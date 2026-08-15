"""Hub-to-hub federation: peer pairing, signed requests, and LAN discovery.

A peer is another Lumina hub on the same LAN. After pairing, both hubs
authenticate every ``/peer/*`` request with their own Ed25519 private key;
the receiver verifies against the peer's public key stored at pairing time.
Only approved resources are ever exchanged -- student data never leaves its
own hub.

Pairing flow:
1. Hub A calls ``GET /peer/hello`` on hub B to confirm it is reachable.
2. Hub A posts B's 6-digit pairing code (shown on B's Settings page) to B,
   but only as a key-confirmation proof: ``key_proof = hmac_sha256(
   key=code, msg=public key)``. The code itself never travels the wire.
3. B verifies the proof against its own code, stores A's public key, and
   replies with the same proof over B's own public key.
4. Every later request carries ``X-Peer-Sig`` / ``X-Peer-Ts`` /
   ``X-Peer-Nonce`` headers. The signature is Ed25519 over
   ``f"{ts}:{path_with_query}"`` made with the sender's private key. The
   receiver verifies timestamp (within 300s), signature against the sender's
   stored public key, and a one-time nonce to prevent replay.

The 6-digit code has only 10^6 entropy, so it must never be used to sign
requests directly -- anyone who sees one signed request could brute-force it
offline and forge ``X-Peer-Sig``. Using per-hub Ed25519 keys means the code
is a bootstrap credential only; capturing it does not let an attacker
impersonate a hub after pairing.
"""

import asyncio
import hashlib
import hmac
import logging
import os
import secrets
import socket
import time
import uuid

from fastapi import HTTPException, Request
from fastapi.responses import FileResponse, StreamingResponse

from app.async_db import db_exec, db_fetch, db_fetch_one
from app.database import UPLOAD_DIR

logger = logging.getLogger("lumina.peer")

DATA_DIR = "data"
KEY_PATH = os.path.join(DATA_DIR, "peer_key.pem")
CODE_TTL = 600          # pairing code lifetime, seconds
MAX_SIG_SKEW = 300      # accepted peer clock skew, seconds
_NONCE_TTL = 300        # replay-protection window
_NONCE_MAX = 1000

# ponytail: in-memory nonce cache -- single-hub, fine for a LAN of hubs.
_nonce_cache: dict[str, float] = {}   # nonce -> expiry timestamp
_pairing_code: str | None = None
_pairing_code_expiry: float = 0.0


