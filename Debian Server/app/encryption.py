"""AES-256-GCM encryption layer and session token helpers for Lumina EduMesh Hub.

Provides transparent request/response encryption via the EncryptedAPIRoute
route class, as well as token generation, rotation, and invalidation.
"""
import os
import json
import base64
import uuid
import asyncio
import sqlite3
import logging
from fastapi import HTTPException, Request, Response
from fastapi.routing import APIRoute
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from app.database import DB_PATH

NO_ENCRYPT_PATHS = {"/student/token", "/register", "/student/refresh-token", "/student/renew-session", "/token", "/ping", "/api/health", "/generate_204", "/welcome", "/static", "/files"}


def _needs_encryption(path: str) -> bool:
    """Determine whether a request path should be encrypted.

    Paths listed in NO_ENCRYPT_PATHS (login, ping, static files, etc.)
    bypass encryption.

    Args:
        path: The URL path of the incoming request.

    Returns:
        True if the path requires encryption, False otherwise.
    """
    for p in NO_ENCRYPT_PATHS:
        if path.startswith(p):
            return False
    return True


def _aes_gcm_encrypt(data: bytes, key: bytes) -> bytes:
    """Encrypt data using AES-256-GCM.

    Prepends a 12-byte random nonce to the ciphertext.

    Args:
        data: Plaintext bytes to encrypt.
        key: 256-bit AES encryption key.

    Returns:
        Nonce-prepended ciphertext bytes.
    """
    aesgcm = AESGCM(key)
    nonce = os.urandom(12)
    ct = aesgcm.encrypt(nonce, data, None)
    return nonce + ct


def _aes_gcm_decrypt(data: bytes, key: bytes) -> bytes:
    """Decrypt AES-256-GCM ciphertext that was encrypted by _aes_gcm_encrypt.

    Expects the first 12 bytes to be the nonce.

    Args:
        data: Nonce-prepended ciphertext bytes.
        key: 256-bit AES encryption key.

    Returns:
        Decrypted plaintext bytes.
    """
    aesgcm = AESGCM(key)
    nonce = data[:12]
    ct = data[12:]
    return aesgcm.decrypt(nonce, ct, None)


def _make_encryption_key() -> bytes:
    """Generate a new random 256-bit AES encryption key.

    Returns:
        A 32-byte AES-256 key.
    """
    return AESGCM.generate_key(bit_length=256)


class EncryptedAPIRoute(APIRoute):
    """Transparent AES-256-GCM encryption/decryption for API requests.

    Routes listed in NO_ENCRYPT_PATHS bypass encryption.
    Encryption is based on the session token's stored key.
    """

    def get_route_handler(self):
        """Return an encrypted route handler that transparently encrypts and decrypts request bodies.

        Skips encryption for paths listed in NO_ENCRYPT_PATHS. Looks up the
        encryption key from the session token stored in the cookie or
        Authorization header.
        """
        original = super().get_route_handler()

        async def encrypted_handler(request: Request) -> Response:
            """Wrap the original handler with AES-256-GCM encryption and decryption."""
            path = request.url.path
            if not _needs_encryption(path):
                return await original(request)

            encryption_key = None
            token = request.cookies.get("lumina_session") or request.headers.get("Authorization", "").removeprefix("Bearer ")
            if token:
                # Known pattern: _get_key opens its own DB connection (separate from
                # the request handler's connection). Perf impact is ~5ms per request.
                # Optimisation opportunity: cache the encryption key on the request
                # object after token creation to avoid this extra lookup.

                def _get_key():
                    conn = sqlite3.connect(DB_PATH, timeout=5.0)
                    try:
                        cur = conn.cursor()
                        cur.execute("SELECT encryption_key FROM sessions WHERE token = ?", (token,))
                        row = cur.fetchone()
                        if row and row[0]:
                            return base64.b64decode(row[0])
                    finally:
                        conn.close()
                    return None

                encryption_key = await asyncio.to_thread(_get_key)

            if encryption_key:
                enc_body = await request.body()
                if enc_body:
                    try:
                        body = json.loads(enc_body)
                        if "encrypted" in body:
                            raw = base64.b64decode(body["encrypted"])
                            request._body = _aes_gcm_decrypt(raw, encryption_key)
                    except Exception:
                        raise HTTPException(status_code=400, detail="Request decryption failed")

            resp = await original(request)

            if encryption_key and resp.status_code < 400:
                from fastapi.responses import StreamingResponse
                if isinstance(resp, StreamingResponse):
                    return resp
                body = getattr(resp, 'body', None)
                if body:
                    try:
                        encrypted = _aes_gcm_encrypt(body, encryption_key)
                        wrapped = json.dumps({"encrypted": base64.b64encode(encrypted).decode()})
                        return Response(content=wrapped, status_code=resp.status_code, headers=dict(resp.headers), media_type="application/json")
                    except Exception:
                        raise HTTPException(status_code=500, detail="Response encryption failed")

            return resp

        return encrypted_handler


