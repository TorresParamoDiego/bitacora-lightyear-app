"""Dependencias globales para la aplicación FastAPI."""

import logging
import os
from fastapi import Header, HTTPException, status
from services.supabase_client import supabase

logger = logging.getLogger("uvicorn.error")

TEST_USER_ID = os.getenv("TEST_USER_ID", "00000000-0000-0000-0000-000000000002")


async def get_current_user_id(
    authorization: str | None = Header(default=None),
) -> str:
    """Extrae el ID de usuario autenticado de public.users resolviendo auth_user_id."""
    # 1. Modo de pruebas/desarrollo sin token JWT
    if not authorization or not authorization.startswith("Bearer "):
        return TEST_USER_ID

    token = authorization.split(" ")[1]

    try:
        # 2. Validar token con Supabase Auth
        user_response = supabase.auth.get_user(token)
        if not user_response or not user_response.user:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token de autenticación inválido o expirado.",
            )

        auth_user_id = user_response.user.id

        # 3. Mapear auth_user_id (auth.users) -> id (public.users)
        response = (
            supabase.table("users")
            .select("id")
            .eq("auth_user_id", auth_user_id)
            .limit(1)
            .execute()
        )

        if response.data and len(response.data) > 0:
            return response.data[0]["id"]

        # Si el usuario existe en Auth pero aún no en public.users, usar auth_user_id como fallback
        logger.warning(
            "Usuario con auth_user_id %s no encontrado en public.users. Usando fallback.",
            auth_user_id,
        )
        return auth_user_id

    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("Error al validar token de autenticación: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Error al procesar las credenciales de autenticación.",
        ) from exc