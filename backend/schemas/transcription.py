from typing import Literal
from pydantic import BaseModel


class TranscriptionResponse(BaseModel):
    estado: Literal["completado", "sin_voz"]
    transcripcion: str
    mensaje: str
    idioma: str | None = None
