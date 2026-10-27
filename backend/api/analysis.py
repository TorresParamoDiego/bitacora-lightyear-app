# backend/api/analysis.py
"""Router para el análisis automático de transcripciones y persistencia de elementos."""

import logging
from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from fastapi.concurrency import run_in_threadpool
from pydantic import ValidationError

from core.deps import get_current_user_id
from schemas.analysis import (
    AnalysisRequest,
    AnalysisResponse,
    SaveItemsRequest,
    SaveItemsResponse,
)
from services.analysis_service import analyze_transcription
from services.audio_service import delete_audio, save_audio
from services.item_storage_service import save_items

logger = logging.getLogger("uvicorn.error")

router = APIRouter(prefix="/api", tags=["US3 - Análisis y Extracción"])


@router.post(
    "/analysis",
    response_model=AnalysisResponse,
    status_code=status.HTTP_200_OK,
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
)
async def create_items(
    request: SaveItemsRequest,
    user_id: str = Depends(get_current_user_id),
) -> SaveItemsResponse:
    try:
        kwargs = {}
        if request.simulate_error:
            kwargs["simulate_error"] = True

        count, saved = await run_in_threadpool(
            save_items,
            request.items,
            user_id,
            request.recording_id,
            **kwargs,
        )
        return SaveItemsResponse(
            saved_count=count,
            items=saved,
            message=f"Se guardaron {count} elementos correctamente.",
        )
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("Error al guardar elementos: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No se pudieron guardar los elementos confirmados.",
        ) from exc


@router.post(
    "/items/with-audio",
    response_model=SaveItemsResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_items_with_audio(
    items: str = Form(...),
    audio: UploadFile = File(...),
    user_id: str = Depends(get_current_user_id),
) -> SaveItemsResponse:
    try:
        try:
            request = SaveItemsRequest.model_validate_json(items)
        except ValidationError as exc:
            raise HTTPException(status_code=422, detail=exc.errors()) from exc

        if not request.items:
            raise HTTPException(
                status_code=422,
                detail="Se requiere al menos una actividad para guardar el audio.",
            )

        audio_data = await save_audio(audio, user_id)
        try:
            kwargs = {}
            if request.simulate_error:
                kwargs["simulate_error"] = True

            count, saved = await run_in_threadpool(
                save_items,
                request.items,
                user_id,
                audio_data["id"],
                **kwargs,
            )
        except Exception:
            try:
                await run_in_threadpool(delete_audio, audio_data["id"])
            except Exception:
                logger.exception("No se pudo limpiar el audio tras fallar el guardado")
            raise

        return SaveItemsResponse(
            saved_count=count,
            items=saved,
            message=f"Se guardaron {count} elementos correctamente.",
        )
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("Error al guardar actividades y audio: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No se pudieron guardar el audio y las actividades.",
        ) from exc