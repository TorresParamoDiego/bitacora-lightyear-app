"""Endpoints CRUD para actividades guardadas."""
import logging, os
from typing import Any
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field
from services.item_storage_service import list_items
from services.supabase_client import supabase

router = APIRouter(prefix="/api/items", tags=["Items"])
logger = logging.getLogger("uvicorn.error")
DEFAULT_USER_ID = "00000000-0000-0000-0000-000000000001"

def _user_id():
    # Compatibilidad con el flujo actual de la aplicación; se sustituye por el usuario autenticado cuando se integre JWT.
    return os.getenv("TEST_USER_ID", DEFAULT_USER_ID)

class ItemUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=250)
    description: str | None = None
    type: str | None = None
    priority: str | None = None
    date: str | None = None
    time: str | None = None
    status: str | None = None

class StatusUpdate(BaseModel):
    status: str

@router.get("")
def get_user_activities() -> dict[str, Any]:
    try:
        items_data = list_items(user_id=_user_id())
        return {"items": items_data, "total": len(items_data)}
    except Exception as exc:
        logger.exception("Error al recuperar actividades")
        raise HTTPException(status_code=500, detail="No fue posible recuperar las actividades. Verifica la conexión y la tabla items.") from exc

@router.put("/{item_id}")
def update_item(item_id: str, body: ItemUpdate):
    values = {k: v for k, v in body.model_dump(exclude_unset=True).items()}
    if not values:
        raise HTTPException(status_code=422, detail="No se recibieron cambios.")
    if "title" in values and (values["title"] is None or not values["title"].strip()):
        raise HTTPException(status_code=422, detail="El título no puede estar vacío.")
    if "status" in values and values["status"] not in ("pending", "completed", "cancelled"):
        raise HTTPException(status_code=422, detail="Estado no válido.")
    if "priority" in values and values["priority"] not in (None, "high", "medium", "low"):
        raise HTTPException(status_code=422, detail="Prioridad no válida.")
    if "title" in values: values["title"] = values["title"].strip()
    values["updated_at"] = __import__('datetime').datetime.now(__import__('datetime').timezone.utc).isoformat()
    try:
        result = supabase.table("items").update(values).eq("id", item_id).eq("user_id", _user_id()).execute()
        if not result.data:
            raise HTTPException(status_code=404, detail="No se encontró la actividad. Puede pertenecer a otra cuenta o no estar guardada en la tabla items.")
        return {"message": "Actividad actualizada correctamente", "item": result.data[0]}
    except HTTPException: raise
    except Exception as exc:
        logger.exception("Error actualizando actividad")
        raise HTTPException(status_code=500, detail="No se pudo actualizar la actividad. Revisa la conexión y las columnas de la tabla items.") from exc

@router.patch("/{item_id}/status")
def update_status(item_id: str, body: StatusUpdate):
    if body.status not in ("pending", "completed"):
        raise HTTPException(status_code=422, detail="El estado debe ser pending o completed.")
    return update_item(item_id, ItemUpdate(status=body.status))

@router.delete("/{item_id}")
def delete_item(item_id: str):
    try:
        result = supabase.table("items").delete().eq("id", item_id).eq("user_id", _user_id()).execute()
        if not result.data:
            raise HTTPException(status_code=404, detail="No se encontró la actividad para eliminar.")
        return {"message": "Actividad eliminada correctamente"}
    except HTTPException: raise
    except Exception as exc:
        logger.exception("Error eliminando actividad")
        raise HTTPException(status_code=500, detail="No se pudo eliminar la actividad.") from exc
