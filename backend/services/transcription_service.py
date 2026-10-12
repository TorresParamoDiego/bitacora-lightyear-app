
"""Servicio US2 de transcripción usando la API de Groq."""

import os
import subprocess
import tempfile
from pathlib import Path
from typing import Any

from distro import info
from groq import Groq

_CLIENT: Groq | None = None
MAX_BYTES = 25 * 1024 * 1024


def _get_client() -> Groq:
    global _CLIENT

    if _CLIENT is None:
        api_key = os.getenv("GROQ_API_KEY")
        if not api_key:
            raise RuntimeError("Falta configurar GROQ_API_KEY.")
        _CLIENT = Groq(api_key=api_key)

    return _CLIENT


def transcribe_bytes(
    content: bytes,
    filename: str,
) -> dict[str, Any]:
    """Convierte audio AAC a WAV y lo transcribe con Groq."""

    extension = Path(filename or "audio.aac").suffix.lower()

    if extension != ".aac":
        raise ValueError("Solo se permiten archivos AAC.")

    if not content:
        raise ValueError("El archivo de audio está vacío.")

    if len(content) > MAX_BYTES:
        raise ValueError("El audio supera el límite de 25 MB.")

    wav_path = None

    try:
        with tempfile.NamedTemporaryFile(
            suffix=".aac", delete=False
        ) as source:
            source.write(content)
            source_path = source.name

        with tempfile.NamedTemporaryFile(
            suffix=".wav", delete=False
        ) as converted:
            wav_path = converted.name

        try:
            subprocess.run(
                [
                    "ffmpeg",
                    "-nostdin",
                    "-v", "error",
                    "-y",
                    "-i", source_path,
                    "-vn",
                    "-ac", "1",
                    "-ar", "16000",
                    "-c:a", "pcm_s16le",
                    wav_path,
                ],
                check=True,
                capture_output=True,
                timeout=60,
            )
        except subprocess.TimeoutExpired as exc:
            raise ValueError(
                "La conversión del audio tardó demasiado."
            ) from exc
        except subprocess.CalledProcessError as exc:
            raise ValueError(
                "No se pudo leer el audio AAC. "
                "Verifica el formato de la grabación."
            ) from exc
        finally:
            os.remove(source_path)

        wav_size = os.path.getsize(wav_path)
        if wav_size == 0:
            raise ValueError("La conversión produjo un archivo vacío.")

        if wav_size > MAX_BYTES:
            raise ValueError(
                "El audio convertido supera el límite de 25 MB."
            )

        with open(wav_path, "rb") as wav_file:
            result = _get_client().audio.transcriptions.create(
                file=("audio.wav", wav_file.read()),
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
                "mensaje": "No se detectó voz inteligible. Graba una nota con voz clara e inténtalo de nuevo.",
                "idioma": getattr(info, "language", "es"),
            }

        return {
            "estado": "completado",
            "transcripcion": transcript,
            "mensaje": "Transcripción realizada correctamente.",
            "idioma": "es",
        }

    finally:
        if wav_path and os.path.exists(wav_path):
            os.remove(wav_path)

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