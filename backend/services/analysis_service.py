"""Servicio de análisis automático de transcripciones para extracción de tareas, eventos y recordatorios."""

import datetime
import json
import logging
import os
import re
from typing import Any

from dotenv import load_dotenv
from groq import Groq
from schemas.analysis import ExtractedItem

load_dotenv()

logger = logging.getLogger("uvicorn.error")

_GROQ_CLIENT: Groq | None = None
MAX_RECURRING_ITEMS = 16

MONTHS = {
    "enero": 1,
    "febrero": 2,
    "marzo": 3,
    "abril": 4,
    "mayo": 5,
    "junio": 6,
    "julio": 7,
    "agosto": 8,
    "septiembre": 9,
    "setiembre": 9,
    "octubre": 10,
    "noviembre": 11,
    "diciembre": 12,
}

DAYS_OF_WEEK = {
    "lunes": 0,
    "martes": 1,
    "miercoles": 2,
    "miércoles": 2,
    "jueves": 3,
    "viernes": 4,
    "sabado": 5,
    "sábado": 5,
    "domingo": 6,
}


def _get_groq_client() -> Groq | None:
    """Obtiene el cliente Groq si la variable de entorno GROQ_API_KEY está definida."""
    global _GROQ_CLIENT
    api_key = os.getenv("GROQ_API_KEY")
    if not api_key:
        return None
    if _GROQ_CLIENT is None:
        try:
            _GROQ_CLIENT = Groq(api_key=api_key)
        except Exception as exc:
            logger.warning("No se pudo inicializar Groq client: %s", exc)
            return None
    return _GROQ_CLIENT


def parse_reference_date(ref_date_str: str | None) -> datetime.date:
    """Parsea la fecha de referencia en formato YYYY-MM-DD o devuelve la fecha actual."""
    if ref_date_str:
        try:
            return datetime.date.fromisoformat(ref_date_str.strip())
        except ValueError:
            logger.warning("Fecha de referencia inválida '%s', usando hoy", ref_date_str)
    return datetime.date.today()


def _extract_broad_date(clause: str, ref_date: datetime.date) -> tuple[str | None, str | None]:
    """Resuelve menciones amplias como 'en enero' o 'en 2027' al primer día del periodo."""
    clause_lower = clause.lower()

    if re.search(r"\b\d{1,2}\s+de\s+(?:" + "|".join(MONTHS.keys()) + r")\b", clause_lower):
        return None, None
    if re.search(r"\b\d{4}-\d{2}-\d{2}\b|\b\d{1,2}/\d{1,2}/\d{4}\b", clause_lower):
        return None, None

    for month_name, month_num in MONTHS.items():
        match_month = re.search(
            rf"\b(?:en|para|durante)\s+{month_name}(?:\s+(?:de|del)?\s+(\d{{4}}))?\b",
            clause_lower,
        )
        if match_month:
            if match_month.group(1):
                year_val = int(match_month.group(1))
            else:
                year_val = (
                    ref_date.year + 1
                    if month_num < ref_date.month
                    else ref_date.year
                )
            first_of_month = datetime.date(year_val, month_num, 1)
            return (
                first_of_month.isoformat(),
                f"fecha aproximada (1.er día de {month_name}: {first_of_month.isoformat()})",
            )

    match_year = re.search(r"\b(?:en|para(?:\s+el)?)\s+(20\d{2})\b", clause_lower)
    if match_year:
        year_val = int(match_year.group(1))
        first_of_year = datetime.date(year_val, 1, 1)
        return (
            first_of_year.isoformat(),
            f"fecha aproximada (1.er día del año {year_val}: {first_of_year.isoformat()})",
        )

    return None, None


