
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
    """Valida y guarda un archivo de audio recibido en una solicitud HTTP.

    La extensión se comprueba contra ``ALLOWED_EXTENSIONS``; el contenido
    multimedia no se inspecciona. El archivo se lee en bloques de 1 MiB y se
    guarda con un nombre aleatorio dentro de ``UPLOAD_DIR``.

    Args:
        file: Archivo cargado en una solicitud ``multipart/form-data``.

    Returns:
        dict[str, str | int]: Metadatos del archivo con las claves
        ``archivo_audio`` (nombre generado), ``ruta`` (ruta local completa),
        ``tamano_bytes`` y ``formato`` (extensión sin punto).

    Raises:
        HTTPException: HTTP 415 para una extensión no permitida, HTTP 413 si
        el archivo supera ``MAX_FILE_SIZE`` o HTTP 400 si está vacío.
        Otros errores de lectura o escritura se propagan a FastAPI.

    Efectos secundarios:
        Crea ``UPLOAD_DIR`` si hace falta, escribe el audio en disco y elimina
        el archivo parcial si ocurre una excepción. Cierra ``file`` siempre.
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