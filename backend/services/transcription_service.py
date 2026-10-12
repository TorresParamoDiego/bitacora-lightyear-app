
"""Servicio US2 de transcripción usando la API de Groq."""

import os
from pathlib import Path
from typing import Any

from groq import Groq

_CLIENT: Groq | None = None

_ALLOWED_EXTENSIONS = {
    ".aac",
    ".m4a",
}

_MAX_BYTES = 25 * 1024 * 1024


def _get_client() -> Groq:
    """Crea el cliente de Groq cuando se necesita."""
    global _CLIENT

    if _CLIENT is None:
        api_key = os.getenv("GROQ_API_KEY")

        if not api_key:
            raise RuntimeError(
                "Falta configurar la variable GROQ_API_KEY."
            )

        _CLIENT = Groq(api_key=api_key)

    return _CLIENT


def transcribe_bytes(
    content: bytes,
    filename: str,
) -> dict[str, Any]:
    """Transcribe audio AAC mediante la API de Groq."""

    extension = Path(filename or "audio.aac").suffix.lower()

    if extension not in _ALLOWED_EXTENSIONS:
        raise ValueError(
            "Formato no compatible. Se acepta AAC o M4A."
        )

    if not content:
        raise ValueError("El archivo de audio está vacío.")

    if len(content) > _MAX_BYTES:
        raise ValueError("El audio supera el límite de 25 MB.")

    # Groq recibe el archivo desde memoria, sin guardarlo en disco.
    result = _get_client().audio.transcriptions.create(
        file=(filename or "audio.aac", content),
        model="whisper-large-v3-turbo",
        language="es",
        response_format="json",
        temperature=0.0,
    )

    transcript = result.text.strip()

    if not transcript:
        return {
            "estado": "sin_voz",
            "transcripcion": "",
            "mensaje": (
                "No se detectó voz inteligible. "
                "Graba una nota con voz clara e inténtalo de nuevo."
            ),
            "idioma": "es",
        }

    return {
        "estado": "completado",
        "transcripcion": transcript,
        "mensaje": "Transcripción realizada correctamente.",
        "idioma": "es",
    }

'''
"""Servicio US2 de transcripción de audio con faster-whisper."""
import os
import tempfile
from pathlib import Path
from typing import Any

from faster_whisper import WhisperModel

_MODEL: WhisperModel | None = None
_ALLOWED_EXTENSIONS = {".wav", ".mp3", ".m4a", ".ogg", ".webm", ".mp4", ".mpeg", ".mpga", ".flac", ".aac", ".opus", ".3gp", ".amr"}
_MAX_BYTES = 25 * 1024 * 1024


def _get_model() -> WhisperModel:
    global _MODEL
    if _MODEL is None:
        model_name = os.getenv("WHISPER_MODEL", "tiny")
        device = os.getenv("WHISPER_DEVICE", "cpu")
        compute_type = os.getenv("WHISPER_COMPUTE_TYPE", "int8" if device == "cpu" else "float16")
        _MODEL = WhisperModel(model_name, device=device, compute_type=compute_type)
    return _MODEL


def transcribe_bytes(content: bytes, filename: str) -> dict[str, Any]:
    """Transcribe bytes and return a JSON-serializable result."""
    extension = Path(filename or "audio.webm").suffix.lower()
    if extension not in _ALLOWED_EXTENSIONS:
        raise ValueError("Formato de audio no compatible.")
    if not content:
        raise ValueError("El archivo de audio está vacío.")
    if len(content) > _MAX_BYTES:
        raise ValueError("El audio supera el límite de 25 MB.")

    temp_path: str | None = None
    try:
        with tempfile.NamedTemporaryFile(suffix=extension, delete=False) as temp:
            temp.write(content)
            temp_path = temp.name

        segments, info = _get_model().transcribe(
            temp_path,
            language="es",
            vad_filter=True,
            beam_size=3,
            condition_on_previous_text=False,
        )
        text_parts = [segment.text.strip() for segment in segments if segment.text.strip()]
        transcript = " ".join(text_parts).strip()

        if not transcript:
            return {
                "estado": "sin_voz",
                "transcripcion": "",
                "mensaje": "No se detectó voz inteligible. Graba una nota con voz clara e inténtalo de nuevo.",
                "idioma": getattr(info, "language", "es"),
            }
        return {
            "estado": "completado",
            "transcripcion": transcript,
            "mensaje": "Transcripción realizada correctamente.",
            "idioma": getattr(info, "language", "es"),
        }
    finally:
        if temp_path and os.path.exists(temp_path):
            try:
                os.remove(temp_path)
            except OSError:
                pass
'''