# Documentación integral de Bitácora Lightyear

## 1. Descripción general

Bitácora Lightyear es una aplicación multiplataforma basada en Flutter y FastAPI que permite:

- grabar notas de voz;
- transcribir audio en español;
- analizar el texto para extraer tareas, recordatorios y eventos;
- revisar y editar los elementos extraídos;
- guardar audio y actividades en Supabase;
- consultar el historial de grabaciones y actividades;
- consultar, completar, cancelar o eliminar actividades;
- programar recordatorios locales y notificaciones push mediante Firebase;
- configurar los avisos de cada actividad o usar anticipaciones predeterminadas por tipo;
- sincronizar las programaciones personalizadas con Supabase y recibirlas en Android o Web.

El sistema tiene dos componentes principales:

- `frontend/`: aplicación Flutter para Android y Web.
- `backend/`: API REST desarrollada con FastAPI.

Los servicios externos utilizados son Supabase Auth, Supabase Database, Supabase Storage, Groq Whisper y Firebase Cloud Messaging.

---

## 2. Arquitectura

```text
Usuario
  |
  | Flutter UI
  v
Frontend Flutter
  |-- Supabase Auth
  |-- Supabase Database mediante backend
  |-- HTTP/JSON o multipart/form-data
  |-- Grabación local con package record
  |-- Firebase Messaging / notificaciones locales
  v
Backend FastAPI
  |-- Validación Pydantic
  |-- Validación de token Supabase
  |-- VAD y conversión AAC -> WAV
  |-- Groq Whisper
  |-- Extracción por Groq o motor de reglas
  v
Supabase
  |-- users
  |-- items
  |-- recordings
  |-- user_fcm_tokens
  |-- user_notification_type_defaults
  |-- item_notification_schedules
  |-- bucket audios
```

### Flujo funcional principal

1. El usuario inicia sesión o crea una cuenta.
2. Se solicita permiso de micrófono.
3. Flutter graba un archivo AAC por un máximo de tres minutos.
4. La app envía el archivo AAC a `POST /api/transcriptions`.
5. El backend convierte el AAC a WAV, aplica RMS y WebRTC VAD y solicita la transcripción a Groq Whisper.
6. El texto puede ser editado por el usuario.
7. El texto se envía a `POST /api/analysis`.
8. Groq intenta extraer elementos; si no existe API o falla, se utiliza un analizador local basado en expresiones regulares y reglas.
9. El usuario revisa, filtra, agrega, elimina o modifica tareas, recordatorios y eventos.
10. Al confirmar, `POST /api/items/with-audio` realiza dos operaciones: sube el AAC al bucket `audios` y crea las filas correspondientes en `items`.
11. Las actividades pueden consultarse, editarse, completarse y eliminarse desde la pestaña Actividades.
12. El backend crea disparadores de notificación basados en fecha y hora.

---

## 3. Estructura del proyecto

```text
bitacora_lightyear/
|-- README.md
|-- documentacion.md
|-- backend/
|   |-- main.py
|   |-- requirements.txt
|   |-- api/
|   |-- core/
|   |-- data/
|   |-- schemas/
|   |-- services/
|   `-- tests/
`-- frontend/
    |-- pubspec.yaml
    |-- pubspec.lock
    |-- lib/
    |-- test/
    |-- assets/
    |-- android/
    `-- web/