def _infer_date_from_time(
    date_str: str | None,
    time_str: str | None,
    ref_date: datetime.date,
    now_dt: datetime.datetime | None = None,
) -> tuple[str | None, bool]:
    """Si hay hora pero no fecha explícita, asigna ref_date o el día siguiente si ya pasó."""
    if date_str is not None or not time_str:
        return date_str, False

    current_dt = now_dt or datetime.datetime.now()
    try:
        hour, minute = [int(part) for part in time_str.split(":")[:2]]
        candidate = datetime.datetime(
            ref_date.year, ref_date.month, ref_date.day, hour, minute
        )
        if ref_date == current_dt.date() and candidate < current_dt:
            next_day = ref_date + datetime.timedelta(days=1)
            return next_day.isoformat(), True
        return ref_date.isoformat(), True
    except (ValueError, TypeError):
        return ref_date.isoformat(), True


def _expand_recurring_clause(
    clause: str,
    base_item: dict[str, Any],
    ref_date: datetime.date,
) -> list[dict[str, Any]]:
    """Genera hasta MAX_RECURRING_ITEMS recordatorios y 1 extra si se excede o no hay fin."""
    clause_lower = clause.lower()
    interval_match = re.search(
        r"\bcada\s+(\d{1,2})\s+(horas?|días?|dias?)\b", clause_lower
    )
    if not interval_match:
        return [base_item]

    interval_val = int(interval_match.group(1))
    unit_raw = interval_match.group(2)
    if interval_val <= 0:
        return [base_item]

    step = (
        datetime.timedelta(hours=interval_val)
        if unit_raw.startswith("hora")
        else datetime.timedelta(days=interval_val)
    )

    days_match = re.search(r"\b(?:por|durante)\s+(\d{1,3})\s+d[íi]as?\b", clause_lower)
    count_match = re.search(
        r"\b(?:por|durante)\s+(\d{1,3})\s+(?:tomas?|veces|dosis|ocurrencias?)\b",
        clause_lower,
    )

    requested_count: int | None = None
    if count_match:
        requested_count = int(count_match.group(1))
    elif days_match:
        days_count = max(int(days_match.group(1)), 1)
        requested_count = int(datetime.timedelta(days=days_count) // step) + 1

    start_date_str = base_item.get("date") or ref_date.isoformat()
    start_time_str = base_item.get("time") or "09:00"
    try:
        y, m, d = [int(p) for p in start_date_str.split("-")]
        hh, mm = [int(p) for p in start_time_str.split(":")]
        start_dt = datetime.datetime(y, m, d, hh, mm)
    except ValueError:
        start_dt = datetime.datetime(ref_date.year, ref_date.month, ref_date.day, 9, 0)

    is_unbounded_or_capped = requested_count is None or requested_count > MAX_RECURRING_ITEMS
    effective_count = (
        MAX_RECURRING_ITEMS
        if is_unbounded_or_capped
        else max(requested_count, 1)
    )

    expanded: list[dict[str, Any]] = []
    target_type = (
        "reminder"
        if any(k in clause_lower for k in ("tomar", "medic", "pastilla", "dosis", "paracetamol"))
        else base_item["type"]
    )

    for idx in range(effective_count):
        occ_dt = start_dt + (step * idx)
        expanded.append(
            {
                **base_item,
                "type": target_type,
                "title": f"{base_item['title']} ({idx + 1}/{effective_count})",
                "description": f"{base_item['description']} — Ocurrencia {idx + 1} de {effective_count}.",
                "date": occ_dt.date().isoformat(),
                "time": occ_dt.strftime("%H:%M"),
                "status": "pending",
            }
        )

    if is_unbounded_or_capped:
        last_dt = start_dt + (step * max(effective_count - 1, 0))
        followup_dt = last_dt + step
        duration_hint = (
            f" durante {days_match.group(1)} días"
            if days_match
            else (f" ({requested_count} solicitadas)" if requested_count else " (duración abierta)")
        )
        expanded.append(
            {
                **base_item,
                "type": "reminder",
                "title": f"Generar más recordatorios: {base_item['title'][:28]}",
                "description": (
                    f"Se generaron {MAX_RECURRING_ITEMS} recordatorios iniciales "
                    f"(cada {interval_val} {unit_raw}{duration_hint}). "
                    "Genera o configura más recordatorios si los sigues ocupando."
                ),
                "date": followup_dt.date().isoformat(),
                "time": followup_dt.strftime("%H:%M"),
                "status": "pending",
            }
        )

    return expanded

def _resolve_item_status(
    item_type: str,
    context_lower: str,
    date_str: str | None,
    ref_date: datetime.date,
    raw_status: str = "",
) -> str:
    """Determina si un elemento está completado, cancelado o pendiente según tiempo y verbos."""
    # 1. Cancelaciones explícitas o en pasado tienen prioridad sobre completado/pendiente.
    cancelled_patterns = [
        r"\bcancel(?:é|e|ó|o|ado|ada|ados|adas|aron)\b",
        r"\bse\s+cancel(?:ó|o|aron)\b",
        r"\banul(?:é|e|ó|o|ada|ado|adas|ados|aron)\b",
        r"\bsuspend(?:í|i|ió|io|ido|ida|idos|idas|ieron)\b",
        r"\bse\s+suspend(?:ió|io|ieron)\b",
    ]
    if any(re.search(p, context_lower) for p in cancelled_patterns):
        return "cancelled"

    completed_past_patterns = [
        r"\bya\s+(?:entregu(?:é|e)|complet(?:é|e)|termin(?:é|e)|realiz(?:é|e)|hice|pagu(?:é|e)|envi(?:é|e)|mand(?:é|e)|compr(?:é|e)|revis(?:é|e)|llam(?:é|e)|tom(?:é|e)|asist(?:í|i)|fui)\b",
        r"\b(?:ayer|antier|anteayer)\s+(?:entregu(?:é|e)|complet(?:é|e)|termin(?:é|e)|realiz(?:é|e)|hice|pagu(?:é|e)|envi(?:é|e)|mand(?:é|e)|compr(?:é|e)|revis(?:é|e)|llam(?:é|e)|tom(?:é|e)|asist(?:í|i)|fui)\b",
        r"\b(?:asist(?:í|i)|fui\s+a|estuve\s+en|tuvimos|asistieron)\b",
    ]
    has_past_completion = any(re.search(p, context_lower) for p in completed_past_patterns)

    if item_type == "event":
        if has_past_completion:
            return "completed"
        if date_str:
            try:
                event_date = datetime.date.fromisoformat(date_str)
                return "completed" if event_date < ref_date else "pending"
            except ValueError:
                return "pending"
        return "pending"

    # Para 'task' y 'reminder': si la acción se expresa como ya realizada o en pasado, pasa a 'completed'.
    if has_past_completion:
        return "completed"

    if raw_status in ("completed", "completado", "completada"):
        return "completed"
    if raw_status in ("cancelled", "cancelado", "cancelada"):
        return "cancelled"
    return "pending"

def _sanitize_items(
    raw_items: list[Any],
    ref_date: datetime.date,
    raw_text: str = "",
    now_dt: datetime.datetime | None = None,
) -> list[ExtractedItem]:
    """Valida, limpia, expande recurrencias y normaliza cada elemento."""
    sanitized: list[ExtractedItem] = []
    seen: set[tuple[str, str, str | None, str | None]] = set()

    for raw_item in raw_items:
        if not isinstance(raw_item, dict):
            continue

        raw_type = str(raw_item.get("type", "")).strip().lower()
        if raw_type not in ("task", "reminder", "event"):
            continue

        title = str(raw_item.get("title", "")).strip()
        if not title:
            continue

        description = str(raw_item.get("description", "")).strip() or title
        clause_context = f"{title} {description}"
        if len(raw_items) == 1 and raw_text:
            clause_context += f" {raw_text}"

        # Expande series continuas si el elemento o transcripción indica periodicidad.
        candidate_items = [raw_item]
        if re.search(r"\bcada\s+\d{1,2}\s+(?:horas?|días?|dias?)\b", clause_context.lower()):
            already_numbered = bool(re.search(r"\(\d+/\d+\)$", title))
            if not already_numbered:
                candidate_items = _expand_recurring_clause(
                    clause_context,
                    {
                        **raw_item,
                        "type": raw_type,
                        "title": title,
                        "description": description,
                    },
                    ref_date,
                )

        for item in candidate_items:
            item_type = str(item.get("type", raw_type)).strip().lower()
            item_title = str(item.get("title", title)).strip()
            item_desc = str(item.get("description", description)).strip() or item_title

            raw_priority = item.get("priority")
            if isinstance(raw_priority, str):
                raw_priority = raw_priority.strip().lower()
                if raw_priority in ("null", "none", "", "ninguna"):
                    priority = None
                elif raw_priority in ("high", "alta", "urgente"):
                    priority = "high"
                elif raw_priority in ("medium", "media", "moderada"):
                    priority = "medium"
                elif raw_priority in ("low", "baja"):
                    priority = "low"
                else:
                    priority = None
            else:
                priority = None

            raw_date = item.get("date")
            date_str: str | None = None
            if isinstance(raw_date, str):
                clean_date = raw_date.strip()
                if clean_date.lower() not in ("null", "none", ""):
                    if re.match(r"^\d{4}-\d{2}-\d{2}$", clean_date):
                        try:
                            datetime.date.fromisoformat(clean_date)
                            date_str = clean_date
                        except ValueError:
                            date_str = None

            item_context = f"{item_title} {item_desc}"
            if len(raw_items) == 1 and raw_text:
                item_context += f" {raw_text}"

            if date_str is not None:
                rel_date, _ = _extract_relative_date(item_context, ref_date)
                if rel_date:
                    date_str = rel_date
            else:
                # Si no hay fecha exacta, intenta anclar meses/años amplios al día 1.
                broad_date, broad_note = _extract_broad_date(item_context, ref_date)
                if broad_date:
                    date_str = broad_date
                    if broad_note and broad_note not in item_desc:
                        item_desc = f"{item_desc} ({broad_note})"

            raw_time = item.get("time")
            time_str: str | None = None
            if isinstance(raw_time, str):
                clean_time = raw_time.strip()
                if clean_time.lower() not in ("null", "none", ""):
                    match_time = re.match(r"^([01]?\d|2[0-3]):([0-5]\d)$", clean_time)
                    if match_time:
                        h, m = int(match_time.group(1)), match_time.group(2)
                        time_str = f"{h:02d}:{m}"

            # Si hay hora pero sigue sin fecha, resuelve hoy o mañana.
            date_str, was_inferred = _infer_date_from_time(
                date_str, time_str, ref_date, now_dt=now_dt
            )
            if was_inferred and date_str and "fecha inferida" not in item_desc.lower():
                item_desc = f"{item_desc} (fecha inferida: {date_str})"

            raw_status = str(item.get("status", "")).strip().lower()
            status = _resolve_item_status(
                item_type=item_type,
                context_lower=item_context.lower(),
                date_str=date_str,
                ref_date=ref_date,
                raw_status=raw_status,
            )

            key = (item_type, item_title.lower(), date_str, time_str)
            if key in seen:
                continue
            seen.add(key)

            sanitized.append(
                ExtractedItem(
                    type=item_type,  # type: ignore[arg-type]
                    title=item_title,
                    description=item_desc,
                    priority=priority,  # type: ignore[arg-type]
                    date=date_str,
                    time=time_str,
                    status=status,  # type: ignore[arg-type]
                )
            )

    return sanitized


def _analyze_with_groq(text: str, ref_date: datetime.date) -> list[ExtractedItem] | None:
    """Intenta analizar la transcripción usando un modelo LLM en Groq."""
    client = _get_groq_client()
    if not client:
        return None

    system_prompt = f"""Eres un analizador semántico experto de transcripciones de voz personales en español.
Tu función es identificar y extraer tareas ('task'), recordatorios ('reminder') y eventos ('event').
La fecha de referencia para hoy es: {ref_date.isoformat()} ({ref_date.strftime('%A, %d de %B de %Y')}).

Debes cumplir estrictamente las siguientes 15 reglas de extracción:
1. No inventar tareas, eventos, recordatorios, fechas, horas ni detalles que no estén respaldados por la transcripción.
2. Si no existe una fecha identificable, utilizar null; nunca sustituirla automáticamente por la fecha actual.
3. Si no se identifica una prioridad explícita o justificable, utilizar null.
4. Para tareas sin prioridad mencionada, conservar null (NO asignar medium automáticamente).
5. Asignar prioridad 'high' ante expresiones claras de urgencia, como «es urgente», «muy urgente», «es muy importante» o «lo necesito cuanto antes».
6. Asignar prioridad 'low' ante expresiones como «cuando se pueda», «no urge», «sin prisa».
7. Asignar prioridad 'medium' ÚNICAMENTE cuando se indique expresamente una importancia moderada (ej. «prioridad media», «importancia moderada»). No deducirla simplemente porque no exista urgencia.
8. Las palabras «hoy mismo» o «mañana» indican tiempo, pero NO necesariamente prioridad alta por sí solas.
9. Para eventos pasados respecto a la fecha de referencia ({ref_date.isoformat()}), utilizar status="completed"; para eventos futuros u hoy, utilizar status="pending".
10. Las tareas deben quedar en status="pending" por defecto, salvo que se indique que ya fueron completadas ("completed") o canceladas ("cancelled").
11. Los recordatorios deben quedar en status="pending" por defecto.
12. No convertir toda la transcripción en una tarea si no se identifica una acción que el usuario deba realizar. Si la transcripción es solo una charla casual, comentario general o saludo sin compromisos, devuelve "items": [].
13. Si hay varios elementos, extraerlos individualmente sin duplicarlos.
14. Si una fecha es ambigua y no puede resolverse con seguridad, dejarla en null.
15. El análisis debe devolver EXCLUSIVAMENTE JSON válido con un objeto raíz "items", sin texto adicional ni markdown.

Formato esperado:
{{
  "items": [
    {{
      "type": "task" | "reminder" | "event",
      "title": "título breve y conciso",
      "description": "detalles relevantes extraídos",
      "priority": "high" | "medium" | "low" | null,
      "date": "YYYY-MM-DD" | null,
      "time": "HH:mm" | null,
      "status": "pending" | "completed" | "cancelled"
    }}
  ]
}}
Todos los 7 campos deben estar siempre presentes.
"""

    models_to_try = [
        "openai/gpt-oss-120b",
        "qwen/qwen3.8-27b",
        "openai/gpt-oss-20b",
        "llama-3.3-70b-versatile",
        "llama-3.1-8b-instant",
    ]

    for model_name in models_to_try:
        try:
            logger.info("Enviando transcripción a Groq con modelo %s...", model_name)
            completion = client.chat.completions.create(
                model=model_name,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": text},
                ],
                temperature=0.0,
                response_format={"type": "json_object"},
            )
            raw_content = completion.choices[0].message.content or "{}"
            parsed = json.loads(raw_content)
            items_raw = parsed.get("items", [])
            if isinstance(items_raw, list):
                return _sanitize_items(items_raw, ref_date, raw_text=text)
        except Exception as exc:
            logger.warning("Fallo al consultar Groq (%s): %s", model_name, exc)

    return None


