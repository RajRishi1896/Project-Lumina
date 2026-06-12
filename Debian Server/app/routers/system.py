"""System routes — health, ping, captive portal, static files, whoami."""
import time
import os
from fastapi import APIRouter, Depends, HTTPException, Request, Response
from fastapi.responses import FileResponse, HTMLResponse, RedirectResponse
from app.database import _startup_time
from app.dependencies import _extract_user

router = APIRouter()


def _error_response(reason: str) -> FileResponse:
    """Generate an error response for unauthorized or missing resources.

    Args:
        reason: The error reason string. "access_denied" returns 403; all others return 401.

    Returns:
        FileResponse serving the static error.html page, or a plain HTML fallback.
    """
    err_path = os.path.join("static", "error.html")
    if os.path.isfile(err_path):
        return FileResponse(err_path, status_code=403 if reason in ("access_denied",) else 401)
    return HTMLResponse(content=f"<h1>Access Denied</h1><p>{reason}</p><a href='/welcome'>Back to Home</a>", status_code=403)


@router.get("/api/health", summary="Health check endpoint", description="Returns server status and uptime in seconds since the application started.", tags=["System"], responses={200: {"description": "Server is healthy with uptime info"}})
async def health():
    """Check the server's health and return uptime.

    Returns:
        Dict with status and uptime in seconds.
    """
    return {"status": "ok", "uptime": time.time() - _startup_time}


@router.get("/ping", summary="Ping server", description="Simple liveness probe. Returns a pong response used by the Flutter app's connectivity heartbeat.", tags=["System"], responses={200: {"description": "Pong response indicating the server is alive"}})
async def ping_server():
    """Respond to a liveness ping.

    Returns:
        Dict with a pong status.
    """
    return {"status": "pong"}


@router.get("/api/task/{task_id}",
            summary="Poll background task status",
            description="Returns the current status and result of a background task previously enqueued via the task queue. Clients should poll this endpoint with the task ID returned by an enqueue operation.",
            tags=["System"],
            responses={200: {"description": "Task status and result (if completed)"}, 404: {"description": "Task ID not found"}})
async def get_task_status(task_id: str):
    """Get the status and result of a background task.

    Args:
        task_id: The task UUID returned by an enqueue operation.

    Returns:
        Dict with task id, type, status, result, and error fields.

    Raises:
        HTTPException 404: If the task ID is unknown.
    """
    from app.task_queue import get_task
    task = get_task(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="Task not found")
    return task


@router.get("/generate_204", summary="Captive portal detection bypass", description="Returns a 204 No Content response to trick Android's captive portal detection into thinking the network has internet access, preventing it from switching to cellular data.", tags=["System"], responses={204: {"description": "Empty response for captive portal bypass"}})
async def generate_204():
    """Return a 204 response for Android captive portal detection.

    Tricks Android into thinking the hotspot has internet access so it does not
    switch to cellular data or show a captive portal warning.

    Returns:
        Response with status code 204 and no body.
    """
    return Response(status_code=204)


@router.get("/welcome", summary="Serve welcome page", description="Serves the captive portal welcome landing page. This is the first page users see when connecting to the hotspot.", tags=["System"], responses={200: {"description": "Welcome page HTML"}})
@router.get("/welcome.html", summary="Serve welcome page (.html)", description="Alternate URL for the welcome page. Both /welcome and /welcome.html serve the same content.", tags=["System"])
async def welcome_page():
    """Serve the welcome landing page.

    Returns:
        FileResponse serving static/welcome.html.
    """
    return FileResponse("static/welcome.html")


@router.get("/dashboard", summary="Serve teacher dashboard", description="Serves the main teacher dashboard HTML page. Requires a valid lumina_session cookie; redirects to /welcome if not authenticated.", tags=["System"], responses={200: {"description": "Dashboard HTML page"}, 302: {"description": "Redirect to welcome page if not authenticated"}})
@router.get("/index.html", summary="Serve teacher dashboard (.html)", description="Alternate URL for the dashboard. Requires a valid session cookie.", tags=["System"])
async def get_dashboard(request: Request):
    """Serve the teacher dashboard page.

    Args:
        request: The incoming HTTP request used to check for a session cookie.

    Returns:
        FileResponse serving static/index.html if authenticated, or a RedirectResponse to /welcome.
    """
    if not request.cookies.get("lumina_session"):
        return RedirectResponse(url="/welcome")
    return FileResponse("static/index.html")


@router.get("/whoami", summary="Get current user identity", description="Returns the username and role of the currently authenticated user based on their session token.", tags=["System"], responses={200: {"description": "User identity retrieved"}, 401: {"description": "Not authenticated or invalid session"}})
async def whoami(user: dict = Depends(_extract_user)):
    """Get the currently authenticated user's identity.

    Args:
        user: The extracted user dict (username and role) injected by the _extract_user dependency.

    Returns:
        Dict with the username and role of the current user.
    """
    return {"username": user["username"], "role": user["role"]}


@router.api_route("/", methods=["GET", "HEAD"], summary="Root redirect", description="Redirects the root URL to the welcome page. Handles both GET and HEAD requests.", tags=["System"])
async def root_redirect():
    """Redirect root requests to the welcome page.

    Returns:
        RedirectResponse to /welcome.
    """
    return RedirectResponse(url="/welcome")


@router.get("/static/{path:path}", summary="Serve static files", description="Serves static files from the static/ directory. CSS and JS files are publicly accessible. HTML pages require teacher or admin authentication. Session expiry returns a 401-style error page.", tags=["System"], responses={200: {"description": "Requested static file"}, 401: {"description": "Session expired or not authenticated"}, 403: {"description": "Access denied (insufficient role)"}, 404: {"description": "File not found"}})
async def serve_static(path: str, request: Request):
    """Serve a static file from the static/ directory.

    Public files (CSS, JS, welcome page) are served without authentication.
    Protected HTML pages require a teacher or admin session.

    Args:
        path: The requested file path relative to the static/ directory.
        request: The incoming HTTP request used for authentication checks.

    Returns:
        FileResponse with the requested file, or an error response.

    Raises:
        HTTPException 401: Propagated from _extract_user if the session is invalid.
    """
    if path.endswith(".html"):
        clean = path[:-5]
        return RedirectResponse(url=f"/static/{clean}", status_code=301)

    def _resolve(p: str) -> str | None:
        fp = os.path.join("static", p)
        if os.path.isfile(fp):
            return fp
        if os.path.isfile(fp + ".html"):
            return fp + ".html"
        return None

    if path.startswith("css/") or path.startswith("js/") or path.startswith("assets/") or path.startswith("lang/") or path in ("welcome.html", "welcome", "error.html", "error"):
        file_path = _resolve(path)
        if file_path:
            return FileResponse(file_path)
        return _error_response("not_found")

    try:
        user = await _extract_user(request)
        if user["role"] not in ("teacher", "admin"):
            return _error_response("access_denied")
        file_path = _resolve(path)
        if file_path:
            return FileResponse(file_path)
        return _error_response("not_found")
    except HTTPException as e:
        if e.status_code == 401:
            return _error_response("session_expired")
        return _error_response("access_denied")