```

---

## 4. Backend

### 4.1 Punto de entrada

El archivo `backend/main.py` crea la aplicación FastAPI, habilita CORS con origen abierto, carga variables de entorno y registra los routers.

La aplicación expone:

- título: `Bitácora Lightyear API`;
- versión: `0.1.0`;
- documentación Swagger: `/docs`;
- documentación ReDoc: `/redoc`;
- health check: `/health`;
- comprobación de Supabase: `/health/db`.

### 4.2 Configuración y dependencias

`backend/requirements.txt` incluye FastAPI, Uvicorn, Pydantic, python-multipart, Supabase, Groq, requests, WebRTC VAD, audioop-lts y utilidades de entorno.

Variables de entorno del backend:

| Variable | Uso |
|---|---|
| `SUPABASE_URL` | URL del proyecto Supabase |
| `SUPABASE_SECRET_KEY` | Clave de servidor para las operaciones del backend |
| `GROQ_API_KEY` | Transcripción y análisis semántico con Groq |
| `TEST_USER_ID` | Usuario usado cuando la petición no contiene Bearer token |
| `WHISPER_MODEL`, `WHISPER_DEVICE`, `WHISPER_COMPUTE_TYPE` | Variables reservadas por una implementación Whisper alternativa conservada en el archivo de transcripción |

El cliente de Supabase se crea en `backend/services/supabase_client.py`. Si faltan `SUPABASE_URL` o `SUPABASE_SECRET_KEY`, el módulo falla explícitamente.

FFmpeg debe estar instalado y disponible en el `PATH` del servidor para convertir AAC a WAV.

### 4.3 Autenticación y usuario actual

La dependencia `get_current_user_id` en `backend/core/deps.py`:

1. si no existe Bearer token, devuelve `TEST_USER_ID`;
2. si existe, valida el token con `supabase.auth.get_user(token)`;
3. busca el identificador público en `public.users` por `auth_user_id`;
4. usa el ID de Auth como fallback si no encuentra el usuario público;
5. devuelve HTTP 401 ante credenciales inválidas.

Este comportamiento permite pruebas sin token, pero no debe considerarse una autorización anónima segura en producción.

#### Registro

`POST /api/auth/register` recibe correo, contraseña y nombre completo. Utiliza Supabase Auth.

Validaciones principales:

- correo válido;
- contraseña de 8 a 128 caracteres;
- nombre de 2 a 100 caracteres;
- respuesta 409 si el correo ya existe;
- respuesta 422 si Supabase rechaza el correo;
- respuesta 201 al crear la cuenta.

El inicio y cierre de sesión se realizan directamente desde Flutter con Supabase, no mediante un endpoint FastAPI.

### 4.4 Esquemas Pydantic

#### Elemento extraído

Los elementos usan `backend/schemas/analysis.py` con estos campos:

| Campo | Tipo | Valores |
|---|---|---|
| `type` | string | `task`, `reminder`, `event` |
| `title` | string | título breve |
| `description` | string | detalle |
| `priority` | string o null | `high`, `medium`, `low` |
| `date` | string o null | `YYYY-MM-DD` |
| `time` | string o null | `HH:mm` |
| `status` | string | `pending`, `completed`, `cancelled` |

`backend/schemas/transcription.py` define estados `completado` o `sin_voz`.

`backend/schemas/voice.py` define la respuesta de una nota de voz almacenada.

### 4.5 API de audio y transcripción

#### `GET /health`

Comprueba que el proceso FastAPI responde.

Respuesta:

```json
{
  "status": "ok",
  "app": "Bitácora Lightyear"
}
```

#### `GET /health/db`

Ejecuta una consulta limitada sobre la tabla `items` y devuelve si Supabase responde.

#### `POST /voice/upload`

Recibe el campo multipart `file`.

Restricciones:

- solo archivo `.aac`;
- máximo 25 MB;
- el archivo no puede estar vacío;
- genera un UUID;
- almacena el objeto bajo ese ID en el bucket `audios`;
- crea un registro en `recordings`;
- elimina el objeto si falla la inserción en la base de datos.

También admite `GET /voice/recordings`, que obtiene las grabaciones del usuario autenticado ordenadas por fecha descendente.

#### `POST /api/transcriptions`

Recibe el campo multipart `audio`.

Restricciones:

- solo `.aac`;
- máximo 25 MB;
- conversión temporal con FFmpeg a WAV mono 16 kHz;
- detección de volumen mínimo;
- detección WebRTC VAD para voz sostenida;
- modelo Groq `whisper-large-v3-turbo`;
- idioma solicitado: español;
- temperatura 0;

Puede devolver:

- `completado`, con transcripción;
- `sin_voz`, si no hay voz inteligible;
- 400 para formato o archivo inválido;
- 413 si supera 25 MB;
- 503 si falla el servicio externo.

El audio convertido se elimina de temporales al finalizar.

### 4.6 API de análisis

#### `POST /api/analysis`

Entrada:

```json
{
  "text": "Entregar el informe el 17 de octubre, es urgente.",
  "reference_date": "2026-10-13"
}
```

Salida:

```json
{
  "items": [
    {
      "type": "task",
      "title": "Entregar el informe",
      "description": "Entregar el informe el 17 de octubre",
      "priority": "high",
      "date": "2026-10-17",
      "time": null,
      "status": "pending"
    }
  ]
}
```

Si no hay fecha de referencia, el analizador usa la fecha actual del servidor.

El motor principal usa Groq con un prompt que exige las reglas de extracción. Si no existe `GROQ_API_KEY`, si la inicialización falla o si no devuelve elementos válidos, recurre al motor determinista de `backend/services/analysis_service.py`.

El motor determinista incluye:

- división de frases y cláusulas;
- detección de verbos de tarea;
- detección de recordatorios;
- detección de eventos;
- extracción de fecha relativa;
- extracción de hora;
- extracción de prioridad;
- título y descripción;
- normalización de estado;
- deduplicación.

Las reglas normalizan expresiones como hoy, mañana, días de semana, meses, horas y expresiones de prioridad. Los eventos pasados quedan `completed` y los futuros o actuales quedan `pending`.

Para tareas recurrentes admite cláusulas como «cada dos días», «cada 3
horas». El analizador convierte los números escritos en español, evita
duplicados y genera hasta 16
ocurrencias; si el texto indica más ocurrencias o no define un final, agrega
una última actividad marcada como recurrente para revisar manualmente.

### 4.7 API de actividades

#### `POST /api/items`

Guarda una o varias actividades confirmadas. Genera UUID para cada elemento y asigna el usuario autenticado. Puede guardar un `recording_id`.

El cuerpo admite `custom_offsets_by_index`, un mapa entre el índice de cada
elemento y una lista de minutos de anticipación. Los valores admitidos incluyen
`0` (en el vencimiento), minutos, horas o días expresados como minutos.
Tras crear las filas, el backend sincroniza
`item_notification_schedules` usando los defaults del usuario por tipo
(`task`, `reminder` y `event`) o los offsets personalizados del elemento.

#### `POST /api/items/with-audio`

Es el endpoint principal usado por la revisión final. Recibe:

- `items`: JSON serializado que valida `SaveItemsRequest`;
- `audio`: archivo AAC;

Proceso:

1. valida que exista al menos una actividad;
2. guarda el audio en `audios`;
3. crea el registro correspondiente en `recordings`;
4. actualiza su transcripción si fue enviada;
5. guarda las actividades asociadas a su ID;
6. elimina el audio y el registro si falla la persistencia de los elementos.

Si se activa `simulate_error`, el servicio de persistencia fuerza deliberadamente un fallo para probar recuperación y compensación.

#### `GET /api/items`

Acepta `recording_id` opcional y devuelve:

```json
{
  "items": [],
  "total": 0
}
```

Los elementos se ordenan por `created_at` descendente.

#### `PUT /api/items/{item_id}`

Actualiza título, descripción, tipo, prioridad, fecha, hora, estado y banderas de notificación.

También admite `notification_offsets`: al actualizar una actividad se reemplaza
su programación personalizada y se recalculan los disparos. Las actividades
completadas o canceladas, o las que pierden su fecha, eliminan las filas
pendientes de `item_notification_schedules`.

Rechaza:

- listas de cambios vacías;
- títulos vacíos;
- estados distintos de `pending`, `completed` o `cancelled`;
- prioridades distintas de `high`, `medium`, `low` o null.

#### `PATCH /api/items/{item_id}/status`

Permite cambiar el estado únicamente a `pending` o `completed`.

#### `DELETE /api/items/{item_id}`

Elimina una actividad solo si pertenece al usuario autenticado.

### 4.8 Persistencia

`backend/services/item_storage_service.py` guarda primero en Supabase. Después crea una copia redundante en `backend/data/saved_items.json`.

Al consultar, intenta Supabase y recurre al archivo local ante una falla. Este respaldo local es secundario y no sustituye las políticas de Supabase.

Tablas inferidas por el código:

- `users`: usuario público con `id` y `auth_user_id`;
- `items`: elementos confirmados, usuario, grabación y banderas de notificaciones;
- `recordings`: grabaciones, usuario, ruta de Storage, nombre original, transcripción y estado;
- `user_fcm_tokens`: tokens FCM asociados al usuario;
- `user_notification_type_defaults`: anticipaciones por usuario y tipo de actividad;
- `item_notification_schedules`: avisos personalizados de cada actividad, su minuto de disparo y estado `sent`.

Bucket Storage esperado:

- `audios`.

Columnas de `items` usadas por el frontend y backend:

- `id`;
- `user_id`;
- `recording_id`;
- `type`;
- `title`;
- `description`;
- `priority`;
- `date`;
- `time`;
- `status`;
- `source_excerpt`;
- `notification_1d_sent`;
- `notification_30m_sent`;
- `notification_due_sent`;
- `created_at`;
- `updated_at`.

### 4.9 Pruebas backend

Las pruebas se encuentran en `backend/tests/`:

- `test_analysis.py`: estructura del análisis, las 15 reglas, fechas relativas, estados y persistencia;
- `test_auth.py`: registro de rutas y conversión de errores de Supabase;
- `test_item_persistence.py`: persistencia de usuario y grabación, audio asociado y rollback ante errores.

Ejecutar:

```powershell
cd backend
python -m pytest tests -v
```

---

## 5. Frontend Flutter

### 5.1 Dependencias principales

El SDK configurado por `frontend/pubspec.yaml` admite Dart `^3.12.0`.

Dependencias relevantes:

| Paquete | Uso |
|---|---|
| `record` | grabación de audio |
| `http` | llamadas HTTP |
| `path_provider` | almacenamiento temporal |
| `path` | construcción de rutas |
| `just_audio` | reproducción |
| `vibration` | vibración |
| `flutter_local_notifications` | recordatorios locales |
| `timezone` | zonas horarias |
| `firebase_core` / `firebase_messaging` | push Android |
| `supabase_flutter` | Auth y sesión |
| `flutter_dotenv` | configuración `.env` |
| `web` | integración web |

### 5.2 Configuración

`frontend/.env` debe contener al menos:

```dotenv
SUPABASE_URL=...
SUPABASE_PUBLISHABLE_KEY=...
```

No se deben almacenar claves secretas de Supabase ni claves privadas de Groq en el frontend.

`frontend/lib/core/config/api_config.dart` contiene:

- URL Render predeterminada;
- URL local configurable;
- endpoints de transcripción, voz, salud, análisis y elementos.

La URL activa predeterminada es `https://bitacora-lightyear-app.onrender.com`.