def _extract_relative_date(clause: str, ref_date: datetime.date) -> tuple[str | None, str]:
    """Extrae fecha relativa o explícita de una cláusula y devuelve (fecha_iso, clausula_limpia)."""
    clause_lower = clause.lower()

    if "pasado mañana" in clause_lower:
        d = ref_date + datetime.timedelta(days=2)
        return d.isoformat(), clause
    if "mañana" in clause_lower:
        d = ref_date + datetime.timedelta(days=1)
        return d.isoformat(), clause
    if "hoy mismo" in clause_lower or " hoy" in clause_lower or clause_lower.startswith("hoy"):
        return ref_date.isoformat(), clause
    if "anteayer" in clause_lower or "antier" in clause_lower or "antes de ayer" in clause_lower:
        d = ref_date - datetime.timedelta(days=2)
        return d.isoformat(), clause
    if "ayer" in clause_lower:
        d = ref_date - datetime.timedelta(days=1)
        return d.isoformat(), clause

    for day_name, day_idx in DAYS_OF_WEEK.items():
        pattern_past = rf"\b(?:el\s+)?{day_name}\s+pasado\b|\bpasado\s+{day_name}\b"
        if re.search(pattern_past, clause_lower):
            delta = (ref_date.weekday() - day_idx) % 7
            if delta == 0:
                delta = 7
            d = ref_date - datetime.timedelta(days=delta)
            return d.isoformat(), clause

        pattern_next = rf"\b(?:el\s+)?próximo\s+{day_name}\b|\b(?:el\s+)?{day_name}\s+que\s+viene\b"
        if re.search(pattern_next, clause_lower):
            delta = (day_idx - ref_date.weekday()) % 7
            if delta == 0:
                delta = 7
            d = ref_date + datetime.timedelta(days=delta)
            return d.isoformat(), clause

        pattern_day = rf"\bel\s+{day_name}\b"
        if re.search(pattern_day, clause_lower):
            is_past = any(w in clause_lower for w in ("asistí", "fui", "estuve", "entregué", "hice", "terminé", "ocurrió"))
            if is_past:
                delta = (ref_date.weekday() - day_idx) % 7
                if delta == 0:
                    delta = 7
                d = ref_date - datetime.timedelta(days=delta)
            else:
                delta = (day_idx - ref_date.weekday()) % 7
                if delta == 0:
                    delta = 7
                d = ref_date + datetime.timedelta(days=delta)
            return d.isoformat(), clause

    for month_name, month_num in MONTHS.items():
        pattern_cal = rf"\b(?:el\s+)?(\d{{1,2}})\s+de\s+{month_name}(?:\s+(?:de|del)?\s+(\d{{4}}))?\b"
        match = re.search(pattern_cal, clause_lower)
        if match:
            day_val = int(match.group(1))
            year_val = int(match.group(2)) if match.group(2) else ref_date.year
            try:
                d = datetime.date(year_val, month_num, day_val)
                return d.isoformat(), clause
            except ValueError:
                return None, clause

    match_iso = re.search(r"\b(\d{4})-(\d{2})-(\d{2})\b", clause)
    if match_iso:
        try:
            d = datetime.date(int(match_iso.group(1)), int(match_iso.group(2)), int(match_iso.group(3)))
            return d.isoformat(), clause
        except ValueError:
            pass

    match_slash = re.search(r"\b(\d{1,2})/(\d{1,2})/(\d{4})\b", clause)
    if match_slash:
        try:
            d = datetime.date(int(match_slash.group(3)), int(match_slash.group(2)), int(match_slash.group(1)))
            return d.isoformat(), clause
        except ValueError:
            pass

    return None, clause


