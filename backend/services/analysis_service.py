"""Servicio de análisis automático de transcripciones para extracción de tareas, eventos y recordatorios."""

import datetime
import json
import logging
import os
import re
from typing import Any

from dotenv import load_dotenv
from groq import Groq
from backend.schemas.analysis import ExtractedItem

load_dotenv()

logger = logging.getLogger("uvicorn.error")

_GROQ_CLIENT: Groq | None = None

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


def _sanitize_items(raw_items: list[Any], ref_date: datetime.date, raw_text: str = "") -> list[ExtractedItem]:
    """Valida, limpia y normaliza cada elemento según las 15 reglas estandarizadas."""
    sanitized: list[ExtractedItem] = []
    seen: set[tuple[str, str, str | None]] = set()

    for item in raw_items:
        if not isinstance(item, dict):
            continue

        raw_type = str(item.get("type", "")).strip().lower()
        if raw_type not in ("task", "reminder", "event"):
            continue

        title = str(item.get("title", "")).strip()
        if not title:
            continue

        description = str(item.get("description", "")).strip() or title

        # Prioridad (Reglas 3, 4, 5, 6, 7, 8)
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

        # Fecha (Reglas 2, 14)
        raw_date = item.get("date")
        date_str: str | None = None
        if isinstance(raw_date, str):
            clean_date = raw_date.strip()
            if clean_date.lower() not in ("null", "none", ""):
                # Validar formato YYYY-MM-DD
                if re.match(r"^\d{4}-\d{2}-\d{2}$", clean_date):
                    try:
                        datetime.date.fromisoformat(clean_date)
                        date_str = clean_date
                    except ValueError:
                        date_str = None

        # Si el modelo asignó una fecha, verificar si hay expresión relativa explícita para evitar errores de cálculo aritmético del LLM
        if date_str is not None:
            context_to_search = f"{title} {description}"
            if len(raw_items) == 1 and raw_text:
                context_to_search += f" {raw_text}"
            rel_date, _ = _extract_relative_date(context_to_search, ref_date)
            if rel_date:
                date_str = rel_date

        # Hora
        raw_time = item.get("time")
        time_str: str | None = None
        if isinstance(raw_time, str):
            clean_time = raw_time.strip()
            if clean_time.lower() not in ("null", "none", ""):
                match_time = re.match(r"^([01]?\d|2[0-3]):([0-5]\d)$", clean_time)
                if match_time:
                    h, m = int(match_time.group(1)), match_time.group(2)
                    time_str = f"{h:02d}:{m}"

        # Estado (Reglas 9, 10, 11)
        raw_status = str(item.get("status", "")).strip().lower()
        if raw_status in ("completed", "completado", "completada"):
            status = "completed"
        elif raw_status in ("cancelled", "cancelado", "cancelada"):
            status = "cancelled"
        elif raw_status in ("pending", "pendiente"):
            status = "pending"
        else:
            status = "pending"

        # Regla 9: Para eventos pasados completed, para futuros u hoy pending
        if raw_type == "event":
            if date_str:
                try:
                    event_date = datetime.date.fromisoformat(date_str)
                    status = "completed" if event_date < ref_date else "pending"
                except ValueError:
                    status = "pending"
            else:
                past_indicators = ["asistí", "asisti", "fui a", "estuve en", "tuvimos", "asistieron"]
                if any(w in f"{title.lower()} {description.lower()} {raw_text.lower()}" for w in past_indicators):
                    status = "completed"
                else:
                    status = "pending"

        # Refuerzo para tareas o elementos cancelados expresamente
        lower_context = f"{title.lower()} {description.lower()}"
        if len(raw_items) == 1 and raw_text:
            lower_context += f" {raw_text.lower()}"
        if any(w in lower_context for w in [
            "cancelé", "cancele", "canceló", "cancelo", "cancelado", "cancelada",
            "se canceló", "se cancelo", "anulado", "anulada", "anuló", "anulo"
        ]):
            status = "cancelled"

        # Deduplicación (Regla 13)
        key = (raw_type, title.lower(), date_str)
        if key in seen:
            continue
        seen.add(key)

        sanitized.append(
            ExtractedItem(
                type=raw_type,  # type: ignore[arg-type]
                title=title,
                description=description,
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

    # 1. Expresiones relativas fijas
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

    # 2. Días de la semana pasados/próximos: "el viernes pasado", "el próximo viernes", "el viernes"
    for day_name, day_idx in DAYS_OF_WEEK.items():
        pattern_past = rf"\b(?:el\s+)?{day_name}\s+pasado\b|\bpasado\s+{day_name}\b"
        if re.search(pattern_past, clause_lower):
            # Calcular hacia atrás
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
            # Si el contexto parece pasado ("asistí el viernes", "fue el viernes")
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

    # 3. Fechas calendario: "17 de octubre", "20 de noviembre de 2026", "el 10 de octubre"
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

    # 4. Formato ISO directo "2026-10-17" o "17/10/2026"
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

    # Formato directo "14:30", "04:30 pm", "9:00 am"
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

    # Formato natural "a las 4 de la tarde", "a las 9 de la mañana", "a las 5 pm", "a las 16 horas"
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

    # Regla 5: Expresiones de alta urgencia
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

    # Regla 6: Expresiones de baja urgencia
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

    # Regla 7: Importancia moderada expresa (NO deducida)
    medium_triggers = [
        "importancia moderada",
        "prioridad media",
        "moderadamente importante",
        "importancia media",
    ]
    if any(t in clause_lower for t in medium_triggers):
        return "medium"

    # Regla 3 y 4: Si no hay mención explícita o justificable, siempre null
    return None


def _clean_title(text: str) -> str:
    """Limpia el texto para generar un título conciso."""
    text = re.sub(
        r"^(?:ya\s+)?(?:tengo que|debo|hay que|toca|necesito|recordar|no olvidar|tener presente|asistí a|asisti a|fui a|recordatorio de|tarea:?)\s+",
        "",
        text,
        flags=re.IGNORECASE,
    )
    # Remover expresiones de urgencia o fechas al final
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

    # Regla 12: Si no hay acciones, eventos ni recordatorios, devolver lista vacía
    # Separar en fragmentos o frases
    split_pattern = r"(?<=[.!?])\s+|;\s*|\s+(?:y además|y también|por otro lado|asimismo|y tengo que|y debo|y hay que)\s+"
    raw_clauses = re.split(split_pattern, text_clean)

    # Si sólo hay una cláusula pero contiene conectores ("y", "también"), revisar si se divide
    clauses: list[str] = []
    for c in raw_clauses:
        c = c.strip()
        if not c:
            continue
        # Sub-dividir si tiene múltiples acciones explícitas unidas por " y " o " además "
        sub_parts = re.split(r",?\s+(?:además|también|y por último)\s+", c, flags=re.IGNORECASE)
        for sp in sub_parts:
            sp = sp.strip()
            if sp:
                clauses.append(sp)

    extracted: list[dict[str, Any]] = []

    # Verbos y patrones para cada tipo (infinitivos y formas conjugadas comunes)
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
    ]
    event_triggers = [
        r"\b(?:clase de|reunión con|reunion con|cita médica|cita con|conferencia|partido de|asistí a|asisti a|fui a|estuve en|taller de|sesión de|sesion de|concierto de|entrenamiento de|webinar)\b",
        r"\b(?:tuvimos reunión|tenemos reunión|habrá reunión)\b",
    ]

    for clause in clauses:
        clause_lower = clause.lower()

        # Determinar si contiene algún tipo
        is_reminder = any(re.search(p, clause_lower) for p in reminder_triggers)
        is_event = any(re.search(p, clause_lower) for p in event_triggers)
        is_task = any(re.search(p, clause_lower) for p in task_verbs)

        # Regla 12: si no coincide con ninguno, omitir
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
        time_val = _extract_time(clause)
        priority_val = _extract_priority(clause)

        # Estado
        if item_type == "event":
            # Regla 9: Para eventos pasados completed, para futuros pending
            past_indicators = ["asistí", "asisti", "fui a", "estuve en", "tuvimos", "asistieron"]
            if any(w in clause_lower for w in past_indicators):
                status_val = "completed"
            elif date_val:
                try:
                    d_parsed = datetime.date.fromisoformat(date_val)
                    status_val = "completed" if d_parsed < ref_date else "pending"
                except ValueError:
                    status_val = "pending"
            else:
                status_val = "pending"
        elif item_type == "task":
            # Regla 10: Tareas pending por defecto, salvo completadas o canceladas
            if any(w in clause_lower for w in ["ya entregué", "ya completé", "ya terminé", "ya lo hice", "ya realicé"]):
                status_val = "completed"
            elif any(w in clause_lower for w in ["cancelé", "se canceló", "cancelada"]):
                status_val = "cancelled"
            else:
                status_val = "pending"
        else:
            # Regla 11: Recordatorios pending por defecto
            status_val = "pending"

        # Título y descripción
        title_val = _clean_title(clause)
        # Limitar título a 60 caracteres
        if len(title_val) > 60:
            # Truncar en la última palabra
            cut = title_val[:60].rfind(" ")
            title_val = title_val[:cut] if cut > 20 else title_val[:60]

        description_val = clause.strip(". ")

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
    """Punto de entrada principal para analizar una transcripción.

    Usa Groq LLM si está disponible; de lo contrario o si falla, recurre al
    motor determinista basado en reglas. Siempre devuelve la estructura JSON:
    {"items": [...]}
    """
    ref_date = parse_reference_date(reference_date)

    if not text or not text.strip():
        return {"items": []}

    # 1. Intentar con Groq si hay API key configurada
    groq_items = _analyze_with_groq(text, ref_date)
    if groq_items is not None:
        logger.info("Análisis completado con Groq: %d elementos extraídos", len(groq_items))
        return {"items": [item.model_dump() for item in groq_items]}

    # 2. Respaldo determinista con reglas y PLN
    logger.info("Analizando transcripción con motor basado en reglas y PLN local...")
    rule_items = _analyze_with_rules(text, ref_date)
    logger.info("Análisis completado con reglas: %d elementos extraídos", len(rule_items))
    return {"items": [item.model_dump() for item in rule_items]}
