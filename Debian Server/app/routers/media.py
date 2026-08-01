"""File streaming and thumbnail generation routes."""
import os
import re
import asyncio
import subprocess
from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import FileResponse, StreamingResponse
from app.database import UPLOAD_DIR, THUMBNAILS_DIR
from app.async_db import db_fetch_one, db_exec

router = APIRouter()


@router.get("/api/stream/{filename:path}",
            summary="Stream a file",
            description="Streams a file with HTTP Range support for partial content (206). Used for video playback with seek support.",
            tags=["Resources"],
            responses={404: {"description": "File not found"}, 416: {"description": "Range not satisfiable"}})
async def stream_file(filename: str, request: Request):
    """Stream a file with HTTP Range support.

    Args:
        filename: Relative path within the upload directory.
        request: FastAPI request for Range header inspection.

    Returns:
        StreamingResponse (206 Partial Content) or FileResponse (200).
    Raises:
        HTTPException 404: If the file does not exist.
        HTTPException 416: If the Range header is invalid.
    """
    if ".." in filename or filename.startswith("/"):
        raise HTTPException(status_code=400, detail="Invalid filename")  # i18n: user-facing error message
    file_path = os.path.normpath(os.path.join(UPLOAD_DIR, filename))
    if not file_path.startswith(os.path.normpath(UPLOAD_DIR)):
        raise HTTPException(status_code=400, detail="Invalid filename")  # i18n: user-facing error message
    if not await asyncio.to_thread(os.path.exists, file_path):
        raise HTTPException(status_code=404, detail="File not found")  # i18n: user-facing error message
    file_size = await asyncio.to_thread(os.path.getsize, file_path)
    range_header = request.headers.get("range")
    if range_header:
        try:
            range_val = range_header.replace("bytes=", "")
            if range_val.startswith("-"):
                suffix = int(range_val[1:])
                start = max(0, file_size - suffix)
                end = file_size - 1
            else:
                start_str, _, end_str = range_val.partition("-")
                start = int(start_str) if start_str else 0
                end = int(end_str) if end_str else file_size - 1
        except ValueError:
            raise HTTPException(status_code=400, detail="Malformed Range header")  # i18n: user-facing error message
        if start >= file_size:
            raise HTTPException(status_code=416, detail="Range not satisfiable")  # i18n: user-facing error message
        content_length = end - start + 1

        async def _stream_chunk():
            file_handle = await asyncio.to_thread(open, file_path, "rb")
            try:
                await asyncio.to_thread(file_handle.seek, start)
                remaining = content_length
                while remaining > 0:
                    chunk = await asyncio.to_thread(file_handle.read, min(65536, remaining))
                    if not chunk:
                        break
                    remaining -= len(chunk)
                    yield chunk
            finally:
                await asyncio.to_thread(file_handle.close)

        return StreamingResponse(
            _stream_chunk(),
            status_code=206,
            media_type="application/octet-stream",
            headers={
                "Content-Range": f"bytes {start}-{end}/{file_size}",
                "Content-Length": str(content_length),
                "Accept-Ranges": "bytes",
            }
        )
    return FileResponse(file_path, headers={"Accept-Ranges": "bytes"})


def _find_video_thumb_time(file_path: str, max_search: int = 30) -> float:
    """Find a suitable thumbnail timestamp by skipping black intros via ffmpeg blackdetect."""
    try:
        result = subprocess.run(
            ["ffmpeg", "-i", file_path, "-vf", "blackdetect=d=0.3:pix_th=0.1",
             "-f", "null", "-"],
            capture_output=True, text=True, timeout=30
        )
        # ffmpeg blackdetect prints black_start BEFORE black_end per segment
        black_end = None
        for m in re.finditer(r'black_end:([\d.]+)', result.stderr):
            end = float(m.group(1))
            if end > (black_end or 0):
                black_end = end
        if black_end is not None:
            return min(black_end + 1.0, float(max_search))
    except Exception:
        pass
    return 2.0