def _extract_time(clause: str) -> str | None:
    """Extrae hora en formato HH:mm si existe."""
    clause_lower = clause.lower()

    match = re.search(r"\b([01]?\d|2[0-3]):([0-5]\d)\s*(am|pm)?\b", clause_lower)
    if match:
        h = int(match.group(1))
        m = match.group(2)
        ampm = match.group(3)
        if ampm == "pm" and h < 12:
            h += 12
        elif ampm == "am" and h == 12:
            h = 0
        return f"{h:02d}:{m}"

    match_natural = re.search(r"\ba\s+las\s+(\d{1,2})(?::([0-5]\d))?\s*(de la tarde|de la noche|de la mañana|am|pm|horas)?\b", clause_lower)
    if match_natural:
        h = int(match_natural.group(1))
        m = match_natural.group(2) or "00"
        period = match_natural.group(3) or ""
        if ("tarde" in period or "noche" in period or period == "pm") and h < 12:
            h += 12
        elif (period == "am" or "mañana" in period) and h == 12:
            h = 0
        if 0 <= h <= 23:
            return f"{h:02d}:{m}"

    return None


def _extract_priority(clause: str) -> str | None:
    """Determina la prioridad siguiendo las reglas 3, 4, 5, 6, 7 y 8."""
    clause_lower = clause.lower()

    high_triggers = [
        "es urgente",
        "muy urgente",
        "urgente",
        "es muy importante",
        "muy importante",
        "lo necesito cuanto antes",
        "cuanto antes",
        "prioridad alta",
        "máxima prioridad",
        "maxima prioridad",
        "de inmediato",
        "urgentemente",
    ]
    if any(t in clause_lower for t in high_triggers):
        return "high"

    low_triggers = [
        "cuando se pueda",
        "no urge",
        "sin prisa",
        "prioridad baja",
        "baja prioridad",
        "no es urgente",
        "con calma",
    ]
    if any(t in clause_lower for t in low_triggers):
        return "low"

    medium_triggers = [
        "importancia moderada",
        "prioridad media",
        "moderadamente importante",
        "importancia media",
    ]
    if any(t in clause_lower for t in medium_triggers):
        return "medium"

    return None


