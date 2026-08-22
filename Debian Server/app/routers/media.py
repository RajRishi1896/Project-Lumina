"""File streaming, thumbnail generation, and video sprite sheet routes."""
import os
import re
import logging
import asyncio
import subprocess
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import FileResponse, StreamingResponse
from app.database import UPLOAD_DIR, THUMBNAILS_DIR
from app.async_db import db_fetch_one
from app.dependencies import verify_user

router = APIRouter()

# VAAPI hardware decode args, probed once. Empty list on machines without a
# usable /dev/dri device or vaapi ffmpeg build; CPU decode is the fallback.
_vaapi_args: list = []


def _probe_vaapi():
    """Return ffmpeg args for VAAPI hardware decode, or [] if unavailable.

    Probed once at import. VAAPI offloads video decode to the Intel/AMD iGPU
    (the largest CPU cost in thumbnail/sprite generation).
    """
    global _vaapi_args
    try:
        if not os.path.exists("/dev/dri/renderD128"):
            return []
        result = subprocess.run(["ffmpeg", "-hwaccels"], capture_output=True, text=True, timeout=5)
        if result.returncode != 0 or "vaapi" not in result.stdout.lower():
            return []
        _vaapi_args = ["-hwaccel", "vaapi", "-vaapi_device", "/dev/dri/renderD128"]
    except Exception:
        pass
    return _vaapi_args


_vaapi_args = _probe_vaapi()


# ── Single-flight generation locks ───────────────────────────────────────────
# Without these, 250 students opening a brand-new course spawn 250 concurrent
# ffmpeg/PyMuPDF generations for the same resource (a CPU thundering herd on
# the hub's weak CPU). Concurrent requests wait on the lock, then find the
# freshly generated file on the cache re-check.
_gen_locks: dict[str, asyncio.Lock] = {}


