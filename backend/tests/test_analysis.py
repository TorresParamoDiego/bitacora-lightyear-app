"""Pruebas automáticas para el módulo de análisis de transcripciones y extracción de información."""

import pytest
from fastapi.testclient import TestClient

from main import app
from schemas.analysis import ExtractedItem
from services.analysis_service import (
    analyze_transcription,
    _analyze_with_rules,
    parse_reference_date,
)
from services.item_storage_service import save_items, list_items

client = TestClient(app)


def test_standardized_json_structure():
    """Regla 15 y Estructura: La respuesta debe tener siempre un objeto raíz con 'items' y todos los 7 campos."""
    res = client.post("/api/analysis", json={"text": "Comprar materiales mañana a las 10:00", "reference_date": "2026-10-13"})
    assert res.status_code == 200
    data = res.json()
    assert "items" in data
    assert isinstance(data["items"], list)
    assert len(data["items"]) >= 1

    for item in data["items"]:
        # Todos los 7 campos deben estar presentes
        for field in ("type", "title", "description", "priority", "date", "time", "status"):
            assert field in item, f"Falta el campo {field} en el elemento"
        assert item["type"] in ("task", "reminder", "event")
        assert item["priority"] in ("high", "medium", "low", None)
        assert item["status"] in ("pending", "completed", "cancelled")


def test_multi_item_extraction_from_prompt_example():
    """Prueba del ejemplo estándar del prompt: tarea urgente, recordatorio y evento pasado."""
    text = (
        "Entregar el proyecto de bases de datos el 17 de octubre, es urgente. "
        "Tener presente el cumpleaños de Ana el 20 de noviembre. "
        "Asistí a clase de natación el 10 de octubre."
    )
    result = analyze_transcription(text, reference_date="2026-10-13")
    items = result["items"]

    assert len(items) == 3

    # Buscar la tarea
    task = next((i for i in items if i["type"] == "task"), None)
    assert task is not None
    assert "Entregar" in task["title"] or "proyecto" in task["title"].lower()
    assert task["priority"] == "high"
    assert task["date"] == "2026-10-17"
    assert task["status"] == "pending"

    # Buscar el recordatorio
    reminder = next((i for i in items if i["type"] == "reminder"), None)
    assert reminder is not None
    assert "Ana" in reminder["title"] or "Ana" in reminder["description"]
    assert reminder["priority"] is None
    assert reminder["date"] == "2026-11-20"
    assert reminder["status"] == "pending"

    # Buscar el evento
    event = next((i for i in items if i["type"] == "event"), None)
    assert event is not None
    assert "natación" in event["title"].lower() or "natación" in event["description"].lower()
    assert event["priority"] is None
    assert event["date"] == "2026-10-10"
    # Regla 9: evento pasado debe ser completed
    assert event["status"] == "completed"


def test_rule_2_missing_date_is_null_not_today():
    """Regla 2: Si no existe una fecha identificable, utilizar null; nunca sustituirla por hoy."""
    text = "Comprar café para la oficina"
    result = analyze_transcription(text, reference_date="2026-10-13")
    items = result["items"]
    assert len(items) == 1
    assert items[0]["date"] is None
    assert items[0]["time"] is None


def test_rule_3_and_4_missing_priority_is_null():
    """Reglas 3 y 4: Si no se menciona prioridad, conservar null (no medium por defecto)."""
    text = "Hacer la tarea de matemáticas"
    result = analyze_transcription(text, reference_date="2026-10-13")
    items = result["items"]
    assert len(items) == 1
    assert items[0]["priority"] is None


def test_rule_5_high_priority_urgency_expressions():
    """Regla 5: Expresiones de urgencia («es urgente», «es muy importante», «lo necesito cuanto antes») -> high."""
    cases = [
        ("Entregar el informe es urgente", "high"),
        ("Revisar el servidor es muy importante", "high"),
        ("Enviar el presupuesto lo necesito cuanto antes", "high"),
        ("Pagar la luz muy urgente", "high"),
    ]
    for text, expected in cases:
        result = analyze_transcription(text, reference_date="2026-10-13")
        assert len(result["items"]) >= 1, f"No extrajo elemento para: {text}"
        assert result["items"][0]["priority"] == expected, f"Falló para: {text}"


def test_rule_6_low_priority_expressions():
    """Regla 6: Expresiones como «cuando se pueda», «no urge», «sin prisa» -> low."""
    cases = [
        ("Arreglar la puerta cuando se pueda", "low"),
        ("Organizar los libros viejos no urge", "low"),
        ("Limpiar el garaje sin prisa", "low"),
    ]
    for text, expected in cases:
        result = analyze_transcription(text, reference_date="2026-10-13")
        assert len(result["items"]) >= 1
        assert result["items"][0]["priority"] == expected


def test_rule_7_medium_priority_explicit_only():
    """Regla 7: Prioridad medium únicamente cuando se exprese importancia moderada."""
    text = "Actualizar la documentación con prioridad media"
    result = analyze_transcription(text, reference_date="2026-10-13")
    assert len(result["items"]) >= 1
    assert result["items"][0]["priority"] == "medium"


def test_rule_8_hoy_and_manana_do_not_imply_high_priority():
    """Regla 8: Las palabras «hoy mismo» o «mañana» indican tiempo, NO prioridad alta por sí solas."""
    text = "Comprar los boletos mañana"
    result = analyze_transcription(text, reference_date="2026-10-13")
    assert len(result["items"]) == 1
    item = result["items"][0]
    assert item["date"] == "2026-10-14"
    assert item["priority"] is None, "Mañana no debe asignar prioridad alta automáticamente"


