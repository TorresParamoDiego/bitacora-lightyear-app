# Bitácora Lightyear

Bitácora Lightyear es una aplicación móvil para registrar notas de voz y convertirlas en texto automáticamente. El flujo actual del proyecto incluye grabación de audio, envío al backend, almacenamiento del archivo y transcripción con IA en español.

## Funcionalidades actuales

- Grabación de audio desde Flutter con control de micrófono.
- Pausa, reanudación y cancelación durante la grabación.
- Límite de grabación de 3 minutos.
- Envío del audio al backend mediante `multipart/form-data`.
- Almacenamiento del audio en el bucket `audios` de Supabase al guardar las actividades.
- Transcripción automática a texto en español utilizando Groq Whisper.
- Manejo de casos sin voz detectada o con errores de transcripción.
- API de salud para comprobar que el backend está activo.

## Arquitectura

- `frontend/`: aplicación Flutter.
- `backend/`: API FastAPI.
- Supabase Storage (`audios`): audios asociados a las actividades guardadas.
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
  "id": "7a58d7c0-a50d-44d8-8fe5-0ab8c72bd8a1",
  "archivo_audio": "7a58d7c0-a50d-44d8-8fe5-0ab8c72bd8a1",
  "duracion": null,
  "fecha_inicio": null,
  "formato": "aac",
  "tamano_bytes": 245367,
  "estado": "recibido"
}
```

Esta ruta alternativa conserva el audio inmediatamente en el bucket `audios`; `id` y `archivo_audio` son la clave del objeto. El flujo normal de la app espera a que el usuario confirme las actividades y usa `POST /api/items/with-audio` para guardar el audio y los elementos juntos.

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

### `POST /api/analysis`

Analiza una transcripción en español para identificar tareas, recordatorios y eventos, aplicando las 15 reglas estandarizadas de extracción.

Ejemplo:

```powershell
curl.exe -i -X POST -H "Content-Type: application/json" -d "{\"text\": \"Entregar el proyecto el 17 de octubre, es urgente. Tener presente el cumpleaños de Ana el 20 de noviembre.\", \"reference_date\": \"2026-10-13\"}" http://127.0.0.1:8000/api/analysis
```

Respuesta estándar (HTTP 200):

```json
{
  "items": [
    {
      "type": "task",
      "title": "Entregar el proyecto",
      "description": "Entregar el proyecto el 17 de octubre",
      "priority": "high",
      "date": "2026-10-17",
      "time": null,
      "status": "pending"
    },
    {
      "type": "reminder",
      "title": "Cumpleaños de Ana",
      "description": "Tener presente el cumpleaños de Ana el 20 de noviembre",
      "priority": null,
      "date": "2026-11-20",
      "time": null,
      "status": "pending"
    }
  ]
}
```

### `POST /api/items/with-audio`

Guarda las actividades y el audio confirmados en una sola operación multipart. El campo `items` debe contener el JSON `{"items":[...]}` y `audio` el archivo `.aac`. El backend carga primero el audio al bucket `audios`, usa la clave resultante como `recording_id` en cada fila de `items` y elimina el objeto si falla la inserción.

### `POST /api/items` y `GET /api/items`

Permite guardar y recuperar los elementos confirmados por el usuario.

## Flujo recomendado

1. El usuario graba una nota de voz en la app Flutter; el archivo se conserva localmente mientras revisa los resultados.
2. La app solicita la transcripción a `POST /api/transcriptions`.
3. El backend transcribe con Groq Whisper.
4. La app envía el texto a `POST /api/analysis` (o pulsa "Analizar tareas y eventos").
5. Se abre la pantalla de revisión visual con bloques diferenciados (Tareas, Recordatorios, Eventos).
6. El usuario edita, elimina o agrega elementos según requiera.
7. El usuario confirma las actividades; `POST /api/items/with-audio` sube el audio al bucket `audios` y guarda esa misma clave en `items.recording_id`.

## Pruebas automatizadas

### Backend (pytest):

```powershell
cd backend
.\.venv\Scripts\python.exe -m pytest tests\test_analysis.py -v
```

### Frontend (flutter test):

```powershell
cd frontend
flutter test
```