Para desarrollo local:

- Web o Windows: `http://127.0.0.1:8000`;
- emulador Android: `http://10.0.2.2:8000`;
- dispositivo físico: IP local del equipo servidor.

### 5.3 Inicio de la aplicación

`frontend/lib/main.dart` realiza:

1. inicialización de bindings;
2. carga de `.env`;
3. inicialización de Supabase;
4. inicialización de Firebase solo en Android;
5. inicialización de notificaciones locales;
6. escucha de cambios de autenticación;
7. registro de token FCM;
8. sincronización de recordatorios;
9. selección entre `LoginScreen` y `HomeScreen`.

Si falla la carga de configuración, muestra `StartupErrorApp`.

### 5.4 Modelos

#### `ActivityItem`

Representa una actividad obtenida de Supabase:

- `id`;
- `type`;
- `title`;
- `description`;
- `priority`;
- `itemDate`;
- `itemTime`;
- `status`;
- `sourceExcerpt`.

Incluye creación desde JSON y copia de objetos.

#### `ExtractedItem`

Representa el elemento revisable generado por el backend:

- tipos normalizados;
- prioridades normalizadas;
- estado normalizado;
- fecha y hora opcionales;
- serialización a JSON;
- etiquetas legibles en español.

#### `RecordingItem`