class PeerManager:
    """Singleton managing this hub's keypair and pairing state."""

    _instance: "PeerManager | None" = None

    def __new__(cls) -> "PeerManager":
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance

    def __init__(self) -> None:
        self._private_key = None
        self._public_key_pem: str | None = None

    def _load_keypair(self) -> None:
        """Load the Ed25519 keypair from disk, generating it on first use."""
        if self._private_key is not None:
            return
        from cryptography.hazmat.primitives import serialization
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
        os.makedirs(DATA_DIR, exist_ok=True)
        if os.path.exists(KEY_PATH):
            with open(KEY_PATH, "rb") as f:
                self._private_key = serialization.load_pem_private_key(f.read(), password=None)
        else:
            self._private_key = Ed25519PrivateKey.generate()
            with open(KEY_PATH, "wb") as f:
                f.write(self._private_key.private_bytes(
                    serialization.Encoding.PEM,
                    serialization.PrivateFormat.PKCS8,
                    serialization.NoEncryption(),
                ))
        self._public_key_pem = self._private_key.public_key().public_bytes(
            serialization.Encoding.PEM,
            serialization.PublicFormat.SubjectPublicKeyInfo,
        ).decode()

    @property
    def public_key_pem(self) -> str:
        """This hub's Ed25519 public key in PEM form."""
        self._load_keypair()
        return self._public_key_pem

    def sign(self, data: bytes) -> bytes:
        """Sign [data] with this hub's Ed25519 private key.

        Returns:
            The raw 64-byte Ed25519 signature.
        """
        self._load_keypair()
        return self._private_key.sign(data)

    def generate_pairing_code(self) -> str:
        """Generate and store a fresh 6-digit pairing code (10-minute expiry)."""
        global _pairing_code, _pairing_code_expiry
        self._load_keypair()
        _pairing_code = f"{secrets.randbelow(1_000_000):06d}"
        _pairing_code_expiry = time.time() + CODE_TTL
        logger.info("New pairing code generated (expires in %ds)", CODE_TTL)
        return _pairing_code

    def current_pairing_code(self) -> str | None:
        """Return the active pairing code, or None if expired."""
        if _pairing_code and time.time() < _pairing_code_expiry:
            return _pairing_code
        return None

    async def pair(self, ip_or_url: str, code: str) -> dict:
        """Pair with the hub at ``ip_or_url`` using its 6-digit pairing code.

        Calls the peer's public endpoints, proves knowledge of the code via
        a key-confirmation MAC over our public key, and stores the peer row.

        Args:
            ip_or_url: Host or URL of the peer hub (e.g. ``192.168.1.20``).
            code: The 6-digit pairing code shown on the peer's Settings page.

        Returns:
            Dict with ``id``, ``name``, and ``base_url`` of the new peer.

        Raises:
            HTTPException: 502 if the peer is unreachable, 403 if the code
                is wrong.
        """
        base = normalize_base_url(ip_or_url)
        try:
            hello = await _http_get_json(f"{base}/peer/hello")
        except HTTPException:
            raise
        except Exception as exc:
            logger.warning("Peer hello failed for %s: %s", base, exc)
            raise HTTPException(status_code=502, detail="Could not reach the peer hub")
        my_pub = self.public_key_pem
        try:
            resp = await _http_post_json(
                f"{base}/peer/pair",
                {"key_proof": pairing_proof(code, my_pub), "public_key": my_pub},
                extra_headers={"X-Peer-Name": socket.gethostname()},
            )
        except HTTPException as exc:
            if exc.status_code == 403:
                raise HTTPException(status_code=403, detail="Invalid or expired pairing code")
            raise
        except Exception as exc:
            logger.warning("Peer pair request failed for %s: %s", base, exc)
            raise HTTPException(status_code=502, detail="Could not reach the peer hub")
        if not resp.get("ok"):
            raise HTTPException(status_code=403, detail="Invalid or expired pairing code")
        peer_pub = str(resp.get("public_key") or "")
        peer_proof = str(resp.get("key_proof") or "")
        if not peer_pub or not hmac.compare_digest(peer_proof, pairing_proof(code, peer_pub)):
            raise HTTPException(status_code=403, detail="Peer key confirmation failed")
        peer_id = f"peer-{uuid.uuid4().hex[:8]}"
        name = str(hello.get("name") or "") or f"peer-{_host_of(base)}"
        await db_exec(
            """INSERT INTO peers (id, name, base_url, public_key, ip_address, paired_at)
               VALUES (?, ?, ?, ?, ?, datetime('now'))""",
            (peer_id, name, base, peer_pub, _host_of(base)),
        )
        logger.info("Paired with %s (%s)", name, base)
        return {"id": peer_id, "name": name, "base_url": base}

    async def request_catalog(self, peer: dict) -> list[dict]:
        """Fetch a paired peer's approved resource catalog (signed)."""
        return await fetch_peer_json(peer, "/peer/catalog")


def pairing_proof(code: str, pub_key_pem: str) -> str:
    """Prove knowledge of the pairing code over a public key.

    Key-confirmation MAC: an attacker who captures the code or a public
    key alone cannot forge the proof for a substituted key, so the
    public keys exchanged at pairing time are bound to the code.

    Args:
        code: The 6-digit pairing code.
        pub_key_pem: One hub's Ed25519 public key in PEM form.

    Returns:
        Hex digest of the code-keyed MAC over the public key.
    """
    return hmac.new(code.encode(), pub_key_pem.encode(), hashlib.sha256).hexdigest()


def sign_headers(path_with_query: str) -> dict[str, str]:
    """Build X-Peer-* headers for a signed request.

    Signature is Ed25519 over ``f"{unix_ts}:{path_with_query}"`` made with
    this hub's private key -- the same canonical form the receiver verifies
    against this hub's stored public key.
    """
    ts = str(int(time.time()))
    nonce = secrets.token_hex(16)
    sig = PeerManager().sign(f"{ts}:{path_with_query}".encode()).hex()
    return {"X-Peer-Ts": ts, "X-Peer-Nonce": nonce, "X-Peer-Sig": sig}


def _verify_ed25519(peer_pub_pem: str, data: bytes, sig_hex: str) -> bool:
    """Return whether [sig_hex] is a valid Ed25519 signature over [data]."""
    try:
        from cryptography.hazmat.primitives import serialization
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
        pub = serialization.load_pem_public_key(peer_pub_pem.encode())
        if not isinstance(pub, Ed25519PublicKey):
            return False
        pub.verify(bytes.fromhex(sig_hex), data)
        return True
    except Exception:
        return False


