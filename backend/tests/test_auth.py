import warnings

from supabase_auth.errors import AuthApiError
from fastapi.testclient import TestClient

from api import auth as auth_api
from main import app

client = TestClient(app)


def test_auth_register_route_is_registered_once():
    with warnings.catch_warnings(record=True) as caught_warnings:
        warnings.simplefilter("always")
        schema = app.openapi()

    assert "/api/auth/register" in schema["paths"]
    assert not any(
        "Duplicate Operation ID register_api_auth_register_post" in str(warning.message)
        for warning in caught_warnings
    )


def test_register_maps_supabase_invalid_email_to_validation_error(monkeypatch):
    def reject_email(_):
        raise AuthApiError(
            'Email address "123@gmail.com" is invalid',
            status=400,
            code="email_address_invalid",
        )

    monkeypatch.setattr(auth_api.supabase.auth, "sign_up", reject_email)

    response = client.post(
        "/api/auth/register",
        json={
            "email": "123@gmail.com",
            "password": "password123",
            "full_name": "Usuario de prueba",
        },
    )

    assert response.status_code == 422
    assert "Supabase rechazó el correo electrónico" in response.json()["detail"]
