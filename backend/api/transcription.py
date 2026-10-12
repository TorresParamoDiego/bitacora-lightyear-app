"""Router independiente para US2. Registrar en backend/main.py."""
from fastapi import APIRouter, File, HTTPException, UploadFile
from groq import APIStatusError
from fastapi.concurrency import run_in_threadpool

from schemas.transcription import TranscriptionResponse
from services.transcription_service import transcribe_bytes

router = APIRouter(prefix="/api/transcriptions", tags=["US2 - Transcripción"])
import logging
logger = logging.getLogger("uvicorn.error")

@router.post("", response_model=TranscriptionResponse)
async def transcribe_audio(audio: UploadFile = File(...)) -> TranscriptionResponse:
    filename = audio.filename or "audio.webm"
    try:
        content = await audio.read()
        result = await run_in_threadpool(transcribe_bytes, content, filename)
        return TranscriptionResponse(**result)
    except APIStatusError as exc:
        logger.exception(
            "Error de Groq: status=%s, respuesta=%s",
            exc.status_code,
            exc.response.text,
        )
        raise HTTPException(
            status_code=502,
            detail=f"Error del servicio de transcripción (HTTP {exc.status_code}).",
        ) from exc

    except Exception as exc:
        logger.exception("Fallo de transcripción")
        raise HTTPException(
            status_code=503,
            detail="No se pudo transcribir el audio. Comprueba el servicio y vuelve a intentarlo.",
        ) from exc
