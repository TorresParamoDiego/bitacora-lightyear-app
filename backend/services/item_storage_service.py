"""Servicio de persistencia para guardar y consultar los elementos confirmados por el usuario."""

import datetime
import json
import logging
from pathlib import Path
from uuid import uuid4
from typing import Any

from schemas.analysis import ExtractedItem
from services.supabase_client import supabase
import hashlib
from zoneinfo import ZoneInfo
logger = logging.getLogger("uvicorn.error")
MEXICO_TZ = ZoneInfo("America/Mexico_City")
BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = BASE_DIR / "data"
ITEMS_FILE = DATA_DIR / "saved_items.json"

DEFAULT_OFFSETS_BY_TYPE: dict[str, list[int]] = {
    "task": [1440, 30, 0],
    "reminder": [30, 0],
    "event": [1440, 60, 0],
}


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
    ITEMS_FILE.write_text(
        json.dumps(items, ensure_ascii=False, indent=2), encoding="utf-8"
    )


def _normalize_offsets(raw_offsets: Any) -> list[int]:
    if not isinstance(raw_offsets, list):
        return []
    cleaned: set[int] = set()
    for val in raw_offsets:
        try:
            num = int(val)
            if num >= 0:
                cleaned.add(num)
        except (TypeError, ValueError):
            continue
    return sorted(cleaned, reverse=True)


def _resolve_due_datetime(
    date_str: str | None,
    time_str: str | None,
) -> datetime.datetime | None:
    if not date_str or not date_str.strip():
        return None

    try:
        due_date = datetime.date.fromisoformat(date_str.strip()[:10])

        hour, minute = 9, 0

        if time_str and time_str.strip():
            parts = time_str.strip().split(":")
            hour = int(parts[0])
            minute = int(parts[1])

        return datetime.datetime(
            due_date.year,
            due_date.month,
            due_date.day,
            hour,
            minute,
            tzinfo=MEXICO_TZ,
        )
    except (ValueError, TypeError, IndexError):
        return None


def _load_user_type_defaults(user_id: str) -> dict[str, list[int]]:
    defaults = {k: list(v) for k, v in DEFAULT_OFFSETS_BY_TYPE.items()}
    try:
        res = (
            supabase.table("user_notification_type_defaults")
            .select("item_type, offset_minutes")
            .eq("user_id", user_id)
            .execute()
        )
        for row in (res.data or []):
            item_type = str(row.get("item_type") or "").strip().lower()
            if item_type:
                defaults[item_type] = _normalize_offsets(row.get("offset_minutes"))
    except Exception as exc:
        logger.debug("No se pudieron cargar defaults de tipo para %s: %s", user_id, exc)
    return defaults


