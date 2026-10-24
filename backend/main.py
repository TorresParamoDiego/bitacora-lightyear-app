
"""Inicializa la aplicación FastAPI de Bitácora Lightyear."""

from dotenv import load_dotenv
load_dotenv()

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from api import items, auth

from api.voice import router as voice_router
from api.transcription import router as transcription_router
from api.analysis import router as analysis_router
from services.supabase_client import supabase
import logging

logger = logging.getLogger(__name__)

app = FastAPI(
    title="Bitácora Lightyear API",
    version="0.1.0",
    description="API para gestionar notas de voz.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)



@app.get("/health")
def health_check():
    """Devuelve el estado básico de disponibilidad de la API.

    Returns:
        dict[str, str]: Estado y nombre de la aplicación. La ruta responde
        con HTTP 200 cuando el proceso puede atender solicitudes.
    """
    return {
        "status": "ok",
        "app": "Bitácora Lightyear",
    }

@app.get("/health/db")
def check_database():
    try:
        result = (
            supabase
            .table("items")
            .select("id")
            .limit(1)
            .execute()
        )

        return {
            "connected": True,
            "message": "Conexión con Supabase correcta",
            "query_ok": result.data is not None,
        }

    except Exception:
        logger.exception("Error consultando la tabla items en Supabase")
        raise HTTPException(
            status_code=503,
            detail="No fue posible consultar la base de datos",
        )


app.include_router(voice_router)
app.include_router(transcription_router)
app.include_router(analysis_router)
app.include_router(items.router)
app.include_router(auth.router)
