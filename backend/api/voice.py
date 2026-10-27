# backend/api/voice.py
"""Rutas HTTP relacionadas con notas de voz."""

from fastapi import APIRouter, Depends, File, UploadFile, status

from core.deps import get_current_user_id
from schemas.voice import VoiceNoteResponse
from services.audio_service import save_audio

router = APIRouter(prefix="/voice", tags=["Voice Notes"])


@router.post(
    "/upload",
    response_model=VoiceNoteResponse,
    status_code=status.HTTP_201_CREATED,
)
async def upload_voice(
    file: UploadFile = File(...),
    user_id: str = Depends(get_current_user_id),
):
    """Recibe un archivo de audio y lo almacena asociándolo al usuario autenticado."""
    audio_data = await save_audio(file, user_id)

    return VoiceNoteResponse(
        id=audio_data["id"],
        archivo_audio=audio_data["archivo_audio"],
        formato=audio_data["formato"],
        tamano_bytes=audio_data["tamano_bytes"],
        estado="recibido",
    )