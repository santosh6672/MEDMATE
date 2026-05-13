import os
import logging
import httpx
from fastapi import HTTPException, Header
from dataclasses import dataclass

logger = logging.getLogger(__name__)

# ── Persistent HTTP client (reused across all requests) ───────────────────────
_http_client: httpx.AsyncClient | None = None

def _get_http_client() -> httpx.AsyncClient:
    global _http_client
    if _http_client is None or _http_client.is_closed:
        _http_client = httpx.AsyncClient(timeout=10.0)
    return _http_client


# ── User dataclass (defined once, not per request) ────────────────────────────
@dataclass
class AuthUser:
    id   : str
    email: str


# ── Dependency ────────────────────────────────────────────────────────────────
async def get_current_user(authorization: str = Header(...)) -> AuthUser:
    if not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=401,
            detail="Invalid authorization header — use: Bearer <token>"
        )

    token = authorization.removeprefix("Bearer ").strip()

    if not token:
        raise HTTPException(status_code=401, detail="Token is missing")

    supabase_url  = os.environ.get("SUPABASE_URL")
    supabase_anon = os.environ.get("SUPABASE_ANON_KEY")

    if not supabase_url or not supabase_anon:
        logger.error("SUPABASE_URL or SUPABASE_ANON_KEY not set")
        raise HTTPException(status_code=500, detail="Server configuration error")

    try:
        response = await _get_http_client().get(
            f"{supabase_url}/auth/v1/user",
            headers={
                "Authorization": f"Bearer {token}",
                "apikey"       : supabase_anon,
            },
        )

        if response.status_code != 200:
            logger.warning(f"Supabase auth rejected: {response.status_code}")
            raise HTTPException(status_code=401, detail="Invalid or expired token")

        user_data = response.json()
        logger.info(f"Auth success: {user_data.get('email')}")
        return AuthUser(id=user_data["id"], email=user_data["email"])

    except HTTPException:
        raise
    except httpx.TimeoutException:
        logger.error("Supabase auth timed out")
        raise HTTPException(status_code=503, detail="Auth service timeout — try again")
    except Exception as e:
        logger.error(f"Auth error: {type(e).__name__}: {e}")
        raise HTTPException(status_code=401, detail="Authentication failed")