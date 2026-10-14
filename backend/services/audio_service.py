
"""Validación y almacenamiento de archivos de audio en Supabase."""

from pathlib import Path
from uuid import uuid4

from fastapi import HTTPException, UploadFile

from services.supabase_client import supabase

ALLOWED_EXTENSIONS = {".aac"}
MAX_FILE_SIZE = 25 * 1024 * 1024  # 25 MB


async def save_audio(file: UploadFile) -> dict:
    """Valida y sube un archivo de audio a Supabase Storage.

    La extensión se comprueba contra ``ALLOWED_EXTENSIONS``; el contenido
    multimedia no se inspecciona. El archivo se valida con un límite de tamaño
    y se sube al bucket de almacenamiento con un identificador único.

    Args:
        file: Archivo cargado en una solicitud ``multipart/form-data``.

    Returns:
        Metadatos del archivo subido, donde ``id`` y ``archivo_audio`` son la
        clave exacta del objeto dentro del bucket ``audios``.

    Raises:
        HTTPException: HTTP 415 para una extensión no permitida, HTTP 413 si
        el archivo supera ``MAX_FILE_SIZE`` o HTTP 400 si está vacío.
        Otros errores de la API de Supabase se propagan a FastAPI.

    Efectos secundarios:
        Cierra el archivo ``file`` al finalizar la transferencia.
    """
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
            supabase.storage.from_("audios").upload(
                path=audio_id,
                file=content,
                file_options={
                    "content-type": "audio/aac",
                    "upsert": "false",
                },
            )
        except Exception as exc:
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
    """Elimina del bucket un audio cuya persistencia asociada haya fallado."""
    supabase.storage.from_("audios").remove([audio_id])