async def _generate_session_token(username: str, role: str, encryption_key: bytes = None, conn: sqlite3.Connection = None) -> dict:
    """Create a new session, refresh token, and persistent key for a user.

    Inserts records into the sessions, refresh_tokens, and persistent_keys
    tables. The session expires on browser close; the refresh token lasts
    7 days; the persistent key lasts 365 days.

    Args:
        username: The user identifier.
        role: Role string (teacher, admin, student).
        encryption_key: Optional 256-bit AES key for request encryption.
        conn: Optional existing DB connection. If provided, the caller is
              responsible for committing and closing; otherwise a new
              connection is opened and closed automatically.

    Returns:
        Dictionary containing session_token, refresh_token, persistent_key,
        and the base64-encoded encryption_key.
    """
    stoken = f"LUMINA_HUB-{uuid.uuid4().hex}"
    rtoken = f"LUMINA_REF-{uuid.uuid4().hex}"
    ptoken = f"LUMINA_PER-{uuid.uuid4().hex}"
    ek = base64.b64encode(encryption_key).decode() if encryption_key else ""

    def _run(conn=conn):
        should_close = conn is None
        if should_close:
            conn = sqlite3.connect(DB_PATH, timeout=5.0)
        try:
            cur = conn.cursor()
            cur.execute("INSERT INTO sessions (token, username, role, encryption_key) VALUES (?, ?, ?, ?)",
                         (stoken, username, role, ek))
            cur.execute("INSERT INTO refresh_tokens (token, username, role, expires_at) VALUES (?, ?, ?, datetime('now', '+7 days'))",
                         (rtoken, username, role))
            cur.execute("INSERT INTO persistent_keys (token, username, role, expires_at) VALUES (?, ?, ?, datetime('now', '+365 days'))",
                         (ptoken, username, role))
            conn.commit()
        finally:
            if should_close:
                conn.close()

    await asyncio.to_thread(_run)
    return {"session_token": stoken, "refresh_token": rtoken, "persistent_key": ptoken, "encryption_key": ek}


async def _invalidate_tokens_for_user(username: str, conn: sqlite3.Connection = None):
    """Delete all sessions, refresh tokens, and persistent keys for a user.

    Used on password change or account deletion to force re-authentication.

    Args:
        username: The user identifier whose tokens should be invalidated.
        conn: Optional existing DB connection. If provided, the caller is
              responsible for committing and closing; otherwise a new
              connection is opened and closed automatically.
    """
    def _run(conn=conn):
        should_close = conn is None
        if should_close:
            conn = sqlite3.connect(DB_PATH, timeout=5.0)
        try:
            cur = conn.cursor()
            cur.execute("DELETE FROM sessions WHERE username = ?", (username,))
            cur.execute("DELETE FROM refresh_tokens WHERE username = ?", (username,))
            cur.execute("DELETE FROM persistent_keys WHERE username = ?", (username,))
            conn.commit()
        finally:
            if should_close:
                conn.close()
    await asyncio.to_thread(_run)