@router.get("/api/thumbnail/{resource_id}",
            summary="Get resource thumbnail",
            description="Returns a cached or generated thumbnail for a resource. Supports PDF (via PyMuPDF) and video (via ffmpeg with black-intro skip).",
            tags=["Resources"],
            responses={404: {"description": "Resource, file, or thumbnail not found"}, 500: {"description": "Thumbnail generation error"}})
async def resource_thumbnail(resource_id: str):
    """Get a thumbnail image for a resource.

    Args:
        resource_id: The resource database id.

    Returns:
        PNG image (FileResponse) or 404.
    Raises:
        HTTPException 404: If resource, file, or thumbnail is unavailable.
        HTTPException 500: If thumbnail generation fails unexpectedly.
    """
    row = await db_fetch_one(
        "SELECT id, filename, resource_type FROM resources WHERE id = ?", (resource_id,))
    table = "resources"
    if not row:
        row = await db_fetch_one(
            "SELECT id, filename, resource_type FROM course_resources WHERE id = ?", (resource_id,))
        table = "course_resources"
    if not row:
        raise HTTPException(status_code=404, detail="Resource not found")  # i18n: user-facing error message
    file_path = os.path.join(UPLOAD_DIR, row["filename"]) if row["filename"] else None
    rtype = row["resource_type"]
    thumb_path = os.path.join(THUMBNAILS_DIR, f"{resource_id}.png")
    if await asyncio.to_thread(os.path.exists, thumb_path):
        return FileResponse(thumb_path, media_type="image/png")
    if not await asyncio.to_thread(os.path.exists, file_path):
        raise HTTPException(status_code=404, detail="File not found")  # i18n: user-facing error message
    page_count = 0
    duration_seconds = 0
    try:
        if rtype in ("textbook", "notes", "pyq", "pastPaper"):
            try:
                import fitz

                def _gen_pdf_thumb(fp, tp):
                    """Generate a 0.3x PNG thumbnail from the first page of a PDF. Runs in worker thread."""
                    doc = fitz.open(fp)
                    try:
                        pix = doc[0].get_pixmap(matrix=fitz.Matrix(0.3, 0.3))
                        pix.save(tp)
                        return doc.page_count
                    finally:
                        doc.close()
                page_count = await asyncio.to_thread(_gen_pdf_thumb, file_path, thumb_path)
            except ImportError:
                raise HTTPException(status_code=404, detail="Thumbnail unavailable (PyMuPDF not installed)")  # i18n: user-facing error message
        elif rtype in ("videos", "khan"):
            thumb_time = await asyncio.to_thread(_find_video_thumb_time, file_path)
            ss = f"{int(thumb_time // 3600):02d}:{int((thumb_time % 3600) // 60):02d}:{int(thumb_time % 60):02d}"
            result = await asyncio.to_thread(lambda: subprocess.run(
                ["ffmpeg", "-i", file_path, "-ss", ss, "-vframes", "1", "-vf", "scale=320:-1", thumb_path, "-y"],
                capture_output=True, timeout=15
            ))
            if result.returncode != 0 or not await asyncio.to_thread(os.path.exists, thumb_path):
                raise HTTPException(status_code=404, detail="Thumbnail generation failed")  # i18n: user-facing error message

            def _probe_duration(fp):
                try:
                    probe = subprocess.run(
                        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", fp],
                        capture_output=True, text=True, timeout=15
                    )
                    return round(float(probe.stdout.strip()))
                except Exception:
                    return 0
            duration_seconds = await asyncio.to_thread(_probe_duration, file_path)
        else:
            raise HTTPException(status_code=404, detail="No thumbnail for this type")  # i18n: user-facing error message
        sets, params = [], []
        if page_count:
            sets.append("page_count = ?")
            params.append(page_count)
        if duration_seconds:
            sets.append("duration_seconds = ?")
            params.append(duration_seconds)
        if sets:
            params.append(resource_id)
            await db_exec(f"UPDATE {table} SET {', '.join(sets)} WHERE id = ?", tuple(params))
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Thumbnail error: {e}")  # i18n: user-facing error message
    return FileResponse(thumb_path, media_type="image/png")