Representa una grabación del historial:

- `id`;
- `originalFilename`;
- `transcript`;
- `createdAt`;
- `durationSeconds`.

#### `TranscriptionResult`

Representa la respuesta del endpoint de transcripción:

- estado;
- texto;
- mensaje;
- idioma.

### 5.5 Servicios

#### Grabación

`audio_recorder_service.dart`:

- verifica permisos;
- graba AAC-LC en Android;
- usa AAC y cambia a Opus si el navegador no admite AAC;
- permite iniciar, pausar, reanudar, detener y cancelar;
- crea archivos temporales con timestamp.

La pantalla rechaza grabaciones menores de dos segundos.

#### Almacenamiento temporal

Los helpers `audio_storage_io.dart` y `audio_storage_stub.dart` mantienen compatibilidad con plataformas móviles y Web.

#### Subida multipart

Los helpers `audio_upload_io.dart` y `audio_upload_stub.dart` crean el archivo multipart de forma compatible con Dart IO y Web.

#### Transcripción

`transcription_api_service.dart` envía el AAC con Bearer token y timeout de tres minutos.

#### Análisis

`analysis_api_service.dart`:

- analiza texto con timeout de 45 segundos;
- guarda elementos con o sin audio;
- puede enviar transcripción;
- puede activar `simulate_error`;
- obtiene elementos guardados.

