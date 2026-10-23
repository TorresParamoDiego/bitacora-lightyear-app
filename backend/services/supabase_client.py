from pathlib import Path
import os

from dotenv import load_dotenv
from supabase import create_client

# Cargar las variables de backend/.env
ENV_PATH = Path(__file__).resolve().parent.parent / ".env"
load_dotenv(ENV_PATH)

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_SECRET_KEY = os.getenv("SUPABASE_SECRET_KEY")

if not SUPABASE_URL or not SUPABASE_SECRET_KEY:
    raise RuntimeError("Faltan las variables de entorno de Supabase")

supabase = create_client(
    SUPABASE_URL,
    SUPABASE_SECRET_KEY,
)
