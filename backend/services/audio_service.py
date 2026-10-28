"""Validación y almacenamiento de archivos de audio en Supabase."""

import logging
from pathlib import Path
from uuid import uuid4

from fastapi import HTTPException, UploadFile, status
from fastapi.concurrency import run_in_threadpool

from services.supabase_client import supabase

logger = logging.getLogger("uvicorn.error")

ALLOWED_EXTENSIONS = {".aac"}
MAX_FILE_SIZE = 25 * 1024 * 1024  # 25 MB


async def save_audio(file: UploadFile, user_id: str) -> dict:
    """Valida, sube un archivo a Supabase Storage y registra en la base de datos."""
    extension = Path(file.filename or "").suffix.lower()

    if extension not in ALLOWED_EXTENSIONS:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Solo se admiten archivos AAC (.aac).",
        )

    try:
        content = await file.read(MAX_FILE_SIZE + 1)

        if not content:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="El archivo de audio está vacío.",
            )

        if len(content) > MAX_FILE_SIZE:
            raise HTTPException(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail="El archivo supera el límite de 25 MB.",
            )

        audio_id = str(uuid4())

        try:
            # 1. Subir al bucket en un hilo secundario (no bloqueante)
            await run_in_threadpool(
                lambda: supabase.storage.from_("audios").upload(
                    path=audio_id,
                    file=content,
                    file_options={
                        "content-type": "audio/aac",
                        "upsert": "false",
                    },
                )
            )

            try:
                # 2. Insertar en la tabla SQL
                await run_in_threadpool(
                    lambda: supabase.table("recordings").insert({
                        "id": audio_id,
                        "user_id": user_id,
                        "storage_path": audio_id,
                        "original_filename": file.filename,
                        "mime_type": "audio/aac",
                        "analysis_status": "pending",
                    }).execute()
                )

            except Exception as db_exc:
                logger.exception("Error al insertar registro en BD, ejecutando rollback del bucket: %s", db_exc)
                # Rollback no bloqueante
                await run_in_threadpool(
                    lambda: supabase.storage.from_("audios").remove([audio_id])
                )
                raise db_exc

        except HTTPException:
            raise
        except Exception as exc:
            logger.exception("Error en la integración con Supabase Storage/DB: %s", exc)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"No se pudo guardar el audio en Supabase: {str(exc)}",
            ) from exc

        return {
            "id": audio_id,
            "archivo_audio": audio_id,
            "ruta": audio_id,
            "tamano_bytes": len(content),
            "formato": "aac",
        }

    finally:
        await file.close()


async def delete_audio(audio_id: str) -> None:
    """Elimina del bucket y de la tabla un audio cuya persistencia asociada haya fallado."""
    try:
        await run_in_threadpool(
            lambda: supabase.table("recordings").delete().eq("id", audio_id).execute()
        )
        await run_in_threadpool(
            lambda: supabase.storage.from_("audios").remove([audio_id])
        )
    except Exception as exc:
        logger.exception("Error al eliminar audio %s en cleanup: %s", audio_id, exc)