#### Actividades

`activities_api_service.dart`:

- obtiene grabaciones;
- obtiene actividades, opcionalmente por grabación;
- crea actividades individuales;
- actualiza elementos;
- cambia estado;
- elimina elementos;
- sincroniza recordatorios locales.

#### Autenticación

`auth_service.dart` usa Supabase Auth para inicio de sesión, registro y cierre de sesión. También registra y elimina tokens FCM con una RPC `register_fcm_token` y la tabla `user_fcm_tokens`.

#### Recordatorios

`reminder_schedule.dart` calcula:

- aviso un día antes;
- aviso treinta minutos antes;
- aviso a la hora exacta;
- hora predeterminada 09:00 si la actividad solo tiene fecha;
- banderas enviadas/no enviadas.

Las actividades completadas o canceladas cancelan sus recordatorios.

#### Preferencias y programación de avisos

`notification_preferences.dart` define:

- unidades de minutos, horas y días;
- etiquetas legibles como «30 minutos antes» o «1 día antes»;
- defaults por tipo de actividad;
- resolución de una hora programada;
- configuración propia opcional para cada actividad.

Los defaults iniciales son:

- tareas: 1 día, 30 minutos y al momento;
- recordatorios: 30 minutos y al momento;
- eventos: 1 día, 1 hora y al momento.

`notification_planner.dart` convierte esos offsets en instantes de disparo
respecto a la fecha y hora límite. Si la actividad solo tiene fecha, usa 09:00.
Las actividades cerradas no producen disparos.

`notification_schedule_service.dart` guarda y carga esas preferencias en
Supabase:

- `user_notification_type_defaults` contiene el esquema predeterminado por tipo;
- `item_notification_schedules` contiene los offsets personalizados de cada
  actividad y conserva si el aviso ya fue enviado;
- al cambiar fecha, hora, tipo, estado o offsets se reemplaza la programación;
- al eliminar una actividad se eliminan sus filas de programación.

El backend aplica la misma lógica en
`item_storage_service.sync_item_notification_schedules()`, lo que permite
mantener los schedules al crear, actualizar o eliminar elementos.

`reminder_notification_service.dart` controla:

- Firebase Messaging Android;
- notificaciones locales;
- permisos;
- apertura del detalle desde notificaciones;
- temporizadores periódicos;
- sincronización Web cada cinco minutos;
- alertas dentro de la aplicación.

### 5.6 Pantallas

#### Inicio de sesión

`login_screen.dart` valida correo y contraseña y usa `AuthService.signIn`.

#### Registro

`register_screen.dart` solicita nombre completo, correo y contraseña. Si Supabase inicia sesión automáticamente, abre `HomeScreen`; si requiere confirmación, vuelve al login.

#### Grabadora

`voice_recorder_screen.dart` contiene los estados:

- `idle`;
- `recording`;
- `success`.

Permite:

- iniciar, pausar y reanudar;
- cancelar;
- detener manualmente;
- detener automáticamente a los tres minutos;
- reproducir y posicionar el audio;
- abrir el panel de transcripción.

#### Panel de transcripción

`transcription_panel.dart`:

- transcribe automáticamente al montar;
- muestra carga y errores;
- permite reintentar;
- permite editar el texto;
- permite ejecutar el análisis.

#### Revisión de análisis