def _clean_title(text: str) -> str:
    """Limpia el texto para generar un título conciso."""
    text = re.sub(
        r"^(?:ya\s+)?(?:tengo que|debo|hay que|toca|necesito|recordar|no olvidar|tener presente|asistí a|asisti a|fui a|recordatorio de|tarea:?)\s+",
        "",
        text,
        flags=re.IGNORECASE,
    )
    text = re.sub(
        r",?\s*(?:es urgente|muy urgente|cuanto antes|cuando se pueda|no urge|sin prisa|con calma|prioridad\s+(?:alta|media|baja)).*$",
        "",
        text,
        flags=re.IGNORECASE,
    )
    text = text.strip(". ,")
    if text:
        return text[0].upper() + text[1:]
    return "Elemento"


def _analyze_with_rules(text: str, ref_date: datetime.date) -> list[ExtractedItem]:
    """Motor de análisis determinista basado en reglas y PLN en español (cumple reglas 1-15)."""
    text_clean = text.strip()
    if not text_clean:
        return []

    split_pattern = r"(?<=[.!?])\s+|;\s*|\s+(?:y además|y también|por otro lado|asimismo|y tengo que|y debo|y hay que)\s+"
    raw_clauses = re.split(split_pattern, text_clean)

    clauses: list[str] = []
    for c in raw_clauses:
        c = c.strip()
        if not c:
            continue
        sub_parts = re.split(r",?\s+(?:además|también|y por último)\s+", c, flags=re.IGNORECASE)
        for sp in sub_parts:
            sp = sp.strip()
            if sp:
                clauses.append(sp)

    extracted: list[dict[str, Any]] = []

    task_verbs = [
        r"\b(?:tengo que|debo|hay que|toca|necesito|urge)\b",
        r"\b(?:entreg(?:ar|ué|ue|o|a|amos|an|ado|ada|ados|adas)|termin(?:ar|é|e|o|a|amos|an|ado|ada)|complet(?:ar|é|e|o|a|amos|an|ado|ada))\b",
        r"\b(?:hacer|hago|haremos|hagan|haz|hice|hecho|haciendo|hace\s+falta|realic(?:é|e)|realiz(?:ar|o|a|ado))\b",
        r"\b(?:envi(?:ar|é|e|o|a|amos|an|ado)|mand(?:ar|é|e|o|a|ado))\b",
        r"\b(?:compr(?:ar|é|e|o|a|amos|an|ado)|adquirir)\b",
        r"\b(?:revis(?:ar|é|e|o|a|amos|an|ado)|verific(?:ar|é|e|o|a|ado)|checar)\b",
        r"\b(?:prepar(?:ar|é|e|o|a|amos|an|ado)|cocinar|elaborar)\b",
        r"\b(?:pag(?:ar|ué|ue|o|a|amos|an|ado)|liquidar|cobrar)\b",
        r"\b(?:llam(?:ar|é|e|o|a|amos|an|ado)|contactar|escribirle a)\b",
        r"\b(?:arregl(?:ar|é|e|o|a|ado)|repar(?:ar|é|e|o|a|ado)|arregle|repare)\b",
        r"\b(?:limpi(?:ar|é|e|o|a|ado)|asear|lavar)\b",
        r"\b(?:organiz(?:ar|é|e|o|a|ado)|orden(?:ar|é|e|o|a|ado)|clasificar)\b",
        r"\b(?:estudi(?:ar|é|e|o|a|ado)|leer|repasar)\b",
        r"\b(?:escrib(?:ir|í|i|o|e|en|iendo|ito)|redactar)\b",
        r"\b(?:actualiz(?:ar|é|e|o|a|ado)|renovar)\b",
        r"\b(?:resolv(?:er|í|i|o|e|iendo|uelto)|solucionar)\b",
        r"\b(?:subir|descargar|imprimir|enviar|instalar|configurar)\b",
        r"\b(?:cancel(?:ar|é|e|o|a|ado|ada)|anular)\b",
        r"\b(?:entrega del?|pago del?|llamada a|revisión del?|envío del?|organización del?|limpieza del?|pedido del?)\b",
    ]
    reminder_triggers = [
        r"\b(?:cumpleaños de|aniversario de|recordar|no olvidar|tener presente|acordarme de|acordarse de|recordatorio)\b",
        r"\b(?:fecha importante|día importante)\b",
        r"\b(?:tomar|pastilla|medicamento|paracetamol|dosis)\b",
    ]
    event_triggers = [
        r"\b(?:clase de|reunión con|reunion con|cita médica|cita con|conferencia|partido de|asistí a|asisti a|fui a|estuve en|taller de|sesión de|sesion de|concierto de|entrenamiento de|webinar)\b",
        r"\b(?:tuvimos reunión|tenemos reunión|habrá reunión)\b",
    ]

    for clause in clauses:
        clause_lower = clause.lower()

        is_reminder = any(re.search(p, clause_lower) for p in reminder_triggers)
        is_event = any(re.search(p, clause_lower) for p in event_triggers)
        is_task = any(re.search(p, clause_lower) for p in task_verbs)

        if not (is_reminder or is_event or is_task):
            continue

        item_type: str
        if is_reminder:
            item_type = "reminder"
        elif is_event:
            item_type = "event"
        else:
            item_type = "task"

        date_val, _ = _extract_relative_date(clause, ref_date)
        broad_note: str | None = None
        if not date_val:
            date_val, broad_note = _extract_broad_date(clause, ref_date)

        time_val = _extract_time(clause)
        priority_val = _extract_priority(clause)
        status_val = _resolve_item_status(
            item_type=item_type,
            context_lower=clause_lower,
            date_str=date_val,
            ref_date=ref_date,
            raw_status="",
        )

        title_val = _clean_title(clause)
        if len(title_val) > 60:
            cut = title_val[:60].rfind(" ")
            title_val = title_val[:cut] if cut > 20 else title_val[:60]

        description_val = clause.strip(". ")
        if broad_note and broad_note not in description_val:
            description_val = f"{description_val} ({broad_note})"

        extracted.append({
            "type": item_type,
            "title": title_val,
            "description": description_val,
            "priority": priority_val,
            "date": date_val,
            "time": time_val,
            "status": status_val,
        })

    return _sanitize_items(extracted, ref_date, raw_text=text)


def analyze_transcription(text: str, reference_date: str | None = None) -> dict[str, Any]:
    """Punto de entrada principal para analizar una transcripción."""
    ref_date = parse_reference_date(reference_date)

    if not text or not text.strip():
        return {"items": []}

    groq_items = _analyze_with_groq(text, ref_date)
    if groq_items is not None:
        if len(groq_items) == 0:
            rule_items = _analyze_with_rules(text, ref_date)
            if rule_items:
                logger.info(
                    "Groq devolvió 0 elementos; respaldo de reglas extrajo %d",
                    len(rule_items),
                )
                return {"items": [item.model_dump() for item in rule_items]}
        logger.info("Análisis completado con Groq: %d elementos extraídos", len(groq_items))
        return {"items": [item.model_dump() for item in groq_items]}

    logger.info("Analizando transcripción con motor basado en reglas y PLN local...")
    rule_items = _analyze_with_rules(text, ref_date)
    logger.info("Análisis completado con reglas: %d elementos extraídos", len(rule_items))
    return {"items": [item.model_dump() for item in rule_items]}