def _gen_lock(resource_id: str) -> asyncio.Lock:
    """Return the per-resource generation lock, creating it on first use."""
    return _gen_locks.setdefault(resource_id, asyncio.Lock())


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
        # Clamp end to the last byte: "bytes=0-999999999" on a 1MB file must
        # not advertise a ~1e9 Content-Length the generator cannot fill.
        end = min(end, file_size - 1)
        if end < start:
            # e.g. "bytes=100-50": syntactically unsatisfiable range.
            raise HTTPException(status_code=416, detail="Range not satisfiable")  # i18n: user-facing error message
        content_length = end - start + 1

        async def _stream_chunk():
            """Yield the requested byte range in 64KB chunks, closing the handle afterwards."""
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
    """Find a suitable thumbnail timestamp by skipping black intros via ffmpeg blackdetect.

    The scan input is capped at 60 seconds of media (-t 60) so ffmpeg cannot
    decode entire multi-hour videos looking for black segments; the chosen
    timestamp is additionally clamped to ``max_search``.
    """
    try:
        result = subprocess.run(
            ["ffmpeg", *_vaapi_args, "-i", file_path, "-t", "60",
             "-vf", "blackdetect=d=0.3:pix_th=0.1",
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


async def _resolve_resource(resource_id: str):
    """Resolve a resource row and its on-disk path from either table.

    Args:
        resource_id: The resource database id.

    Returns:
        A tuple of (row, table, file_path), or (None, None, None) if not found.
    """
    row = await db_fetch_one(
        "SELECT id, filename, resource_type, duration_seconds FROM resources WHERE id = ?", (resource_id,))
    table = "resources"
    if not row:
        row = await db_fetch_one(
            "SELECT id, course_id, filename, resource_type, duration_seconds FROM course_resources WHERE id = ?", (resource_id,))
        table = "course_resources"
    if not row:
        return None, None, None
    # Course-resource files live under uploads/courses/{course_id}/resources/,
    # not directly in the uploads root: build the correct path.
    if table == "course_resources":
        file_path = os.path.join(UPLOAD_DIR, "courses", str(row["course_id"]), "resources", row["filename"]) if row["filename"] else None
    else:
        file_path = os.path.join(UPLOAD_DIR, row["filename"]) if row["filename"] else None
    return row, table, file_path


def _probe_duration(file_path: str) -> float:
    """Probe a video's duration in seconds via ffprobe. Returns 0 on failure."""
    try:
        probe = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", file_path],
            capture_output=True, text=True, timeout=15
        )
        return round(float(probe.stdout.strip()))
    except Exception:
        return 0


def _generate_video_sprite(file_path: str, sprite_path: str, interval: float, columns: int, rows: int) -> bool:
    """Render a seek-preview sprite sheet: one 160x90 frame per interval, tiled into a grid.

    Runs inside asyncio.to_thread. Never raises; returns success bool.
    """
    try:
        # fps=1/{interval} samples one frame per interval; tile packs them into the grid.
        result = subprocess.run(
            ["ffmpeg", *_vaapi_args, "-y", "-i", file_path,
             "-vf", f"fps=1/{interval},scale=160:90,tile={columns}x{rows}",
             "-frames:v", "1", "-q:v", "5", sprite_path],
            capture_output=True, timeout=120
        )
        return result.returncode == 0 and os.path.exists(sprite_path)
    except Exception:
        return False


@router.get("/api/thumbnail/{resource_id}",
            summary="Get resource thumbnail",
            description="Returns a cached or generated thumbnail for a resource. Supports PDF (via PyMuPDF) and video (via ffmpeg with black-intro skip).",
            tags=["Resources"],
            responses={404: {"description": "Resource, file, or thumbnail not found"}, 500: {"description": "Thumbnail generation error"}})
async def resource_thumbnail(resource_id: str):
    """Get a thumbnail image for a resource.

    NOTE: intentionally unauthenticated. The Flutter app fetches thumbnails
    via Image.network() with no Authorization header (resource_thumbnail.dart);
    requiring auth here would break every student thumbnail. Abuse is bounded
    by the per-resource single-flight lock and the time-capped ffmpeg scan.

    Args:
        resource_id: The resource database id.

    Returns:
        PNG image (FileResponse) or 404.
    Raises:
        HTTPException 404: If resource, file, or thumbnail is unavailable.
        HTTPException 500: If thumbnail generation fails unexpectedly.
    """
    row, _table, file_path = await _resolve_resource(resource_id)
    if not row:
        raise HTTPException(status_code=404, detail="Resource not found")  # i18n: user-facing error message
    rtype = row["resource_type"]
    thumb_path = os.path.join(THUMBNAILS_DIR, f"{resource_id}.png")
    if await asyncio.to_thread(os.path.exists, thumb_path):
        return FileResponse(thumb_path, media_type="image/png")
    if not file_path or not await asyncio.to_thread(os.path.exists, file_path):
        raise HTTPException(status_code=404, detail="File not found")  # i18n: user-facing error message
    async with _gen_lock(resource_id):
        # Single-flight re-check: another request may have generated the
        # thumbnail while this one waited for the lock.
        if await asyncio.to_thread(os.path.exists, thumb_path):
            return FileResponse(thumb_path, media_type="image/png")
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
                        finally:
                            doc.close()
                    await asyncio.to_thread(_gen_pdf_thumb, file_path, thumb_path)
                except ImportError:
                    raise HTTPException(status_code=404, detail="Thumbnail unavailable (PyMuPDF not installed)")  # i18n: user-facing error message
            elif rtype in ("videos", "khan"):
                thumb_time = await asyncio.to_thread(_find_video_thumb_time, file_path)
                ss = f"{int(thumb_time // 3600):02d}:{int((thumb_time % 3600) // 60):02d}:{int(thumb_time % 60):02d}"
                result = await asyncio.to_thread(lambda: subprocess.run(
                    ["ffmpeg", *_vaapi_args, "-i", file_path, "-ss", ss, "-vframes", "1", "-vf", "scale=320:-1", thumb_path, "-y"],
                    capture_output=True, timeout=15
                ))
                if result.returncode != 0 or not await asyncio.to_thread(os.path.exists, thumb_path):
                    raise HTTPException(status_code=404, detail="Thumbnail generation failed")  # i18n: user-facing error message
            else:
                raise HTTPException(status_code=404, detail="No thumbnail for this type")  # i18n: user-facing error message
        except HTTPException:
            raise
        except Exception as e:
            logging.error(f"thumbnail {resource_id}: {e}", exc_info=True)
            raise HTTPException(status_code=500, detail="Thumbnail generation failed.")  # i18n: user-facing error message
    return FileResponse(thumb_path, media_type="image/png")


@router.get("/api/video/previews/{resource_id}/sprite",
            summary="Get video seek-preview sprite sheet",
            description="Returns the cached JPG sprite sheet for a video resource. The metadata route generates it on first request.",
            tags=["Resources"],
            responses={401: {"description": "Unauthorized"}, 404: {"description": "Sprite not found"}})
async def video_preview_sprite(resource_id: str, user: str = Depends(verify_user)):
    """Get the cached sprite sheet image for a video resource.

    Args:
        resource_id: The resource database id.
        user: Authenticated username (any role; the Flutter app requests this
            through its authenticated Dio client).

    Returns:
        JPEG image (FileResponse).
    Raises:
        HTTPException 404: If no sprite sheet exists yet.
    """
    sprite_path = os.path.join(THUMBNAILS_DIR, f"{resource_id}_previews.jpg")
    if not await asyncio.to_thread(os.path.exists, sprite_path):
        raise HTTPException(status_code=404, detail="Sprite not found")  # i18n: user-facing error message
    return FileResponse(sprite_path, media_type="image/jpeg")


@router.get("/api/video/previews/{resource_id}",
            summary="Get video seek-preview metadata",
            description="Returns sprite sheet metadata for a video resource, generating the sheet on first request. Clients use it for YouTube-style seek preview thumbnails.",
            tags=["Resources"],
            response_model=dict,
            responses={401: {"description": "Unauthorized"}, 404: {"description": "Video or preview unavailable"}, 500: {"description": "Preview generation error"}})
async def video_preview_meta(resource_id: str, user: str = Depends(verify_user)):
    """Get (and lazily generate) the seek-preview sprite sheet for a video.

    Args:
        resource_id: The resource database id.
        user: Authenticated username (any role; the Flutter app requests this
            through its authenticated Dio client).

    Returns:
        JSON metadata describing the sprite grid and sampling interval.
    Raises:
        HTTPException 404: If the resource is not a video, is too short, or generation fails.
    """
    row, _table, file_path = await _resolve_resource(resource_id)
    if not row:
        raise HTTPException(status_code=404, detail="Resource not found")  # i18n: user-facing error message
    if row["resource_type"] not in ("videos", "khan"):
        raise HTTPException(status_code=404, detail="Previews not supported for this resource type")  # i18n: user-facing error message
    if not file_path or not await asyncio.to_thread(os.path.exists, file_path):
        raise HTTPException(status_code=404, detail="File not found")  # i18n: user-facing error message
    duration = row["duration_seconds"] or 0
    if not duration:
        duration = await asyncio.to_thread(_probe_duration, file_path)
    if duration < 16:
        raise HTTPException(status_code=404, detail="Video too short for previews")  # i18n: user-facing error message
    frames = min(60, max(1, int(duration) // 8))
    interval = round(duration / frames, 2)
    columns = 6
    rows = (frames + columns - 1) // columns
    sprite_path = os.path.join(THUMBNAILS_DIR, f"{resource_id}_previews.jpg")
    if not await asyncio.to_thread(os.path.exists, sprite_path):
        async with _gen_lock(resource_id):
            # Single-flight re-check: another request may have generated the
            # sprite sheet while this one waited for the lock.
            if not await asyncio.to_thread(os.path.exists, sprite_path):
                ok = await asyncio.to_thread(_generate_video_sprite, file_path, sprite_path, interval, columns, rows)
                if not ok:
                    raise HTTPException(status_code=404, detail="Preview generation failed")  # i18n: user-facing error message
    return {
        "resource_id": resource_id,
        "sprite_url": f"/api/video/previews/{resource_id}/sprite",
        "frame_w": 160,
        "frame_h": 90,
        "columns": columns,
        "rows": rows,
        "frames": frames,
        "interval_seconds": interval,
    }