`analysis_review_screen.dart` permite:

- revisar elementos extraídos;
- filtrar por tarea, recordatorio y evento;
- agregar elementos;
- editar elementos;
- eliminar elementos;
- simular un fallo de persistencia;
- confirmar el guardado.

Al guardar usa la grabación y la transcripción para asociarlas al registro de `recordings` y a los elementos.

#### Actividades

`activities_screen.dart` ofrece:

- listado de actividades;
- filtros;
- búsqueda;
- creación manual;
- edición;
- eliminación;
- cambio de estado;
- representación de elementos vencidos.

#### Detalle de actividad

`activity_detail_screen.dart` muestra la actividad completa, permite cambiar estado, editar y eliminar.

#### Historial de transcripciones

`transcriptions_screen.dart` muestra grabaciones almacenadas y su transcripción.

#### Detalle de transcripción

`transcription_detail_screen.dart` muestra una grabación individual y permite obtener sus actividades asociadas.

#### Perfil

`user_profile_screen.dart` muestra correo e ID y permite cerrar sesión.

También permite configurar los avisos predeterminados de tareas,
recordatorios y eventos. Cada tipo puede usar minutos, horas o días como
anticipación y admite múltiples avisos.

#### Navegación

`home_screen.dart` usa `IndexedStack` y tres pestañas:

- Grabar;
- Actividades;
- Historial.

### 5.7 Widgets compartidos

- `widgets/transcription_panel.dart`: integración de transcripción y análisis;
- `widgets/slide_controls.dart`: controles visuales de grabación;
- `widgets/activity_edit_dialog.dart`: formulario reutilizable de actividad con
  edición de fecha, hora, estado, prioridad y avisos propios mediante minutos,
  horas o días.

### 5.8 Android

`frontend/android/app/src/main/AndroidManifest.xml` incluye permisos de:

- grabación de audio;
- vibración;
- Internet;
- arranque;
- notificaciones;
- alarmas exactas.

Permite tráfico claro porque el backend local puede usar HTTP.

`frontend/android/app/build.gradle.kts` usa:

- plugin Google Services;
- Java 17;
- core library desugaring;
- Firebase BoM;
- Firebase Analytics.

`google-services.json` configura Firebase Android.

### 5.9 Web

`frontend/web/` contiene el manifiesto y los recursos PWA.

En Web:

- no se inicia Firebase;
- se usan notificaciones del navegador;
- la grabación usa blobs;
- los recordatorios se mantienen mediante temporizadores locales.

### 5.10 Pruebas frontend

Archivos en `frontend/test/`:

- `activity_item_test.dart`;
- `analysis_api_service_test.dart`;
- `analysis_review_screen_test.dart`;
- `extracted_item_test.dart`;
- `reminder_schedule_test.dart`.

Ejecutar:

```powershell
cd frontend
flutter test
```

---

## 6. Ejecución en desarrollo

### 6.1 Backend

Windows PowerShell:

```powershell
cd backend
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
```

Configurar variables:

```powershell
$env:SUPABASE_URL="https://..."
$env:SUPABASE_SECRET_KEY="..."
$env:GROQ_API_KEY="..."
```

Ejecutar:

```powershell
python -m uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

Servicios disponibles:

- API: `http://127.0.0.1:8000`;
- Swagger: `http://127.0.0.1:8000/docs`;
- health: `http://127.0.0.1:8000/health`.

### 6.2 Frontend

```powershell
cd frontend
flutter pub get
flutter run
```

Para Android de desarrollo local, ajustar `ApiConfig.baseUrl` a la dirección correcta o cambiar temporalmente `baseUrl = localUrl`.

---

## 7. Contratos HTTP resumidos

