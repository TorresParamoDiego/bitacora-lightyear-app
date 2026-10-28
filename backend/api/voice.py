# backend/api/voice.py
"""Rutas HTTP relacionadas con notas de voz."""

# Modifica la importación en la línea 4
from fastapi import APIRouter, Depends, File, UploadFile, status, HTTPException
from services.supabase_client import supabase
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

@router.get("/recordings")
def get_user_recordings(user_id: str = Depends(get_current_user_id)):
    """Devuelve el historial de grabaciones del usuario."""
    try:
        res = (
            supabase.table("recordings")
            .select("id, original_filename, transcript, created_at, duration_seconds")
            .eq("user_id", user_id)
            .order("created_at", desc=True)
            .execute()
        )
        return {"recordings": res.data or []}
    except Exception as exc:
        raise HTTPException(status_code=500, detail="Error al obtener las grabaciones") from exc