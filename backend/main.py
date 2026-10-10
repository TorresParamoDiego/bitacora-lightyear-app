
"""Inicializa la aplicación FastAPI de Bitácora Lightyear."""

from fastapi import FastAPI

from api.voice import router as voice_router
from api.transcription import router as transcription_router


app = FastAPI(
    title="Bitácora Lightyear API",
    version="0.1.0",
    description="API para gestionar notas de voz.",
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


app.include_router(voice_router)
app.include_router(transcription_router)
