"""Stateless session tokens.

There is no sessions table yet, so a citizen "session token" is a signed,
self-describing string: `<citizen_id>.<expiry>.<hmac>`. The HMAC is keyed on
the app secret, so the token can be verified later without a DB lookup.

This is intentionally lightweight for the current milestone. When real session
management / refresh tokens land, [create_session_token] can be swapped for a
JWT library or a server-side session store without changing call sites.
"""

import base64
import hashlib
import hmac
import time

from app.core.config import get_settings

# Token lifetime: 30 days.
_TOKEN_TTL_SECONDS = 60 * 60 * 24 * 30


def _secret() -> bytes:
    settings = get_settings()
    # Fall back to a fixed dev secret so tokens work before a real secret is
    # configured. TODO: require SESSION_SECRET in production.
    secret = settings.session_secret or "civicroute-dev-secret-change-me"
    return secret.encode("utf-8")


def _sign(payload: str) -> str:
    digest = hmac.new(_secret(), payload.encode("utf-8"), hashlib.sha256).digest()
    return base64.urlsafe_b64encode(digest).decode("utf-8").rstrip("=")


def create_session_token(citizen_id: str) -> str:
    """Return a signed session token for the given citizen."""
    expiry = int(time.time()) + _TOKEN_TTL_SECONDS
    payload = f"{citizen_id}.{expiry}"
    return f"{payload}.{_sign(payload)}"


def verify_session_token(token: str) -> str | None:
    """Return the citizen_id if the token is valid and unexpired, else None."""
    try:
        citizen_id, expiry_str, signature = token.rsplit(".", 2)
    except ValueError:
        return None
    payload = f"{citizen_id}.{expiry_str}"
    if not hmac.compare_digest(signature, _sign(payload)):
        return None
    if int(expiry_str) < int(time.time()):
        return None
    return citizen_id
