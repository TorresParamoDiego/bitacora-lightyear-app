"""Servicio de persistencia para guardar y consultar los elementos confirmados por el usuario."""

import datetime
import json
import logging
from pathlib import Path
from uuid import uuid4
from typing import Any

from schemas.analysis import ExtractedItem
from services.supabase_client import supabase

logger = logging.getLogger("uvicorn.error")

BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = BASE_DIR / "data"
ITEMS_FILE = DATA_DIR / "saved_items.json"


def _ensure_data_dir() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    if not ITEMS_FILE.exists():
        ITEMS_FILE.write_text("[]", encoding="utf-8")


def _read_local_items() -> list[dict[str, Any]]:
    _ensure_data_dir()
    try:
        content = ITEMS_FILE.read_text(encoding="utf-8")
        return json.loads(content)
    except Exception as exc:
        logger.warning("Error al leer archivo local de items: %s", exc)
        return []


def _write_local_items(items: list[dict[str, Any]]) -> None:
    _ensure_data_dir()
    ITEMS_FILE.write_text(json.dumps(items, ensure_ascii=False, indent=2), encoding="utf-8")


DEFAULT_USER_ID = "00000000-0000-0000-0000-000000000001"


def save_items(
    items: list[ExtractedItem],
    user_id: str | None = None,
    recording_id: str | None = None,
    simulate_error: bool = False,
) -> tuple[int, list[dict[str, Any]]]:
    """Guarda una lista de elementos confirmados en la base de datos Supabase y en almacenamiento local.

    Returns:
        tuple[int, list[dict]]: Cantidad de elementos guardados y la lista con sus IDs generados.
    Raises:
        RuntimeError: Si ocurre un fallo al persistir en Supabase o si simulate_error es True.
    """
    if simulate_error:
        raise RuntimeError(
            "Error forzado de almacenamiento: fallo de conexión simulado con el repositorio de datos (Supabase)."
        )

    if not items:
        return 0, []

    effective_user_id = user_id or DEFAULT_USER_ID
    now_iso = datetime.datetime.now(datetime.timezone.utc).isoformat()
    prepared: list[dict[str, Any]] = []

    for item in items:
        record = item.model_dump()
        record["id"] = str(uuid4())
        record["user_id"] = effective_user_id
        if recording_id:
            record["recording_id"] = recording_id
        if not record.get("date"):
            record["date"] = None
        if not record.get("time"):
            record["time"] = None
        record["created_at"] = now_iso
        record["updated_at"] = now_iso
        prepared.append(record)

    # 1. Persistencia primaria en Supabase
    try:
        supabase.table("items").insert(prepared).execute()
        logger.info("Se guardaron exitosamente %d elementos en Supabase.", len(prepared))
    except Exception as exc:
        logger.exception("Error al guardar elementos en Supabase: %s", exc)
        raise RuntimeError(f"Error al persistir en la base de datos Supabase: {exc}") from exc

    # 2. Respaldo local JSON para redundancia (solo si la BD tuvo éxito)
    try:
        current_items = _read_local_items()
        current_items.extend(prepared)
        _write_local_items(current_items)
    except Exception as exc:
        logger.warning("No se pudo escribir en el respaldo local: %s", exc)

    return len(prepared), prepared


def list_items(user_id: str | None = None, recording_id: str | None = None) -> list[dict[str, Any]]:
    """Devuelve la lista de elementos guardados desde Supabase o fallback local."""
    effective_user_id = user_id or DEFAULT_USER_ID
    # 1. Intentar leer desde Supabase
    try:
        query = supabase.table("items").select("*").eq("user_id", effective_user_id)
        if recording_id:
            query = query.eq("recording_id", recording_id)
            
        res = query.order("created_at", desc=True).execute()
        if res and res.data is not None:
            return res.data
    except Exception as exc:
        logger.debug("Lectura de Supabase no disponible o error: %s", exc)

    # 2. Fallback a almacenamiento local (el filtro por recording_id no se implementa en local para brevedad)
    local = [i for i in _read_local_items() if i.get("user_id") == effective_user_id]
    if recording_id:
        local = [i for i in local if i.get("recording_id") == recording_id]
    return local

