"""Esquemas Pydantic para el análisis de transcripciones y extracción de elementos."""

from typing import Any, Literal
from pydantic import BaseModel, Field


ItemType = Literal["task", "reminder", "event"]
ItemPriority = Literal["high", "medium", "low"] | None
ItemStatus = Literal["pending", "completed", "cancelled"]


class ExtractedItem(BaseModel):
    """Representa un elemento extraído de una transcripción.

    Todos los campos deben estar presentes en cada elemento.
    """
    type: ItemType = Field(
        ...,
        description='Tipo de elemento: "task", "reminder" o "event".'
    )
    title: str = Field(
        ...,
        description="Título breve y descriptivo del elemento."
    )
    description: str = Field(
        ...,
        description="Detalles relevantes extraídos de la transcripción."
    )
    priority: ItemPriority = Field(
        default=None,
        description='Prioridad: "high", "medium", "low" o null.'
    )
    date: str | None = Field(
        default=None,
        description='Fecha en formato "YYYY-MM-DD" o null si no se identifica.'
    )
    time: str | None = Field(
        default=None,
        description='Hora en formato "HH:mm" o null si no se identifica.'
    )
    status: ItemStatus = Field(
        default="pending",
        description='Estado: "pending", "completed" o "cancelled".'
    )


class AnalysisRequest(BaseModel):
    """Solicitud para analizar una transcripción."""
    text: str = Field(
        ...,
        min_length=1,
        description="Texto de la transcripción a analizar."
    )
    reference_date: str | None = Field(
        default=None,
        description='Fecha de referencia en formato "YYYY-MM-DD". Si se omite, se usa la fecha actual.'
    )


class AnalysisResponse(BaseModel):
    """Estructura JSON estandarizada con un objeto raíz que contiene la propiedad 'items'."""
    items: list[ExtractedItem] = Field(
        default_factory=list,
        description="Lista de elementos extraídos de la transcripción."
    )


class SaveItemsRequest(BaseModel):
    """Solicitud para guardar elementos confirmados por el usuario."""
    items: list[ExtractedItem] = Field(
        ...,
        description="Lista de elementos confirmados para guardar."
    )


class SaveItemsResponse(BaseModel):
    """Respuesta tras guardar elementos confirmados."""
    saved_count: int = Field(
        ...,
        description="Número de elementos guardados correctamente."
    )
    items: list[dict[str, Any]] = Field(
        ...,
        description="Elementos guardados, incluidos sus IDs y relaciones."
    )
    message: str = Field(
        ...,
        description="Mensaje descriptivo del resultado."
    )
