
"""Esquemas de validación y respuesta para las notas de voz."""

from datetime import datetime

from pydantic import BaseModel, Field


class VoiceNoteResponse(BaseModel):
    """Representa la respuesta JSON de ``POST /voice/upload``.

    Attributes:
        id: Identificador único asignado a la nota recibida.
        archivo_audio: Nombre generado del archivo de audio guardado.
        duracion: Duración en segundos, opcional y nula mientras no se
            calcule en la implementación actual.
        fecha_inicio: Fecha de inicio, opcional y nula mientras no se
            proporcione en la implementación actual.
        formato: Extensión del archivo sin punto.
        tamano_bytes: Tamaño del archivo en bytes; debe ser mayor que cero.
        estado: Estado de la recepción. Su valor predeterminado es
            ``"recibido"``.
    """

    id: str
    archivo_audio: str
    duracion: float | None = None
    fecha_inicio: datetime | None = None
    formato: str
    tamano_bytes: int = Field(gt=0)
    estado: str = "recibido"