| Método | Ruta | Entrada | Uso |
|---|---|---|---|
| `GET` | `/health` | ninguna | disponibilidad |
| `GET` | `/health/db` | ninguna | disponibilidad de Supabase |
| `POST` | `/api/auth/register` | JSON | registro |
| `POST` | `/voice/upload` | multipart `file` | subir una nota |
| `GET` | `/voice/recordings` | Bearer opcional | historial de grabaciones |
| `POST` | `/api/transcriptions` | multipart `audio` | transcribir |
| `POST` | `/api/analysis` | JSON | analizar texto |
| `POST` | `/api/items` | JSON | guardar elementos |
| `POST` | `/api/items/with-audio` | multipart `items` y `audio` | guardar elementos y audio |
| `GET` | `/api/items` | query `recording_id` opcional | listar elementos |
| `PUT` | `/api/items/{item_id}` | JSON, incluye `notification_offsets` opcional | actualizar elemento y su programación |
| `PATCH` | `/api/items/{item_id}/status` | JSON | actualizar estado |
| `DELETE` | `/api/items/{item_id}` | ninguna | eliminar elemento |

---

## 8. Seguridad y consideraciones operativas

- Las claves secretas deben permanecer solo en el backend o en variables de despliegue.
- CORS está configurado con `allow_origins=["*"]`; para producción conviene limitar dominios permitidos.
- En ausencia de Bearer token, las rutas usan un usuario de pruebas definido por `TEST_USER_ID`.
- Las operaciones de acceso a datos deben verificarse con reglas RLS de Supabase.
- Supabase Storage debe permitir únicamente las operaciones requeridas por el backend y la lectura autorizada por el usuario.
- El backend acepta audio `.aac` de hasta 25 MB.
- FFmpeg debe estar instalado en producción.
- El archivo local `backend/data/saved_items.json` debe considerarse respaldo, no fuente primaria.
- El registro backend existe, aunque el frontend actual usa directamente la API de Supabase Auth.
- En Web no se ejecuta Firebase; el seguimiento y las alertas dependen de temporizadores locales.

---

## 9. Inventario de archivos fuente

### Backend

```text
backend/main.py
backend/api/auth.py
backend/api/analysis.py
backend/api/items.py
backend/api/transcription.py
backend/api/voice.py
backend/core/deps.py
backend/schemas/analysis.py
backend/schemas/transcription.py
backend/schemas/voice.py
backend/services/analysis_service.py
backend/services/audio_service.py
backend/services/item_storage_service.py
backend/services/supabase_client.py
backend/services/transcription_service.py
backend/tests/test_analysis.py
backend/tests/test_auth.py
backend/tests/test_item_persistence.py
```

### Frontend

```text
frontend/lib/main.dart
frontend/lib/core/config/api_config.dart
frontend/lib/models/activity_item.dart
frontend/lib/models/extracted_item.dart
frontend/lib/models/recording_item.dart
frontend/lib/models/transcription_result.dart
frontend/lib/models/voice_note.dart
frontend/lib/models/notification_preferences.dart
frontend/lib/screens/activities_screen.dart
frontend/lib/screens/activity_detail_screen.dart
frontend/lib/screens/analysis_review_screen.dart
frontend/lib/screens/home_screen.dart
frontend/lib/screens/login_screen.dart
frontend/lib/screens/register_screen.dart
frontend/lib/screens/transcription_detail_screen.dart
frontend/lib/screens/transcription_tester_screen.dart
frontend/lib/screens/transcriptions_screen.dart
frontend/lib/screens/user_profile_screen.dart
frontend/lib/screens/voice_recorder_screen.dart
frontend/lib/services/activities_api_service.dart
frontend/lib/services/analysis_api_service.dart
frontend/lib/services/audio_recorder_service.dart
frontend/lib/services/audio_storage_helper.dart
frontend/lib/services/audio_storage_io.dart
frontend/lib/services/audio_storage_stub.dart
frontend/lib/services/audio_upload_helper.dart
frontend/lib/services/audio_upload_io.dart
frontend/lib/services/audio_upload_stub.dart
frontend/lib/services/auth_service.dart
frontend/lib/services/auth_session.dart
frontend/lib/services/browser_notifications_stub.dart
frontend/lib/services/browser_notifications_web.dart
frontend/lib/services/notification_planner.dart
frontend/lib/services/notification_schedule_service.dart
frontend/lib/services/reminder_notification_service.dart
frontend/lib/services/reminder_schedule.dart
frontend/lib/services/transcription_api_service.dart
frontend/lib/services/voice_api_service.dart
frontend/lib/widgets/activity_edit_dialog.dart
frontend/lib/widgets/slide_controls.dart
frontend/lib/widgets/transcription_panel.dart
```
