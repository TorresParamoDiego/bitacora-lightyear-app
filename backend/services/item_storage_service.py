"""Servicio de persistencia para guardar y consultar los elementos confirmados por el usuario."""

import datetime
import logging
from uuid import uuid4
from typing import Any

from schemas.analysis import ExtractedItem
from services.supabase_client import supabase

logger = logging.getLogger("uvicorn.error")

def save_items(
    items: list[ExtractedItem],
    user_id: str,
    recording_id: str | None = None,
) -> tuple[int, list[dict[str, Any]]]:
    """Persiste elementos en Supabase asociados al usuario y al audio opcional.

    Returns:
        tuple[int, list[dict]]: Cantidad de elementos guardados y la lista con sus IDs generados.
    """
    if not user_id:
        raise ValueError("Se requiere un user_id para guardar actividades")
    if not items:
        return 0, []

    now_iso = datetime.datetime.now(datetime.timezone.utc).isoformat()
    prepared: list[dict[str, Any]] = []

    for item in items:
        record = item.model_dump()
        record["id"] = str(uuid4())
        record["user_id"] = user_id
        record["recording_id"] = recording_id
        record["created_at"] = now_iso
        prepared.append(record)

    response = supabase.table("items").insert(prepared).execute()
    saved_items = response.data or []
    if len(saved_items) != len(prepared):
        raise RuntimeError(
            f"Supabase confirmó {len(saved_items)} de {len(prepared)} actividades."
        )

    logger.info("Se guardaron %d elementos en Supabase.", len(saved_items))
    return len(saved_items), saved_items

def list_items(user_id: str) -> list[dict[str, Any]]:
    """Devuelve las actividades de un usuario desde Supabase."""
    if not user_id:
        raise ValueError("Se requiere un user_id para consultar actividades")

    response = (
        supabase.table("items")
        .select(
            "id, user_id, recording_id, type, title, description, "
            "priority, date, time, status, created_at"
        )
        .eq("user_id", user_id)
        .order("created_at", desc=True)
        .execute()
    )

    return response.data or []
