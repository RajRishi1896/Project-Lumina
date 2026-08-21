"""System routes: health, ping, captive portal, static files, whoami."""
import os
import asyncio
from fastapi import APIRouter, Depends, HTTPException, Request, Response
from fastapi.responses import FileResponse, HTMLResponse, PlainTextResponse, RedirectResponse
from app.dependencies import _extract_user
from app.models import StatusResponse, WhoamiResponse

router = APIRouter()

STATIC_DIR = "static"


async def _error_response(reason: str) -> HTMLResponse:
    """Render error page with the given reason."""
    error_page = os.path.join(STATIC_DIR, "error.html")
    try:
        def _read_error_page():
            """Read error.html from disk inside the thread pool."""
            with open(error_page, "r", encoding="utf-8") as f:
                return f.read()
        content = await asyncio.to_thread(_read_error_page)
    except FileNotFoundError:
        return HTMLResponse("<h1>Error</h1>", status_code=404)  # i18n: fallback error page when error.html file is missing
    reasons = {
        "not_found": ("Page Not Found", "The page you are looking for does not exist.", "notfound", "Not Found"),  # i18n: error page title and message
        "access_denied": ("Access Denied", "You do not have permission to view this page.", "denied", "Access Denied"),  # i18n: error page title and message
        "session_expired": ("Session Expired", "Your session has expired. Please log in again.", "expired", "Session Expired"),  # i18n: error page title and message
    }
    title, message, badge_cls, badge_text = reasons.get(reason, ("Error", "An error occurred.", "notfound", "Error"))
    content = content.replace("{{TITLE}}", title).replace("{{MESSAGE}}", message).replace("{{BADGE}}", badge_cls).replace("{{BADGE_TEXT}}", badge_text)
    return HTMLResponse(content, status_code={
        "not_found": 404, "access_denied": 403, "session_expired": 401
    }.get(reason, 500))


@router.get("/ping", response_model=StatusResponse, summary="Ping server", description="Simple liveness probe. Returns a pong response used by the Flutter app's connectivity heartbeat.", tags=["System"], responses={200: {"description": "Pong response indicating the server is alive"}})
async def ping_server():
    """Respond to a liveness ping.

    Returns:
        Dict with a pong status.
    """
    return {"status": "pong"}


@router.get("/generate_204", summary="Captive portal detection bypass", description="Returns a 204 No Content response to trick Android's captive portal detection into thinking the network has internet access, preventing it from switching to cellular data.", tags=["System"], responses={204: {"description": "Empty response for captive portal bypass"}})
async def generate_204():
    """Return a 204 response for Android captive portal detection.

    Tricks Android into thinking the hotspot has internet access so it does not
    switch to cellular data or show a captive portal warning.

    Returns:
        Response with status code 204 and no body.
    """
    return Response(status_code=204)


@router.get("/connecttest.txt", include_in_schema=False)
async def windows_connect_test():
    """Windows 10/11 captive portal probe: must return exact string."""
    return PlainTextResponse("Microsoft Connect Test")


@router.get("/ncsi.txt", include_in_schema=False)
async def windows_ncsi():
    """Windows NCSI captive portal probe."""
    return PlainTextResponse("Microsoft NCSI")


@router.get("/hotspot-detect.html", include_in_schema=False)
async def ios_hotspot_detect():
    """iOS/macOS captive portal probe."""
    return HTMLResponse("<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>")


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
    try:
        user = await _extract_user(request)
        if user["role"] not in ("teacher", "admin"):
            return RedirectResponse(url="/welcome")
    except HTTPException:
        return RedirectResponse(url="/welcome")
    return FileResponse("static/index.html")


@router.get("/whoami", response_model=WhoamiResponse, summary="Get current user identity", description="Returns the username and role of the currently authenticated user based on their session token.", tags=["System"], responses={200: {"description": "User identity retrieved"}, 401: {"description": "Not authenticated or invalid session"}})
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
    if ".." in path or path.startswith("/"):
        return await _error_response("not_found")
    if path.endswith(".html"):
        clean = path[:-5]
        qs = "?" + request.url.query if request.url.query else ""
        return RedirectResponse(url=f"/static/{clean}{qs}", status_code=301)

    def _resolve(p: str) -> str | None:
        """Resolve a static path to an existing file, appending .html when needed."""
        fp = os.path.join("static", p)
        if os.path.isfile(fp):
            return fp
        if os.path.isfile(fp + ".html"):
            return fp + ".html"
        return None

    if path.startswith("css/") or path.startswith("js/") or path.startswith("assets/") or path.startswith("lang/") or path.startswith("fonts/") or path in ("welcome.html", "welcome"):
        file_path = _resolve(path)
        if file_path:
            return FileResponse(file_path)
        return await _error_response("not_found")

    if path in ("error.html", "error"):
        reason = request.query_params.get("reason", "not_found")
        return await _error_response(reason)

    try:
        user = await _extract_user(request)
        if user["role"] not in ("teacher", "admin"):
            return await _error_response("access_denied")
        if user["role"] == "teacher" and path in ("manage-danger", "manage-danger.html"):
            return await _error_response("access_denied")
        file_path = _resolve(path)
        if file_path:
            return FileResponse(file_path)
        return await _error_response("not_found")
    except HTTPException as e:
        if e.status_code == 401:
            return await _error_response("session_expired")
        return await _error_response("access_denied")
