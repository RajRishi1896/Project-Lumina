"""Shared thumbnail generation utilities for teacher/admin routes."""
import os
import re
import asyncio
import shutil
import subprocess
import logging

thumbnail_semaphore = asyncio.Semaphore(2)


async def get_zim_upload_max_size():
    """Calculate max ZIM upload size (total disk minus 1 GB reserve)."""
    try:
        _disk = await asyncio.to_thread(shutil.disk_usage, "/")
        return max(0, _disk.total - 1024 * 1024 * 1024)
    except Exception:
        return 5000 * 1024 * 1024


def find_video_thumb_time(file_path: str, max_search: int = 30) -> float:
    """Find a suitable thumbnail timestamp by skipping black intros via ffmpeg blackdetect.

    Args:
        file_path: Path to the video file.
        max_search: Maximum seconds into the video to search.

    Returns:
        Timestamp in seconds for the thumbnail, defaulting to 2.0 on failure.
    """
    try:
        result = subprocess.run(
            ["ffmpeg", "-i", file_path, "-vf", "blackdetect=d=0.3:pix_th=0.1",
             "-f", "null", "-"],
            capture_output=True, text=True, timeout=30
        )
        black_end = None
        for m in re.finditer(r'black_duration:([\d.]+)\s*black_start:([\d.]+)',
                             result.stderr):
            duration = float(m.group(1))
            start = float(m.group(2))
            end = start + duration
            if end > (black_end or 0):
                black_end = end
        if black_end is not None:
            t = black_end + 1.0
            return min(t, float(max_search))
    except Exception:
        pass
    return 2.0
