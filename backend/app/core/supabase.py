from supabase import create_client, Client
from app.core.config import settings

# Initialize Supabase client with service role key for administrative/bypass capabilities
supabase_client: Client = create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_KEY)
