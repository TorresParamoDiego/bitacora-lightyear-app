
"""Servicio US2 de transcripción usando la API de Groq."""

"""Transcripción AAC con detección de voz y Groq."""
import os
import subprocess
import tempfile
import wave
from pathlib import Path
from typing import Any
import logging
import webrtcvad
from groq import Groq

_CLIENT: Groq | None = None

MAX_BYTES = 25 * 1024 * 1024
SAMPLE_RATE = 16000
FRAME_MS = 30
FRAME_BYTES = SAMPLE_RATE * 2 * FRAME_MS // 1000

# Ajustables según las grabaciones reales.
MIN_SPEECH_SECONDS = 0.35
MIN_CONTIGUOUS_SECONDS = 0.24
NO_SPEECH_THRESHOLD = 0.60
logger = logging.getLogger("uvicorn.error")

def _get_client() -> Groq:
    global _CLIENT

    if _CLIENT is None:
        api_key = os.getenv("GROQ_API_KEY")
        if not api_key:
            raise RuntimeError("Falta configurar GROQ_API_KEY.")
        _CLIENT = Groq(api_key=api_key)

    return _CLIENT


def no_speech_response() -> dict[str, Any]:
    return {
        "estado": "sin_voz",
        "transcripcion": "",
        "mensaje": (
            "No se detectaron palabras inteligibles. "
            "Graba nuevamente con voz clara e inténtalo de nuevo."
        ),
        "idioma": "es",
    }


def _has_speech(wav_path: str) -> bool:
    """Busca actividad de voz sostenida, no solo picos de volumen."""
    vad = webrtcvad.Vad(3)
    speech_frames = 0
    current_run = 0
    longest_run = 0

    with wave.open(wav_path, "rb") as audio:
        if (
            audio.getnchannels() != 1
            or audio.getsampwidth() != 2
            or audio.getframerate() != SAMPLE_RATE
        ):
            raise ValueError("El audio convertido tiene un formato inesperado.")

        while True:
            frame = audio.readframes(SAMPLE_RATE * FRAME_MS // 1000)
            if len(frame) < FRAME_BYTES:
                break

            is_speech = vad.is_speech(frame, SAMPLE_RATE)

            if is_speech:
                speech_frames += 1
                current_run += 1
                longest_run = max(longest_run, current_run)
            else:
                current_run = 0

    total_speech = speech_frames * FRAME_MS / 1000
    longest_speech = longest_run * FRAME_MS / 1000

    return (
        total_speech >= MIN_SPEECH_SECONDS
        and longest_speech >= MIN_CONTIGUOUS_SECONDS
    )


def _segments_are_silent(result: Any) -> bool:
    """Usa la probabilidad de ausencia de voz que informa Whisper."""
    segments = getattr(result, "segments", None)

    if not segments:
        return False

    probabilities = []

    for segment in segments:
        if isinstance(segment, dict):
            probability = segment.get("no_speech_prob")
        else:
            probability = getattr(segment, "no_speech_prob", None)

        if probability is not None:
            probabilities.append(float(probability))

    # Si todos los segmentos evaluables indican ausencia de voz,
    # rechazamos el resultado.
    return bool(probabilities) and all(
        p >= NO_SPEECH_THRESHOLD for p in probabilities
    )


def transcribe_bytes(content: bytes, filename: str) -> dict[str, Any]:
    """Transcribe una copia WAV temporal; el original permanece AAC.
    Se rechaza el audio sin actividad de voz sostenida.
    1. Convierte a WAV mono 16 kHz.
    2. Detecta actividad de voz sostenida con WebRTC VAD.
    3. Si hay voz, envía a Groq para transcripción.
    """
    extension = Path(filename or "audio.aac").suffix.lower()

    if extension != ".aac":
        raise ValueError("Solo se permiten archivos AAC.")

    if not content:
        raise ValueError("El archivo de audio está vacío.")

    if len(content) > MAX_BYTES:
        raise ValueError("El audio supera el límite de 25 MB.")

    source_path = None
    wav_path = None

    try:
        with tempfile.NamedTemporaryFile(
            suffix=".aac", delete=False
        ) as source:
            source_path = source.name
            source.write(content)

        with tempfile.NamedTemporaryFile(
            suffix=".wav", delete=False
        ) as converted:
            wav_path = converted.name

        try:
            subprocess.run(
                [
                    "ffmpeg", "-nostdin", "-v", "error", "-y",
                    "-i", source_path,
                    "-vn", "-ac", "1", "-ar", str(SAMPLE_RATE),
                    "-c:a", "pcm_s16le", wav_path,
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
                "No se pudo leer el audio AAC."
            ) from exc

        # Primera barrera: no enviar a Groq audio sin actividad
        # de voz sostenida.
        if not _has_speech(wav_path):
            return no_speech_response()

        if os.path.getsize(wav_path) == 0:
            raise ValueError("La conversión produjo un archivo vacío.")

        with open(wav_path, "rb") as wav_file:
            result = _get_client().audio.transcriptions.create(
                file=("audio.wav", wav_file),
                model="whisper-large-v3-turbo",
                language="es",
                response_format="verbose_json",
                temperature=0.0,
            )
        logger.info("Texto detectado: %r", result.text)
        logger.info("Resultado completo de Groq: %r", result)

        transcript = (result.text or "").strip()

        transcript = (result.text or "").strip()

        # Segunda barrera: utilizar la señal de ausencia de voz
        # de Whisper cuando está disponible.
        if not transcript or _segments_are_silent(result):
            return no_speech_response()

        return {
            "estado": "completado",
            "transcripcion": transcript,
            "mensaje": "Transcripción realizada correctamente.",
            "idioma": "es",
        }

    finally:
        for path in (source_path, wav_path):
            if path and os.path.exists(path):
                os.remove(path)


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