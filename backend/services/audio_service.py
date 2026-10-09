
"""Validación y almacenamiento local de archivos de audio."""

from pathlib import Path
from uuid import uuid4

from fastapi import HTTPException, UploadFile


BASE_DIR = Path(__file__).resolve().parent.parent
UPLOAD_DIR = BASE_DIR / "uploads"

ALLOWED_EXTENSIONS = {".wav", ".mp3", ".m4a", ".ogg", ".webm",".aac"}
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
            detail="Formato de audio no permitido."
        )

    UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

    filename = f"{uuid4().hex}{extension}"
    destination = UPLOAD_DIR / filename
    total_size = 0

    try:
        with destination.open("wb") as audio:
            while True:
                chunk = await file.read(1024 * 1024)

                if not chunk:
                    break

                total_size += len(chunk)

                if total_size > MAX_FILE_SIZE:
                    raise HTTPException(
                        status_code=413,
                        detail="El archivo supera el límite de 25 MB."
                    )

                audio.write(chunk)

        if total_size == 0:
            raise HTTPException(
                status_code=400,
                detail="El archivo de audio está vacío."
            )

        return {
            "archivo_audio": filename,
            "ruta": str(destination),
            "tamano_bytes": total_size,
            "formato": extension.lstrip("."),
        }

    except Exception:
        destination.unlink(missing_ok=True)
        raise

    finally:
        await file.close()