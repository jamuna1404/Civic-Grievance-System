"""Supabase client singleton.

Exposes a single lazily-created [Client] so routers share one connection
instead of constructing a new client per request.
"""

from functools import lru_cache

from supabase import Client, create_client

from app.core.config import get_settings


@lru_cache
def get_supabase() -> Client:
    """Return the shared Supabase client.

    Raises:
        RuntimeError: if SUPABASE_URL / SUPABASE_KEY are not configured.
    """
    settings = get_settings()
    if not settings.supabase_url or not settings.supabase_key:
        raise RuntimeError(
            "Supabase is not configured. Set SUPABASE_URL and SUPABASE_KEY "
            "in your environment or .env file."
        )
    return create_client(settings.supabase_url, settings.supabase_key)