def _nonce_ok(nonce: str) -> bool:
    """Accept a nonce once; reject replays. Evicts expired entries when full."""
    now = time.time()
    if nonce in _nonce_cache:
        return False
    if len(_nonce_cache) >= _NONCE_MAX:
        expired = [k for k, v in _nonce_cache.items() if v < now]
        for k in expired:
            _nonce_cache.pop(k, None)
    _nonce_cache[nonce] = now + _NONCE_TTL
    return True


async def verify_peer_sig(request: Request) -> dict:
    """FastAPI dependency -- require a valid signed request from a paired peer.

    Checks the X-Peer-Ts / X-Peer-Sig / X-Peer-Nonce headers against every
    paired peer's stored Ed25519 public key. Returns the matching peer row.

    Raises:
        HTTPException: 401 for missing, expired, replayed, or unsigned headers.
    """
    ts_h = request.headers.get("x-peer-ts")
    sig = request.headers.get("x-peer-sig")
    nonce = request.headers.get("x-peer-nonce")
    if not (ts_h and sig and nonce):
        raise HTTPException(status_code=401, detail="Missing peer signature headers")
    try:
        ts = int(ts_h)
    except ValueError:
        raise HTTPException(status_code=401, detail="Invalid peer timestamp")
    if abs(time.time() - ts) > MAX_SIG_SKEW:
        raise HTTPException(status_code=401, detail="Peer signature expired")
    if not _nonce_ok(nonce):
        raise HTTPException(status_code=401, detail="Peer request replayed")
    canonical = request.url.path
    if request.url.query:
        canonical += f"?{request.url.query}"
    data = f"{ts_h}:{canonical}".encode()
    for peer in await get_peers():
        pub = peer.get("public_key") or ""
        if not pub:
            continue
        if _verify_ed25519(pub, data, sig):
            return peer
    raise HTTPException(status_code=401, detail="Invalid peer signature")


async def handle_pair_request(key_proof: str, public_key: str, name: str | None, client_ip: str) -> dict:
    """Process an incoming pairing request from another hub.

    Verifies the key-confirmation proof (keyed by our active pairing code)
    over the remote hub's public key, stores the pairing peer (named from
    the X-Peer-Name header or the source IP), and returns our public key
    with our own key-confirmation proof so the peer can verify it.

    Args:
        key_proof: HMAC of the pairing code over the remote public key.
        public_key: The remote hub's Ed25519 public key (PEM).
        name: Optional hub name from the X-Peer-Name header.
        client_ip: Source IP of the pairing request.

    Returns:
        Dict with ``ok``, ``public_key`` (ours), ``key_proof``, and ``id``.

    Raises:
        HTTPException: 403 if the code is wrong or expired.
    """
    if not _pairing_code or not key_proof or time.time() > _pairing_code_expiry:
        raise HTTPException(status_code=403, detail="Invalid or expired pairing code")
    if not public_key or not hmac.compare_digest(key_proof, pairing_proof(_pairing_code, public_key)):
        raise HTTPException(status_code=403, detail="Invalid or expired pairing code")
    my_pub = PeerManager().public_key_pem
    peer_id = f"peer-{uuid.uuid4().hex[:8]}"
    host = client_ip or "unknown"
    await db_exec(
        """INSERT INTO peers (id, name, base_url, public_key, ip_address, paired_at)
           VALUES (?, ?, ?, ?, ?, datetime('now'))""",
        (peer_id, name or f"peer-{host}", f"http://{host}:8000", public_key, host),
    )
    logger.info("Incoming pairing from %s (%s)", name or host, host)
    return {"ok": True, "public_key": my_pub, "key_proof": pairing_proof(_pairing_code, my_pub), "id": peer_id}


async def get_peers() -> list[dict]:
    """Return all paired peers ordered by name."""
    rows = await db_fetch("SELECT * FROM peers ORDER BY name")
    return [dict(r) for r in rows]


async def get_peer(peer_id: str) -> dict | None:
    """Return a single paired peer by id, or None."""
    row = await db_fetch_one("SELECT * FROM peers WHERE id = ?", (peer_id,))
    return dict(row) if row else None


