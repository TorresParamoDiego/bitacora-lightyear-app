"""Router para el análisis automático de transcripciones y persistencia de elementos."""

import logging
from fastapi import APIRouter, HTTPException, status
from fastapi.concurrency import run_in_threadpool

from schemas.analysis import (
    AnalysisRequest,
    AnalysisResponse,
    SaveItemsRequest,
    SaveItemsResponse,
)
from services.analysis_service import analyze_transcription
from services.item_storage_service import list_items, save_items

logger = logging.getLogger("uvicorn.error")

router = APIRouter(prefix="/api", tags=["US3 - Análisis y Extracción"])


@router.post(
    "/analysis",
    response_model=AnalysisResponse,
    status_code=status.HTTP_200_OK,
    summary="Analizar transcripción",
    description="Analiza una transcripción en español para identificar tareas, eventos y recordatorios con fechas y prioridades.",
)
async def analyze_text(request: AnalysisRequest) -> AnalysisResponse:
    try:
        result = await run_in_threadpool(
            analyze_transcription,
            request.text,
            request.reference_date,
        )
        return AnalysisResponse(**result)
    except Exception as exc:
        logger.exception("Error al analizar transcripción: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error interno al procesar el análisis de la transcripción.",
        ) from exc


@router.post(
    "/items",
    response_model=SaveItemsResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Guardar elementos confirmados",
    description="Persiste los elementos (tareas, eventos, recordatorios) confirmados o editados por el usuario.",
)
async def create_items(request: SaveItemsRequest) -> SaveItemsResponse:
    try:
        count, saved = await run_in_threadpool(save_items, request.items)
        return SaveItemsResponse(
            saved_count=count,
            items=request.items,
            message=f"Se guardaron {count} elementos correctamente.",
        )
    except Exception as exc:
        logger.exception("Error al guardar elementos: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No se pudieron guardar los elementos confirmados.",
        ) from exc


@router.get(
    "/items",
    summary="Listar elementos guardados",
    description="Recupera la lista de elementos guardados previamente.",
)
async def get_items():
    try:
        items = await run_in_threadpool(list_items)
        return {"items": items, "total": len(items)}
    except Exception as exc:
        logger.exception("Error al obtener elementos: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No se pudieron recuperar los elementos.",
        ) from exc
