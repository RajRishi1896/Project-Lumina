"""Course cover images: data-URL parsing and disk storage."""
import asyncio
import base64
import glob
import os
from fastapi import HTTPException

COVER_TYPES = {"image/png": "png", "image/jpeg": "jpg", "image/webp": "webp"}
COVER_MAX_BYTES = 2 * 1024 * 1024


def parse_cover_data_url(data_url: str):
    """Split a cover data-URL into (ext, raw bytes).

    Raises 400 for non-data-URLs, types outside PNG/JPEG/WebP, bad base64,
    or decoded payloads over 2MB.
    """
    header, _, b64 = data_url.partition(",")
    ext = COVER_TYPES.get(header[5:].split(";")[0].strip().lower()) if header.startswith("data:") else None
    if not b64 or ";base64" not in header or ext is None:
        raise HTTPException(status_code=400, detail="Cover image must be a PNG, JPEG, or WebP data-URL.")  # i18n: user-facing error message
    if len(b64) * 3 // 4 > COVER_MAX_BYTES:
        raise HTTPException(status_code=400, detail="Cover image exceeds the 2 MB limit.")  # i18n: user-facing error message
    try:
        raw = base64.b64decode(b64, validate=True)
    except Exception:
        raise HTTPException(status_code=400, detail="Cover image is not valid base64.") from None  # i18n: user-facing error message
    if len(raw) > COVER_MAX_BYTES:
        raise HTTPException(status_code=400, detail="Cover image exceeds the 2 MB limit.")  # i18n: user-facing error message
    return ext, raw


async def save_course_cover(courses_dir: str, course_id: str, data_url):
    """Store or remove a course cover image.

    None leaves the cover untouched; '' removes it; otherwise the data-URL
    is decoded (max 2MB) and written to courses/{course_id}/cover.<ext>,
    replacing any previous cover.* file.

    Returns the stored relative path (served under /files), '' on removal,
    or None when untouched. All disk I/O runs in a worker thread.
    """
    if data_url is None:
        return None
    ext, raw = (None, None) if not data_url else parse_cover_data_url(data_url)

    def _write():
        """Replace cover.* on disk in a single blocking call."""
        course_dir = os.path.join(courses_dir, course_id)
        os.makedirs(course_dir, exist_ok=True)
        for old in glob.glob(os.path.join(course_dir, "cover.*")):
            try:
                os.remove(old)
            except OSError:
                pass
        if raw:
            with open(os.path.join(course_dir, "cover." + ext), "wb") as f:
                f.write(raw)

    await asyncio.to_thread(_write)
    if not data_url:
        return ""
    return "courses/%s/cover.%s" % (course_id, ext)