async def fetch_file(peer: dict, resource_id: str, range_header: str | None) -> tuple[int, dict, object]:
    """Stream a file from a paired peer, forwarding the Range header.

    Args:
        peer: The peer row from the database.
        resource_id: The resource id on the peer hub.
        range_header: The client's raw ``Range`` header to forward, if any.

    Returns:
        Tuple of (status_code, response headers, async body generator).
        The generator closes the underlying connection when exhausted.

    Raises:
        HTTPException: 502 if the peer is unreachable, otherwise the peer's
            status code when it rejects the request.
    """
    import httpx
    path = f"/peer/file/{resource_id}"
    headers = sign_headers(path)
    if range_header:
        headers["Range"] = range_header
    client = httpx.AsyncClient(timeout=httpx.Timeout(300.0, connect=10.0))
    try:
        req = client.build_request("GET", peer["base_url"] + path, headers=headers)
        resp = await client.send(req, stream=True)
    except Exception as exc:
        await client.aclose()
        logger.warning("Peer file fetch failed for %s: %s", peer.get("base_url"), exc)
        raise HTTPException(status_code=502, detail="Peer file stream failed")
    if resp.status_code >= 400:
        await resp.aclose()
        await client.aclose()
        raise HTTPException(status_code=resp.status_code, detail="Peer file unavailable")
    out_headers = {
        k: v for k, v in resp.headers.items()
        if k.lower() in ("content-range", "accept-ranges", "content-type", "content-length")
    }

    async def _body():
        """Stream the peer's response body in 64KB chunks, closing both handles."""
        try:
            async for chunk in resp.aiter_bytes(65536):
                yield chunk
        finally:
            await resp.aclose()
            await client.aclose()

    return resp.status_code, out_headers, _body()


async def fetch_peer_json(peer: dict, path_with_query: str) -> dict:
    """Signed GET a peer endpoint and parse its JSON body.

    Args:
        peer: The peer row from the database.
        path_with_query: Endpoint path and query to sign and request, e.g.
            ``/peer/zim/search?query=x``.

    Returns:
        The parsed JSON body.

    Raises:
        HTTPException: 502 when the peer is unreachable; forwards the peer's
            status code when it rejects the request (>=400).
    """
    try:
        return await _http_get_json(
            peer["base_url"] + path_with_query,
            headers=sign_headers(path_with_query),
        )
    except HTTPException:
        raise
    except Exception as exc:
        logger.warning("Peer JSON fetch failed for %s: %s", peer.get("base_url"), exc)
        raise HTTPException(status_code=502, detail="Peer unreachable")


async def fetch_peer_bytes(peer: dict, path_with_query: str) -> tuple[str, bytes]:
    """Signed GET a peer endpoint and return its raw body.

    Args:
        peer: The peer row from the database.
        path_with_query: Endpoint path and query to sign and request, e.g.
            ``/peer/zim/asset?archive_id=X&path=P``.

    Returns:
        Tuple of (content_type, body bytes).

    Raises:
        HTTPException: 502 when the peer is unreachable; forwards the peer's
            status code when it rejects the request (>=400).
    """
    import httpx
    headers = sign_headers(path_with_query)
    async with httpx.AsyncClient(timeout=httpx.Timeout(60.0, connect=10.0)) as client:
        try:
            resp = await client.get(peer["base_url"] + path_with_query, headers=headers)
        except Exception as exc:
            logger.warning("Peer bytes fetch failed for %s: %s", peer.get("base_url"), exc)
            raise HTTPException(status_code=502, detail="Peer unreachable")
        if resp.status_code >= 400:
            raise HTTPException(status_code=resp.status_code, detail="Peer rejected the request")
        content_type = resp.headers.get("content-type") or "application/octet-stream"
        return content_type, resp.content


