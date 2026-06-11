"""Thumbnail generation worker — runs as a background task.

Provides the ``generate_thumbnail`` handler that can be registered
with the task queue for deferred thumbnail processing.
"""
import logging
import os
import subprocess

UPLOAD_DIR = "uploads"
THUMBNAILS_DIR = "thumbnails"


async def generate_thumbnail(params: dict) -> dict:
    """Generate a thumbnail for the given resource file.

    Dispatches to the appropriate generator based on file extension:
    ``ffmpeg`` for video files, ``PyMuPDF`` for PDFs. Both I/O-bound
    and CPU-bound steps are offloaded to a thread pool.

    Args:
        params: Must contain ``resource_id`` (int or str) and
            ``filename`` (str).

    Returns:
        Dict with ``thumb_path`` (str or None) and ``cached`` (bool).

    Raises:
        FileNotFoundError: If the source file does not exist.
    """
    import asyncio

    resource_id = params["resource_id"]
    filename = params["filename"]
    filepath = os.path.join(UPLOAD_DIR, filename)

    if not os.path.exists(filepath):
        raise FileNotFoundError("File not found: {0}".format(filepath))

    ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
    thumb_path = os.path.join(THUMBNAILS_DIR, "{0}.png".format(resource_id))

    if os.path.exists(thumb_path):
        return {"thumb_path": thumb_path, "cached": True}

    os.makedirs(THUMBNAILS_DIR, exist_ok=True)

    if ext in ("mp4", "webm", "mkv", "avi", "mov"):
        await asyncio.to_thread(_generate_video_thumb, filepath, thumb_path)
    elif ext == "pdf":
        await asyncio.to_thread(_generate_pdf_thumb, filepath, thumb_path)

    exists = os.path.exists(thumb_path)
    return {"thumb_path": thumb_path if exists else None, "cached": False}


def _generate_video_thumb(filepath: str, thumb_path: str):
    """Generate a 320px-wide PNG thumbnail from a video via ffmpeg.

    Uses the ``blackdetect`` filter to skip intro black frames and
    picks the first non-black frame plus one second, capped at 30 s.

    Args:
        filepath: Path to the source video file.
        thumb_path: Destination path for the PNG thumbnail.
    """
    try:
        probe = subprocess.run(
            [
                "ffprobe",
                "-v",
                "error",
                "-show_entries",
                "format=duration",
                "-of",
                "default=noprint_wrappers=1:nokey=1",
                filepath,
            ],
            capture_output=True,
            text=True,
            timeout=10,
        )
        duration = float(probe.stdout.strip() or 0)
        thumb_time = min(30.0, max(1.0, duration * 0.15))

        detect = subprocess.run(
            [
                "ffmpeg",
                "-i",
                filepath,
                "-vf",
                "blackdetect=d=0.5:pix_th=0.1",
                "-f",
                "null",
                "-",
            ],
            capture_output=True,
            text=True,
            timeout=30,
        )
        for line in detect.stderr.split("\n"):
            if "black_duration" in line:
                parts = line.split()
                for p in parts:
                    if p.startswith("black_start:"):
                        start = float(p.split(":")[1])
                        thumb_time = min(30.0, start + 1.0)
                        break
                break
        subprocess.run(
            [
                "ffmpeg",
                "-y",
                "-i",
                filepath,
                "-ss",
                str(thumb_time),
                "-vframes",
                "1",
                "-vf",
                "scale=320:-1",
                thumb_path,
            ],
            capture_output=True,
            timeout=30,
        )
    except Exception as e:
        logging.warning("Video thumb failed for %s: %s", filepath, e)


def _generate_pdf_thumb(filepath: str, thumb_path: str):
    """Generate a 0.3x-scale PNG thumbnail from the first PDF page via PyMuPDF.

    Args:
        filepath: Path to the source PDF file.
        thumb_path: Destination path for the PNG thumbnail.
    """
    try:
        import fitz

        doc = fitz.open(filepath)
        try:
            if doc.page_count > 0:
                page = doc[0]
                mat = fitz.Matrix(0.3, 0.3)
                pix = page.get_pixmap(matrix=mat)
                pix.save(thumb_path)
        finally:
            doc.close()
    except ImportError:
        logging.warning("PyMuPDF not available, skipping PDF thumbnail")
    except Exception as e:
        logging.warning("PDF thumb failed for %s: %s", filepath, e)
