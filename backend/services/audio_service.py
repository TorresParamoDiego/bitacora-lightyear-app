"""Validación y almacenamiento de archivos de audio en Supabase."""

from pathlib import Path
from uuid import uuid4

from fastapi import HTTPException, UploadFile

from services.supabase_client import supabase

ALLOWED_EXTENSIONS = {".aac"}
MAX_FILE_SIZE = 25 * 1024 * 1024  # 25 MB


async def save_audio(file: UploadFile, user_id: str) -> dict: # <-- Añadido user_id
    """Valida, sube un archivo a Supabase Storage y registra en la base de datos."""
    extension = Path(file.filename or "").suffix.lower()

    if extension not in ALLOWED_EXTENSIONS:
        raise HTTPException(
            status_code=415,
            detail="Solo se admiten archivos AAC (.aac).",
        )

    try:
        content = await file.read(MAX_FILE_SIZE + 1)

        if not content:
            raise HTTPException(
                status_code=400,
                detail="El archivo de audio está vacío.",
            )

        if len(content) > MAX_FILE_SIZE:
            raise HTTPException(
                status_code=413,
                detail="El archivo supera el límite de 25 MB.",
            )

        audio_id = str(uuid4())

        try:
            # 1. Subir al bucket
            supabase.storage.from_("audios").upload(
                path=audio_id,
                file=content,
                file_options={
                    "content-type": "audio/aac",
                    "upsert": "false",
                },
            )
            
            try:
                # 2. Insertar en la tabla SQL con todos los campos obligatorios
                supabase.table("recordings").insert({
                    "id": audio_id,
                    "user_id": user_id,
                    "storage_path": audio_id,          # <-- ¡ESTE ES EL CAMPO QUE FALTABA!
                    "original_filename": file.filename, # Recomendado ya que lo tienes
                    "mime_type": "audio/aac",           # Recomendado ya que lo tienes
                    "analysis_status": "pending"        # Tu esquema ya lo pone por defecto, pero es buena práctica
                }).execute()
                
            except Exception as db_exc:
                # Rollback manual: si falla la inserción en BD, borramos del bucket
                supabase.storage.from_("audios").remove([audio_id])
                raise db_exc

        except Exception as exc:
            # (Aquí puedes dejar el log temporal o regresarlo a la normalidad)
            raise HTTPException(
                status_code=502,
                detail="No se pudo guardar el audio en Supabase.",
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


def delete_audio(audio_id: str) -> None:
    """Elimina del bucket y de la tabla un audio cuya persistencia asociada haya fallado."""
    # Primero borramos de la base de datos (por si existiera la relación)
    supabase.table("recordings").delete().eq("id", audio_id).execute()
    # Luego borramos del storage
    supabase.storage.from_("audios").remove([audio_id])