async def _stream_local_file(file_path: str, range_header: str | None):
    """Serve a local file with HTTP Range support (mirrors routers/media.py).

    Args:
        file_path: Absolute path to the file in UPLOAD_DIR.
        range_header: The raw ``Range`` header, or None for a full response.

    Returns:
        FileResponse (200) or StreamingResponse (206).

    Raises:
        HTTPException: 404/400/416 mirroring the media router.
    """
    if not await asyncio.to_thread(os.path.exists, file_path):
        raise HTTPException(status_code=404, detail="File not found")
    file_size = await asyncio.to_thread(os.path.getsize, file_path)
    if not range_header:
        return FileResponse(file_path, headers={"Accept-Ranges": "bytes"})
    try:
        val = range_header.replace("bytes=", "")
        if val.startswith("-"):
            start = max(0, file_size - int(val[1:]))
            end = file_size - 1
        else:
            start_str, _, end_str = val.partition("-")
            start = int(start_str) if start_str else 0
            end = int(end_str) if end_str else file_size - 1
    except ValueError:
        raise HTTPException(status_code=400, detail="Malformed Range header")
    if start >= file_size:
        raise HTTPException(status_code=416, detail="Range not satisfiable")
    length = end - start + 1

    async def _chunks():
        """Yield the requested byte range in 64KB chunks, closing the handle afterwards."""
        fh = await asyncio.to_thread(open, file_path, "rb")
        try:
            await asyncio.to_thread(fh.seek, start)
            remaining = length
            while remaining > 0:
                chunk = await asyncio.to_thread(fh.read, min(65536, remaining))
                if not chunk:
                    break
                remaining -= len(chunk)
                yield chunk
        finally:
            await asyncio.to_thread(fh.close)

    return StreamingResponse(
        _chunks(),
        status_code=206,
        media_type="application/octet-stream",
        headers={
            "Content-Range": f"bytes {start}-{end}/{file_size}",
            "Content-Length": str(length),
            "Accept-Ranges": "bytes",
        },
    )


def normalize_base_url(ip_or_url: str) -> str:
    """Normalise an admin-entered host/IP[:port] into an http base URL."""
    s = (ip_or_url or "").strip()
    if not s:
        raise HTTPException(status_code=400, detail="Peer address required")
    if not s.startswith("http"):
        s = "http://" + s
    return s.rstrip("/")


def _host_of(base_url: str) -> str:
    """Extract the host portion of a base URL."""
    return base_url.split("://", 1)[-1].split("/", 1)[0].split(":", 1)[0]


def _own_ips() -> set[str]:
    """Return this host's non-loopback IPv4 addresses."""
    ips = set()
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ip = info[4][0]
            if not ip.startswith("127."):
                ips.add(ip)
    except OSError:
        pass
    return ips


def discover_peers_blocking(timeout: float = 2.5) -> list[dict]:
    """Browse the LAN for EduMeshHub mDNS services (blocking -- call via to_thread).

    Returns:
        List of dicts with ``name``, ``ip``, and ``port``, excluding this host.
        Empty list when zeroconf is unavailable or nothing is found.
    """
    try:
        from zeroconf import ServiceBrowser, ServiceStateChange, Zeroconf
    except ImportError:
        return []
    service_type = "_http._tcp.local."
    found: dict[str, dict] = {}
    own_ips = _own_ips()

    def _on_change(zc, stype, name, state_change):
        """Record newly-announced EduMeshHub services that are not this host."""
        if state_change is not ServiceStateChange.Added or not name.startswith("EduMeshHub"):
            return
        info = zc.get_service_info(stype, name)
        if info and info.addresses:
            ip = socket.inet_ntoa(info.addresses[0])
            if ip in own_ips:
                return
            found[name] = {"name": name, "ip": ip, "port": info.port or 8000}

    zc = Zeroconf()
    browser = ServiceBrowser(zc, service_type, handlers=[_on_change])
    try:
        deadline = time.time() + timeout
        while time.time() < deadline and not found:
            time.sleep(0.1)
    finally:
        browser.cancel()
        zc.close()
    return list(found.values())


async def _http_get_json(url: str, headers: dict | None = None) -> dict:
    """GET a URL and parse its JSON body."""
    import httpx
    async with httpx.AsyncClient(timeout=httpx.Timeout(15.0, connect=5.0)) as client:
        resp = await client.get(url, headers=headers)
        if resp.status_code >= 400:
            raise HTTPException(status_code=resp.status_code, detail="Peer rejected the request")
        return resp.json()


async def _http_post_json(url: str, payload: dict, extra_headers: dict | None = None) -> dict:
    """POST a JSON payload and parse the response."""
    import httpx
    headers = {"Content-Type": "application/json"}
    if extra_headers:
        headers.update(extra_headers)
    async with httpx.AsyncClient(timeout=httpx.Timeout(15.0, connect=5.0)) as client:
        resp = await client.post(url, json=payload, headers=headers)
        if resp.status_code >= 400:
            raise HTTPException(status_code=resp.status_code, detail="Peer rejected the request")
        return resp.json()