def test_rule_9_event_status_past_vs_future():
    """Regla 9: Eventos pasados completed, eventos futuros pending."""
    # Pasado
    past_text = "Asistí a la reunión con el cliente el 10 de octubre"
    res_past = analyze_transcription(past_text, reference_date="2026-10-13")
    assert res_past["items"][0]["type"] == "event"
    assert res_past["items"][0]["status"] == "completed"

    # Futuro
    future_text = "Reunión con el director el 25 de octubre"
    res_future = analyze_transcription(future_text, reference_date="2026-10-13")
    assert res_future["items"][0]["type"] == "event"
    assert res_future["items"][0]["status"] == "pending"


def test_rule_10_task_status_default_and_completed():
    """Regla 10: Tareas pending por defecto, salvo completadas expresamente."""
    text_pending = "Entregar el informe de ventas"
    res1 = analyze_transcription(text_pending, reference_date="2026-10-13")
    assert res1["items"][0]["status"] == "pending"

    text_completed = "Ya entregué el informe de ventas"
    res2 = analyze_transcription(text_completed, reference_date="2026-10-13")
    assert res2["items"][0]["status"] == "completed"


def test_rule_11_reminder_status_default():
    """Regla 11: Los recordatorios deben quedar en pending por defecto."""
    text = "Tener presente el aniversario de la empresa"
    res = analyze_transcription(text, reference_date="2026-10-13")
    assert res["items"][0]["type"] == "reminder"
    assert res["items"][0]["status"] == "pending"


def test_rule_12_casual_speech_produces_zero_items():
    """Regla 12: No convertir toda la transcripción en tarea si no hay una acción."""
    casual_texts = [
        "Hoy el cielo estaba muy despejado y me tomé un café por la mañana.",
        "Qué bonito día hace hoy para salir a caminar.",
        "Hola probando el micrófono uno dos tres.",
    ]
    for text in casual_texts:
        res = analyze_transcription(text, reference_date="2026-10-13")
        assert res["items"] == [], f"Esperaba lista vacía para charla casual: {text}"


def test_time_extraction():
    """Prueba de extracción de hora en diferentes formatos."""
    text = "Reunión con el equipo a las 14:30"
    res = analyze_transcription(text, reference_date="2026-10-13")
    assert res["items"][0]["time"] == "14:30"

    text2 = "Clase de piano a las 4 de la tarde"
    res2 = analyze_transcription(text2, reference_date="2026-10-13")
    assert res2["items"][0]["time"] == "16:00"


def test_save_and_retrieve_items_api():
    """Prueba del flujo de guardado de elementos confirmados a través del backend."""
    item1 = ExtractedItem(
        type="task",
        title="Enviar reporte",
        description="Reporte final a gerencia",
        priority="high",
        date="2026-10-15",
        time="09:00",
        status="pending",
    )
    item2 = ExtractedItem(
        type="reminder",
        title="Cumpleaños de Laura",
        description="Comprar regalo de cumpleaños",
        priority=None,
        date="2026-11-05",
        time=None,
        status="pending",
    )

    save_payload = {"items": [item1.model_dump(), item2.model_dump()]}
    save_res = client.post("/api/items", json=save_payload)
    assert save_res.status_code == 201
    save_data = save_res.json()
    assert save_data["saved_count"] == 2
    assert len(save_data["items"]) == 2

    # Verificar que GET /api/items devuelve los elementos
    get_res = client.get("/api/items")
    assert get_res.status_code == 200
    get_data = get_res.json()
    assert "items" in get_data
    titles = [i["title"] for i in get_data["items"]]
    assert "Enviar reporte" in titles
    assert "Cumpleaños de Laura" in titles


def test_rule_13_multiple_items_without_duplicates():
    """Regla 13: Extraer múltiples elementos individualmente sin duplicarlos."""
    text = (
        "Comprar hojas para la impresora. "
        "Y además revisar el proyecto final el 18 de octubre. "
        "Comprar hojas para la impresora."  # repetido intencionalmente
    )
    res = analyze_transcription(text, reference_date="2026-10-13")
    items = res["items"]
    # No debe duplicar "Comprar hojas para la impresora"
    assert len(items) == 2
    titles = [i["title"].lower() for i in items]
    assert any("comprar hojas" in t for t in titles)
    assert any("revisar" in t for t in titles)


def test_rule_14_ambiguous_date_remains_null():
    """Regla 14: Si una fecha es ambigua y no puede resolverse con seguridad, dejarla en null."""
    text = "Hacer la limpieza general en algún momento del año"
    res = analyze_transcription(text, reference_date="2026-10-13")
    assert len(res["items"]) == 1
    assert res["items"][0]["date"] is None


def test_cancelled_task_status():
    """Regla 10: Tareas canceladas tienen estado cancelled."""
    text = "Cancelé el pedido de materiales"
    res = analyze_transcription(text, reference_date="2026-10-13")
    assert len(res["items"]) == 1
    assert res["items"][0]["status"] == "cancelled"


def test_relative_weekday_dates():
    """Prueba resolución de fechas relativas como 'el próximo viernes' y 'el viernes pasado'."""
    # reference_date: 2026-10-13 (martes)
    # viernes pasado fue 2026-10-09
    # próximo viernes es 2026-10-16
    past_text = "Asistí a la conferencia el viernes pasado"
    res_past = analyze_transcription(past_text, reference_date="2026-10-13")
    assert res_past["items"][0]["date"] == "2026-10-09"
    assert res_past["items"][0]["status"] == "completed"

    future_text = "Reunión con el equipo el próximo viernes"
    res_future = analyze_transcription(future_text, reference_date="2026-10-13")
    assert res_future["items"][0]["date"] == "2026-10-16"
    assert res_future["items"][0]["status"] == "pending"
