"""Registro de cuentas mediante Supabase Auth."""
import logging
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, EmailStr, Field
from supabase_auth.errors import AuthApiError
from backend.services.supabase_client import supabase

router = APIRouter(prefix="/api/auth", tags=["Autenticación"])
logger = logging.getLogger("uvicorn.error")

class RegisterRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    full_name: str = Field(min_length=2, max_length=100)

@router.post("/register", status_code=201)
def register(body: RegisterRequest):
    try:
        result = supabase.auth.sign_up({
            "email": str(body.email).strip().lower(),
            "password": body.password,
            "options": {"data": {"full_name": body.full_name.strip()}},
        })
        user = result.user
        if user is None:
            raise HTTPException(status_code=400, detail="No fue posible crear la cuenta. Verifica los datos.")
        if not result.session:
            return {"message": "Cuenta creada. Revisa tu correo para confirmar el registro.", "authenticated": False, "user_id": user.id}
        return {"message": "Cuenta creada e inició sesión correctamente.", "authenticated": True, "user_id": user.id, "access_token": result.session.access_token, "token_type": "bearer"}
    except HTTPException: raise
    except Exception as exc:
        message = str(exc).lower()
        if isinstance(exc, AuthApiError) and "email" in message and "invalid" in message:
            raise HTTPException(
                status_code=422,
                detail="Supabase rechazó el correo electrónico. Verifica que sea válido y que el proyecto permita registros con correo.",
            ) from exc
        if "already" in message or "registered" in message or "exists" in message or "duplicate" in message:
            raise HTTPException(status_code=409, detail="El correo electrónico ya está en uso.")
        logger.exception("Error en el registro de cuenta")
        raise HTTPException(status_code=400, detail="No fue posible registrar la cuenta. Verifica los datos e inténtalo nuevamente.")