def sync_item_notification_schedules(
    *,
    item_id: str,
    user_id: str,
    item_type: str,
    status: str | None,
    date_str: str | None,
    time_str: str | None,
    custom_offsets: list[int] | None = None,
    type_defaults: dict[str, list[int]] | None = None,
) -> None:
    """
    Sincroniza los avisos FCM de una actividad.

    custom_offsets:
      None = heredar defaults del tipo.
      []   = desactivar avisos.
      [...] = utilizar anticipaciones personalizadas.
    """
    if not item_id or not user_id:
        raise ValueError("item_id y user_id son obligatorios.")

    normalized_status = (status or "pending").strip().lower()
    due_at = _resolve_due_datetime(date_str, time_str)

    # Actividades sin fecha, completadas o canceladas:
    # no deben conservar avisos pendientes.
    if normalized_status in ("completed", "cancelled") or due_at is None:
        (
            supabase.table("item_notification_schedules")
            .delete()
            .eq("item_id", item_id)
            .eq("user_id", user_id)
            .execute()
        )
        return

    defaults = (
        type_defaults
        if type_defaults is not None
        else _load_user_type_defaults(user_id)
    )

    normalized_type = (item_type or "task").strip().lower()

    if custom_offsets is None:
        offsets = _normalize_offsets(
            defaults.get(
                normalized_type,
                DEFAULT_OFFSETS_BY_TYPE["task"],
            )
        )
    else:
        offsets = _normalize_offsets(custom_offsets)

    existing_res = (
        supabase.table("item_notification_schedules")
        .select(
            "offset_minutes, sent, sent_at, schedule_fingerprint"
        )
        .eq("item_id", item_id)
        .eq("user_id", user_id)
        .execute()
    )

    existing_rows = existing_res.data or []

    existing_by_offset: dict[int, dict[str, Any]] = {}

    for row in existing_rows:
        try:
            existing_by_offset[int(row["offset_minutes"])] = row
        except (KeyError, TypeError, ValueError):
            continue

    # Si el usuario desactivó todos los avisos, limpiar schedules.
    if not offsets:
        (
            supabase.table("item_notification_schedules")
            .delete()
            .eq("item_id", item_id)
            .eq("user_id", user_id)
            .execute()
        )
        return

    now = datetime.datetime.now(MEXICO_TZ)
    now_utc_iso = datetime.datetime.now(
        datetime.timezone.utc
    ).isoformat()

    rows_to_upsert: list[dict[str, Any]] = []

    for offset in offsets:
        fire_at = due_at - datetime.timedelta(minutes=offset)

        fingerprint_source = (
            f"{due_at.isoformat()}|{offset}"
        )

        fingerprint = hashlib.sha256(
            fingerprint_source.encode("utf-8")
        ).hexdigest()

        previous = existing_by_offset.get(offset)

        # Solo conservar el envío anterior si pertenece
        # exactamente a esta misma programación.
        was_sent = (
            previous is not None
            and previous.get("sent") is True
            and previous.get("schedule_fingerprint") == fingerprint
        )

        # Los avisos cuyo momento ya pasó no deben enviarse
        # tardíamente al reconstruir la programación.
        is_past = fire_at <= now
        mark_sent = was_sent or is_past

        previous_sent_at = (
            previous.get("sent_at")
            if was_sent
            else None
        )

        rows_to_upsert.append(
            {
                "item_id": item_id,
                "user_id": user_id,
                "offset_minutes": offset,
                "sent": mark_sent,
                "sent_at": (
                    previous_sent_at
                    if was_sent
                    else now_utc_iso if is_past else None
                ),
                "schedule_fingerprint": fingerprint,
                "updated_at": now_utc_iso,
            }
        )

    # Primero guardar la nueva programación.
    (
        supabase.table("item_notification_schedules")
        .upsert(
            rows_to_upsert,
            on_conflict="item_id,offset_minutes",
        )
        .execute()
    )

    # Después retirar anticipaciones que ya no existen.
    current_offsets = set(offsets)

    for previous_offset in existing_by_offset:
        if previous_offset not in current_offsets:
            (
                supabase.table("item_notification_schedules")
                .delete()
                .eq("item_id", item_id)
                .eq("user_id", user_id)
                .eq("offset_minutes", previous_offset)
                .execute()
            )
            
            

DEFAULT_USER_ID = "00000000-0000-0000-0000-000000000001"


def save_items(
    items: list[ExtractedItem],
    user_id: str | None = None,
    recording_id: str | None = None,
    simulate_error: bool = False,
    custom_offsets_by_index: dict[int, list[int]] | None = None,
) -> tuple[int, list[dict[str, Any]]]:
    """Guarda una lista de elementos confirmados en Supabase y respaldo local, y programa sus avisos."""
    if simulate_error:
        raise RuntimeError(
            "Error forzado de almacenamiento: fallo de conexión simulado con el repositorio de datos (Supabase)."
        )

    if not items:
        return 0, []

    effective_user_id = user_id or DEFAULT_USER_ID
    now_iso = datetime.datetime.now(datetime.timezone.utc).isoformat()
    prepared: list[dict[str, Any]] = []

    for idx, item in enumerate(items):
        record = item.model_dump()

        custom = (
            custom_offsets_by_index.get(idx)
            if custom_offsets_by_index is not None
            and idx in custom_offsets_by_index
            else None
        )

        record["notification_offsets"] = (
            _normalize_offsets(custom)
            if custom is not None
            else None
        )
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

    # 2. Programación de avisos en `item_notification_schedules`
    type_defaults = _load_user_type_defaults(effective_user_id)
    for idx, rec in enumerate(prepared):
        custom = rec.get("notification_offsets")
        sync_item_notification_schedules(
            item_id=rec["id"],
            user_id=effective_user_id,
            item_type=str(rec.get("type") or "task"),
            status=rec.get("status"),
            date_str=rec.get("date"),
            time_str=rec.get("time"),
            custom_offsets=custom,
            type_defaults=type_defaults,
        )

    # 3. Respaldo local JSON para redundancia (solo si la BD tuvo éxito)
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
    try:
        query = supabase.table("items").select("*").eq("user_id", effective_user_id)
        if recording_id:
            query = query.eq("recording_id", recording_id)

        res = query.order("created_at", desc=True).execute()
        if res and res.data is not None:
            return res.data
    except Exception as exc:
        logger.debug("Lectura de Supabase no disponible o error: %s", exc)

    local = [i for i in _read_local_items() if i.get("user_id") == effective_user_id]
    if recording_id:
        local = [i for i in local if i.get("recording_id") == recording_id]
    return local