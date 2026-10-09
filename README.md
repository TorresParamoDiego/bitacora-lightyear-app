# Bitácora Lightyear

Aplicación Flutter con una API FastAPI para recibir y almacenar archivos de
audio como notas de voz. La implementación actual no transcribe el audio.

## Requisitos

- Python 3.10 o posterior para el backend.
- Flutter con una versión de Dart compatible con `^3.12.0` (según
  `frontend/pubspec.yaml`).

## Instalación y ejecución del backend

Desde la raíz del repositorio, crea un entorno virtual e instala las
dependencias fijadas en `backend/requirements.txt`:

```powershell
cd backend
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
```

Inicia la API desde el directorio `backend`:

```powershell
python -m uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

La documentación interactiva de FastAPI estará en
`http://127.0.0.1:8000/docs`. La API guarda los archivos recibidos en
`backend/uploads`, que se crea cuando se realiza la primera carga.

## Instalación y ejecución de Flutter

En otra terminal, instala las dependencias y ejecuta la aplicación:

```powershell
cd frontend
flutter pub get
flutter run
```

Flutter obtiene las URL del backend desde
`frontend/lib/core/config/api_config.dart`. Ajusta allí `baseUrl` a una
dirección alcanzable desde el dispositivo o emulador; para un teléfono físico,
el equipo que ejecuta la API y el teléfono deben poder comunicarse por la red.

## API y contrato Flutter–FastAPI

### `GET /health`

- **Solicitud:** no requiere cuerpo ni parámetros.
- **Respuesta:** HTTP 200 y un objeto JSON con `status: "ok"` y
  `app: "Bitácora Lightyear"`.

### `POST /voice/upload`

- **Solicitud:** `multipart/form-data` con el campo obligatorio `file` que
  contiene el archivo. Se permiten las extensiones `.wav`, `.mp3`, `.m4a`,
  `.ogg`, `.webm` y `.aac`; el archivo debe tener contenido.
- **Límite:** el código admite hasta `25 * 1024 * 1024` bytes (25 MiB).
- **Efecto:** el servidor genera un nombre de archivo y guarda el audio en
  `backend/uploads`.
- **Respuesta correcta:** HTTP 201 y un objeto JSON con `id`,
  `archivo_audio`, `duracion`, `fecha_inicio`, `formato`, `tamano_bytes` y
  `estado`. Actualmente `duracion` y `fecha_inicio` son nulos; `estado` vale
  `"recibido"`. No se calcula una transcripción.
- **Errores documentados:** HTTP 400 para un archivo vacío, HTTP 413 para
  superar el límite, HTTP 415 para una extensión no admitida y HTTP 422 si
  falta el campo requerido o FastAPI no puede validar la solicitud. Los
  errores HTTP de FastAPI se devuelven en el formato JSON habitual
  `{"detail": ...}`.

El cliente Flutter envía el archivo en el campo `file`, interpreta HTTP 201
como una respuesta `VoiceNoteResponse` y lee `id`, `archivo_audio`, `formato`,
`tamano_bytes` y `estado`. No necesita los dos campos opcionales para construir
su modelo actual. No hay en el backend una configuración de entorno cargada
por código; la URL que usa Flutter se configura en `ApiConfig`.

## Pruebas y comprobaciones

No se encontraron pruebas automatizadas para el backend. Puedes comprobarlo
manualmente mientras la API está en ejecución:

```powershell
curl.exe -i http://127.0.0.1:8000/health
curl.exe -i -F "file=@C:\ruta\al\audio.wav" http://127.0.0.1:8000/voice/upload
```

Para ejecutar las pruebas Flutter existentes:

```powershell
cd frontend
flutter test
```
