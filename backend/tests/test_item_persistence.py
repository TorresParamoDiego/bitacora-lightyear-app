import json
from types import SimpleNamespace

from fastapi.testclient import TestClient

from api import analysis as analysis_api
from main import app
from schemas.analysis import ExtractedItem
from services import item_storage_service

client = TestClient(app)


def test_save_items_persists_user_and_bucket_audio_id(monkeypatch):
    saved_records = []

    class InsertQuery:
        def insert(self, records):
            saved_records.extend(records)
            return self

        def execute(self):
            return SimpleNamespace(data=saved_records)

    monkeypatch.setattr(
        item_storage_service.supabase,
        "table",
        lambda table_name: InsertQuery(),
    )

    count, result = item_storage_service.save_items(
        [ExtractedItem(type="task", title="Enviar reporte", description="")],
        user_id="user-123",
        recording_id="audio-456",
    )

    assert count == 1
    assert result[0]["user_id"] == "user-123"
    assert result[0]["recording_id"] == "audio-456"
    assert saved_records == result


def test_save_with_audio_stores_bucket_id_in_inserted_items(monkeypatch):
    audio_id = "audio-object-id"

    async def fake_save_audio(_file):
        return {"id": audio_id}

    inserted = []

    def fake_save_items(items, user_id, recording_id):
        inserted.extend(
            {
                "id": "item-id",
                "user_id": user_id,
                "recording_id": recording_id,
                **item.model_dump(),
            }
            for item in items
        )
        return len(inserted), inserted

    monkeypatch.setenv("TEST_USER_ID", "user-123")
    monkeypatch.setattr(analysis_api, "save_audio", fake_save_audio)
    monkeypatch.setattr(analysis_api, "save_items", fake_save_items)

    response = client.post(
        "/api/items/with-audio",
        data={
            "items": json.dumps(
                {
                    "items": [
                        {
                            "type": "task",
                            "title": "Enviar reporte",
                            "description": "Reporte final",
                            "priority": "high",
                            "date": "2026-10-15",
                            "time": "09:00",
                            "status": "pending",
                        }
                    ]
                }
            )
        },
        files={"audio": ("recording.aac", b"audio", "audio/aac")},
    )

    assert response.status_code == 201
    assert inserted[0]["recording_id"] == audio_id
    assert response.json()["items"][0]["recording_id"] == audio_id


def test_failed_item_insert_removes_uploaded_audio(monkeypatch):
    removed_ids = []

    async def fake_save_audio(_file):
        return {"id": "orphan-candidate"}

    def fail_save_items(_items, _user_id, _recording_id):
        raise RuntimeError("database unavailable")

    monkeypatch.setenv("TEST_USER_ID", "user-123")
    monkeypatch.setattr(analysis_api, "save_audio", fake_save_audio)
    monkeypatch.setattr(analysis_api, "save_items", fail_save_items)
    monkeypatch.setattr(
        analysis_api,
        "delete_audio",
        lambda audio_id: removed_ids.append(audio_id),
    )

    response = client.post(
        "/api/items/with-audio",
        data={"items": json.dumps({"items": [{"type": "task", "title": "Test", "description": ""}]})},
        files={"audio": ("recording.aac", b"audio", "audio/aac")},
    )

    assert response.status_code == 500
    assert removed_ids == ["orphan-candidate"]
