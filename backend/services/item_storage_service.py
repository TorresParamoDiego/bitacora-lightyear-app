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


def save_items(items: list[ExtractedItem]) -> tuple[int, list[dict[str, Any]]]:
    """Guarda una lista de elementos confirmados tanto en base de datos como en almacenamiento local.

    Returns:
        tuple[int, list[dict]]: Cantidad de elementos guardados y la lista con sus IDs generados.
    """
    now_iso = datetime.datetime.now().isoformat()
    prepared: list[dict[str, Any]] = []

    for item in items:
        record = item.model_dump()
        record["id"] = str(uuid4())
        record["created_at"] = now_iso
        prepared.append(record)

    # 1. Intentar persistencia en Supabase
    try:
        supabase.table("items").insert(prepared).execute()
        logger.info("Se guardaron %d elementos en Supabase.", len(prepared))
    except Exception as exc:
        logger.warning(
            "No se pudo guardar en Supabase (tabla 'items' no configurada aún o sin conexión): %s. "
            "Se guardará en almacenamiento local seguro.",
            exc,
        )

    # 2. Persistencia en almacenamiento local JSON para garantizar persistencia
    current_items = _read_local_items()
    current_items.extend(prepared)
    _write_local_items(current_items)

    return len(prepared), prepared


def list_items() -> list[dict[str, Any]]:
    """Devuelve la lista de elementos guardados."""
    # 1. Intentar leer desde Supabase
    try:
        res = supabase.table("items").select("*").order("created_at", desc=True).execute()
        if res and res.data:
            return res.data
    except Exception as exc:
        logger.debug("Lectura de Supabase no disponible: %s", exc)

    # 2. Fallback a almacenamiento local
    return _read_local_items()
