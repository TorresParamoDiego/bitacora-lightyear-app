# Bitácora Lightyear

Bitácora Lightyear es una aplicación móvil para registrar notas de voz y convertirlas en texto automáticamente. El flujo actual del proyecto incluye grabación de audio, envío al backend, almacenamiento del archivo y transcripción con IA en español.

## Funcionalidades actuales

- Grabación de audio desde Flutter con control de micrófono.
- Pausa, reanudación y cancelación durante la grabación.
- Límite de grabación de 3 minutos.
- Envío del audio al backend mediante `multipart/form-data`.
- Almacenamiento del archivo en `backend/uploads`.
- Transcripción automática a texto en español utilizando Groq Whisper.
- Manejo de casos sin voz detectada o con errores de transcripción.
- API de salud para comprobar que el backend está activo.

## Arquitectura

- `frontend/`: aplicación Flutter.
- `backend/`: API FastAPI.
- `backend/uploads/`: archivos de audio guardados por la app.
- `backend/api/`: rutas HTTP del backend.
- `backend/services/`: lógica de almacenamiento y transcripción.

## Requisitos

- Python 3.10 o superior.
- Flutter SDK con Dart compatible con `^3.12.0`.
- `ffmpeg` instalado y disponible en el `PATH` del sistema.
- Variable de entorno `GROQ_API_KEY` configurada para la transcripción.

## Instalación y ejecución del backend

Desde la raíz del proyecto:

```powershell
cd backend
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
```

Configura la clave de Groq antes de arrancar la API:

```powershell
$env:GROQ_API_KEY="tu_clave_aqui"
```

Inicia el servidor:

```powershell
python -m uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

La documentación interactiva de FastAPI estará disponible en:

- `http://127.0.0.1:8000/docs`

## Instalación y ejecución de Flutter

En otra terminal:

```powershell
cd frontend
flutter pub get
flutter run
```

La URL del backend se define en `frontend/lib/core/config/api_config.dart`.
Ajusta `baseUrl` según el entorno:

- Emulador Android: `http://10.0.2.2:8000`
- Dispositivo físico: la IP del equipo donde corre el backend

## API y contrato Flutter–FastAPI

### `GET /health`

Respuesta esperada:

```json
{
  "status": "ok",
  "app": "Bitácora Lightyear"
}
```

### `POST /voice/upload`

Envía un archivo de audio en `multipart/form-data` con el campo `file`.

Ejemplo:

```powershell
curl.exe -i -F "file=@C:\ruta\al\audio.aac" http://127.0.0.1:8000/voice/upload
```

Respuesta exitosa (HTTP 201):

```json
{
  "id": "uuid",
  "archivo_audio": "audio_123.aac",
  "duracion": null,
  "fecha_inicio": null,
  "formato": "aac",
  "tamano_bytes": 245367,
  "estado": "recibido"
}
```

El audio se guarda en `backend/uploads` y el cliente no necesita construir la transcripción desde esta respuesta.

### `POST /api/transcriptions`

Recibe un audio en `multipart/form-data` con el campo `audio` y devuelve el texto transcrito.

Ejemplo:

```powershell
curl.exe -i -F "audio=@C:\ruta\al\audio.aac" http://127.0.0.1:8000/api/transcriptions
```

Respuesta exitosa (HTTP 200):

```json
{
  "estado": "completado",
  "transcripcion": "Hoy revisé el avance del proyecto y dejamos pendientes dos tareas importantes.",
  "mensaje": "Transcripción realizada correctamente.",
  "idioma": "es"
}
```

Si no se detecta voz clara, la respuesta puede ser:

```json
{
  "estado": "sin_voz",
  "transcripcion": "",
  "mensaje": "No se detectó voz inteligible. Graba una nota con voz clara e inténtalo de nuevo.",
  "idioma": "es"
}
```

## Flujo recomendado

1. El usuario graba una nota de voz en la app Flutter.
2. La app envía el archivo a `POST /voice/upload`.
3. El backend guarda el audio en `backend/uploads`.
4. La app solicita la transcripción a `POST /api/transcriptions`.
5. El backend convierte el audio a WAV y lo transcribe con Groq Whisper.
6. La interfaz muestra el texto resultante y su estado.

## Comprobaciones rápidas

Comprueba que el backend responde:

```powershell
curl.exe -i http://127.0.0.1:8000/health
```

Y para ejecutar la suite Flutter disponible:

```powershell
cd frontend
flutter test
```

## Nota importante

La transcripción no es una característica antigua ni opcional: forma parte del flujo actual de la aplicación. El README anterior describía un estado del proyecto que ya no refleja la implementación actual.

