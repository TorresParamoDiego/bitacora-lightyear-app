
"""Validación y almacenamiento de archivos de audio en Supabase."""

from pathlib import Path
from uuid import uuid4

from fastapi import HTTPException, UploadFile

from services.supabase_client import supabase

BASE_DIR = Path(__file__).resolve().parent.parent
UPLOAD_DIR = BASE_DIR / "uploads"

ALLOWED_EXTENSIONS = {".aac"}
MAX_FILE_SIZE = 25 * 1024 * 1024  # 25 MB


async def save_audio(file: UploadFile) -> dict:
    """Valida y sube un archivo de audio a Supabase Storage.

    La extensión se comprueba contra ``ALLOWED_EXTENSIONS``; el contenido
    multimedia no se inspecciona. El archivo se lee en bloques de 1 MiB, se
    sube al bucket de almacenamiento con un nombre único y se obtiene su URL.

    Args:
        file: Archivo cargado en una solicitud ``multipart/form-data``.

    Returns:
        dict[str, str | int]: Metadatos del archivo subido con las claves
        ``archivo_audio`` (nombre único generado), ``url_publica`` (o ruta en el
        bucket), ``tamano_bytes`` y ``formato`` (extensión sin punto).

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

        filename = f"{uuid4().hex}.aac"

        try:
            supabase.storage.from_("audios").upload(
                path=filename,
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
            "archivo_audio": filename,
            "ruta": filename,
            "tamano_bytes": len(content),
            "formato": "aac",
        }

    finally:
        await file.close()