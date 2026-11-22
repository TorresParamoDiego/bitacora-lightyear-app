# backend/api/items.py
"""Endpoints CRUD para actividades guardadas."""
import logging
import datetime
import re
from typing import Any
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from core.deps import get_current_user_id
from services.item_storage_service import list_items
from services.supabase_client import supabase

router = APIRouter(prefix="/api/items", tags=["Items"])
logger = logging.getLogger("uvicorn.error")

DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
TIME_RE = re.compile(r"^([01]\d|2[0-3]):([0-5]\d)(?::[0-5]\d)?$")

class ItemUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=250)
    description: str | None = None
    type: str | None = None
    priority: str | None = None
    date: str | None = None
    time: str | None = None
    status: str | None = None
    notification_1d_sent: bool | None = None
    notification_30m_sent: bool | None = None
    notification_due_sent: bool | None = None


class StatusUpdate(BaseModel):
    status: str

def _normalize_date(value: str | None) -> str | None:
    if value is None:
        return None
    cleaned = value.strip()
    if not cleaned:
        return None
    if not DATE_RE.match(cleaned):
        raise HTTPException(status_code=422, detail="Formato de fecha inválido (use YYYY-MM-DD).")
    try:
        # Valida días reales y años bisiestos en el calendario.
        return datetime.date.fromisoformat(cleaned).isoformat()
    except ValueError as exc:
        raise HTTPException(status_code=422, detail="Fecha de calendario no válida.") from exc


def _normalize_time(value: str | None) -> str | None:
    if value is None:
        return None
    cleaned = value.strip()
    if not cleaned:
        return None
    match = TIME_RE.match(cleaned)
    if not match:
        raise HTTPException(status_code=422, detail="Formato de hora inválido (use HH:mm).")
    hour = int(match.group(1))
    minute = int(match.group(2))
    return f"{hour:02d}:{minute:02d}"

@router.get("")
def get_user_activities(
    recording_id: str | None = None,
    user_id: str = Depends(get_current_user_id),
) -> dict[str, Any]:
    try:
        items_data = list_items(user_id=user_id, recording_id=recording_id)
        return {"items": items_data, "total": len(items_data)}
    except Exception as exc:
        logger.exception("Error al recuperar actividades")
        raise HTTPException(
            status_code=500, detail="No fue posible recuperar las actividades."
        ) from exc


@router.put("/{item_id}")
def update_item(
    item_id: str,
    body: ItemUpdate,
    user_id: str = Depends(get_current_user_id),
):
    values = {k: v for k, v in body.model_dump(exclude_unset=True).items()}
    if not values:
        raise HTTPException(status_code=422, detail="No se recibieron cambios.")
    if "title" in values and (values["title"] is None or not values["title"].strip()):
        raise HTTPException(status_code=422, detail="El título no puede estar vacío.")
    if "status" in values and values["status"] not in ("pending", "completed", "cancelled"):
        raise HTTPException(status_code=422, detail="Estado no válido.")
    if "priority" in values and values["priority"] not in (None, "high", "medium", "low"):
        raise HTTPException(status_code=422, detail="Prioridad no válida.")
    if "type" in values and values["type"] not in ("task", "reminder", "event"):
        raise HTTPException(status_code=422, detail="Tipo de actividad no válido.")
    # Normaliza y valida fecha y hora antes de persistir en Supabase.
    if "date" in values:
        values["date"] = _normalize_date(values["date"])
    if "time" in values:
        values["time"] = _normalize_time(values["time"])
    if "title" in values:
        values["title"] = values["title"].strip()
    values["updated_at"] = __import__('datetime').datetime.now(__import__('datetime').timezone.utc).isoformat()

    try:
        result = (
            supabase.table("items")
            .update(values)
            .eq("id", item_id)
            .eq("user_id", user_id)
            .execute()
        )
        if not result.data:
            raise HTTPException(
                status_code=404,
                detail="No se encontró la actividad o pertenece a otro usuario.",
            )
        return {"message": "Actividad actualizada correctamente", "item": result.data[0]}
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("Error actualizando actividad")
        raise HTTPException(status_code=500, detail="No se pudo actualizar la actividad.") from exc


@router.patch("/{item_id}/status")
def update_status(
    item_id: str,
    body: StatusUpdate,
    user_id: str = Depends(get_current_user_id),
):
    if body.status not in ("pending", "completed"):
        raise HTTPException(status_code=422, detail="El estado debe ser pending o completed.")
    return update_item(item_id, ItemUpdate(status=body.status), user_id=user_id)


@router.delete("/{item_id}")
def delete_item(
    item_id: str,
    user_id: str = Depends(get_current_user_id),
):
    try:
        result = (
            supabase.table("items")
            .delete()
            .eq("id", item_id)
            .eq("user_id", user_id)
            .execute()
        )
        if not result.data:
            raise HTTPException(status_code=404, detail="No se encontró la actividad a eliminar.")
        return {"message": "Actividad eliminada correctamente"}
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("Error eliminando actividad")
        raise HTTPException(status_code=500, detail="No se pudo eliminar la actividad.") from exc

