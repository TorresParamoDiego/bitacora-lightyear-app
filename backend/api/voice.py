"""Rutas HTTP relacionadas con notas de voz."""

import os
from fastapi import APIRouter, File, HTTPException, UploadFile, status

from backend.services.audio_service import save_audio
from backend.schemas.voice import VoiceNoteResponse


router = APIRouter(prefix="/voice", tags=["Voice Notes"])


@router.post(
    "/upload",
    response_model=VoiceNoteResponse,
    status_code=status.HTTP_201_CREATED,
)
async def upload_voice(file: UploadFile = File(...)):
    """Recibe y almacena un archivo de audio.

    Solicitud:
        ``POST /voice/upload`` con ``Content-Type: multipart/form-data`` y un
        campo obligatorio ``file`` que contenga el audio.

    Returns:
        VoiceNoteResponse: Identificador de nota, nombre de archivo, formato,
        tamaño, estado y los campos opcionales de duración y fecha, que quedan
        nulos en esta implementación.

    Raises:
        HTTPException: Con HTTP 400 si el archivo está vacío, 413 si supera
        el límite configurado o 415 si su extensión no está permitida.
        FastAPI responde con HTTP 422 si falta el campo requerido o no se
        puede validar la solicitud.

    Efectos secundarios:
        Guarda el audio en el bucket ``audios`` de Supabase y registra
        su metadata en la tabla de grabaciones.
    """
    user_id = os.getenv("TEST_USER_ID")
    if not user_id:
        raise HTTPException(status_code=500, detail="Falta configurar TEST_USER_ID")

    # Pasamos el user_id a la función
    audio_data = await save_audio(file, user_id)

    return VoiceNoteResponse(
        id=audio_data["id"],
        archivo_audio=audio_data["archivo_audio"],
        formato=audio_data["formato"],
        tamano_bytes=audio_data["tamano_bytes"],
        estado="recibido",
    )