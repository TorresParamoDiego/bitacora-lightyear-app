
import logging
import os
from typing import Any

from fastapi import APIRouter, HTTPException
from services.item_storage_service import list_items

router = APIRouter(prefix="/api/items", tags=["Items"])
logger = logging.getLogger("uvicorn.error")


@router.get("/")
async def get_user_activities() -> dict[str, list[dict[str, Any]]]:
    test_user_id = os.getenv("TEST_USER_ID")

    if not test_user_id:
        raise HTTPException(
            status_code=500,
            detail="Falta configurar TEST_USER_ID",
        )

    try:
        items_data = list_items(user_id=test_user_id)
        return {"items": items_data}

    except Exception:
        logger.exception("Error al recuperar actividades de Supabase")
        raise HTTPException(
            status_code=500,
            detail="No fue posible recuperar las actividades",
        )
