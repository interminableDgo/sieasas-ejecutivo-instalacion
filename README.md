# SGSC · SIESAS Ejecutivo

**Sistema de Gestión de Solicitudes Ciudadanas (SGSC)**, aplicación **SIESAS · Ejecutivo**: tablero de indicadores, consulta y registro de solicitudes de apoyo para el personal directivo de la **Secretaría de Salud de Nuevo León**. Es el proyecto de titulación al que corresponde este repositorio.

Documentación complementaria:
- [`GUIA_DESPLIEGUE_INSTITUCIONAL.md`](GUIA_DESPLIEGUE_INSTITUCIONAL.md): procedimiento de instalación en un servidor de la Secretaría.
- [`docs/MIGRACION_INFRAESTRUCTURA.md`](docs/MIGRACION_INFRAESTRUCTURA.md): cómo dejar Aiven, Render y Netlify; esquema, privilegios, TLS y corte.
- [`backend/README.md`](backend/README.md): API, administración y correo.
- [`pruebas/microservicios/README.md`](pruebas/microservicios/README.md): pruebas de la arquitectura de microservicios.

---

## 1. Descripción general

SIESAS Ejecutivo es una aplicación **web** (Flutter) que consulta la base de datos de solicitudes de apoyo de la Secretaría, el sistema **SSNL** (Gestoría de Apoyos), y presenta la información con indicadores, gráficas, filtros y reportes. También permite registrar nuevas solicitudes desde el módulo Ejecutivo.

La API está dividida en un **núcleo de autenticación** y **cuatro microservicios** (Indicadores y Filtros, Detalle de Indicadores, Registro Ejecutivo, Reportes y Exportación). Un **gateway Nginx** los publica, y todo se ejecuta con **Docker Compose**.

## 2. Objetivo y problemática

Las solicitudes de apoyo (medicamentos, estudios, traslados, etc.) se registran en SSNL. Para dar seguimiento, el personal directivo dependía de consultas manuales y reportes armados a mano, sin una vista consolidada por municipio, tipo de apoyo, dependencia, grupo vulnerable o estatus.

SGSC ofrece:
- indicadores actualizados desde la base de datos;
- desglose hasta la solicitud individual;
- comparación de periodos;
- exportaciones sin datos personales;
- un formulario de registro guiado que respeta el esquema SSNL.

## 3. Institución a la que está dirigido

**Secretaría de Salud del Estado de Nuevo León**, personal con rol **Ejecutivo**. Cada cuenta está limitada a una entidad federativa (por omisión, Nuevo León, clave INEGI 19).

## 4. Funcionalidades principales

| Área | Funcionalidad |
|---|---|
| Acceso | Inicio de sesión con contraseña (Argon2, o bcrypt heredado de SSNL), segundo factor TOTP si la cuenta lo tiene, solicitud de cuenta, recuperación de contraseña por correo (enlace de 30 minutos y un solo uso), perfil y cierre de sesión |
| Tablero | Total, activas y resueltas; distribución por municipio, tipo de apoyo, dependencia remitente, grupo vulnerable y estatus; tendencia mensual (registradas contra resueltas actualmente); comparación de dos periodos |
| Desglose | Desde cada indicador o barra, listado filtrado de 10 por página, y detalle de la solicitud |
| Filtros | Municipio, tipo de apoyo, dependencia, grupo vulnerable, estatus y rango de fechas de registro. Se aplican a todo el tablero, al listado y a las exportaciones. |
| Registro | Asistente de tres pasos: beneficiario (nuevo o existente, CURP opcional con validación de formato), solicitante y solicitud; pantalla de revisión antes de enviar. Asigna el estatus «Inicio», guarda la autoría y evita duplicados por reintento (idempotencia). |
| Reportes | Excel (seis hojas) y PDF con indicadores, distribuciones y tendencia del periodo filtrado, **sin nombres ni filas individuales** |

**Estados vacíos y errores.**
- Sin solicitudes: total cero e invitación a registrar la primera.
- Filtros sin coincidencias: mensaje y botón para limpiar.
- Error de conexión: mensaje y reintento; nunca se sustituye por cero.
- Información opcional ausente: «Sin información».

**Fuera de alcance:**
- el módulo **Ciudadano**: hay un prototipo con rutas `/ciudadano/*` en el núcleo, que el gateway no publica;
- regiones, prioridad por solicitud y fecha de cierre, porque el esquema SSNL no las respalda;
- métricas de tiempos o SLA.

## 5. Tecnologías utilizadas

| Capa | Tecnología |
|---|---|
| Frontend | Flutter 3 (Dart `^3.13.2`) para web: `http`, `uuid`, `share_plus`, `file_selector`; tipografía Mulish |
| Gateway | Nginx 1.27 (Alpine) |
| API | Python 3.12, FastAPI, Uvicorn, SQLAlchemy 2, PyMySQL |
| Seguridad | argon2-cffi, bcrypt, pyotp, cryptography (Fernet), tokens opacos guardados como hash SHA-256 |
| Reportes | openpyxl (Excel), reportlab (PDF) |
| Base de datos | MySQL 8.4 (hoy en Aiven, con TLS verificado) |
| Contenedores | Docker, Docker Compose v2 |
| Pruebas | pytest, httpx, flutter_test, Playwright (recorridos en navegador) |

## 6. Arquitectura y comunicación entre componentes

```
              Navegador (Flutter web)
                       │  HTTP(S)
                       ▼
     ┌──────────────── gateway (Nginx) ────────────────┐   único puerto publicado
     │  /                → archivos de Flutter web     │   127.0.0.1:8080 → 80
     │  /auth/*          → nucleo                      │
     │  /ejecutivo/dashboard|comparacion|catalogos      → indicadores
     │  GET  /ejecutivo/solicitudes[/{id}]              → detalle
     │  POST /ejecutivo/solicitudes, /personas,
     │       /colonias, /municipios-nacimiento         → registro
     │  /ejecutivo/exportar/{xlsx,pdf}                  → reportes
     │  /ciudadano/*, /docs, otras                      → 404
     └──────────────────────────────────────────────────┘
          │ red interna Docker «sgsc» (172.30.0.0/24), sin puertos publicados
          ▼
   nucleo · indicadores · detalle · registro · reportes   (FastAPI, puerto 8000 cada uno)
          │ cada servicio con su propio pool de conexiones, TLS verificado
          ▼
                   MySQL 8 (esquema SSNL + tablas de SGSC)
```

- Los servicios **no se llaman entre sí**. Cada uno valida por su cuenta el token contra MySQL, con la librería común `sgsc_common`, y consulta directamente las tablas que necesita.
- Si uno se detiene, solo sus rutas responden 503 y los demás siguen funcionando.
- El encabezado `Authorization: Bearer <token>` pasa intacto por el gateway.
- Cada respuesta indica qué servicio la atendió en `X-SGSC-Service`.

## 7. Frontend Flutter

- Proyecto en `sgsc_ejecutiva/`. Punto de entrada `lib/main.dart`; cliente de la API `lib/services/executive_api.dart`; pantallas en `lib/screens/`.
- La dirección de la API se fija **al compilar**: `--dart-define=API_BASE_URL=<url>`. Con Docker es `http://localhost:8080`; con `iniciar.ps1`, `http://127.0.0.1:8000`.
- El token de sesión se guarda solo en memoria: recargar la página exige iniciar sesión de nuevo.
- El diseño sigue el wireframe institucional: naranja Nuevo León, azul Salud, tarjetas y Mulish. Ancho máximo de 440 px en escritorio y ancho completo en móvil.
- Solo se ha compilado y probado para **web**. Las carpetas `android/`, `ios/`, `linux/`, `macos/` y `windows/` son las plantillas de Flutter, sin compilar ni probar.

## 8. Gateway Nginx

- `gateway/nginx.conf` y `gateway/Dockerfile`.
- Resuelve los servicios por el DNS interno de Docker en cada petición: arranca aunque falte un servicio.
- Límite de 30 inicios de sesión por minuto por IP (`/auth/login`, ráfaga de 10).
- Cuerpo máximo de 64 KB.
- No publica `/docs` ni `/ciudadano/*`.
- Sus registros no guardan las consultas (el enlace de recuperación lleva el token en la URL).
- `gateway/tests/test_nginx_routes.py` comprueba que cada ruta que usa Flutter llegue a su servicio.

## 9. Núcleo FastAPI y autenticación

- Código en `backend/app/`, la aplicación FastAPI original, también llamada «monolito». En Docker, el contenedor `nucleo` la ejecuta y el gateway solo le envía `/auth/*` y `/health`.
- **Rutas:**
  - `POST /auth/login`, `/auth/verify` (TOTP), `/auth/logout`, `/auth/request-access`, `/auth/forgot-password`, `/auth/reset-password`;
  - `GET /auth/me`.
- **Sesión:**
  - token opaco aleatorio; en la tabla `ejecutivo_token` solo se guarda su hash;
  - duración de 8 horas;
  - cambiar la contraseña revoca las sesiones abiertas.
- **Cada petición del Ejecutivo exige:**
  - una cuenta activa (`Tbl_Users`);
  - el rol `Ejecutivo` (`auth_assignment`);
  - una entidad asignada (`ejecutivo_acceso`);
  - todas las consultas se limitan a esa entidad.
- Límite de intentos por IP y por cuenta (`ejecutivo_limite`).
- El núcleo es el único contenedor que recibe las variables SMTP y `AUTH_ENCRYPTION_KEY`.
- **Render** publica hoy este mismo monolito, con todas sus rutas, desde la rama `dev` (`render.yaml`).
  - La prueba de paridad (`pruebas/microservicios/codigo/`) exige que la lógica copiada en los microservicios siga siendo idéntica a la del monolito.

## 10. Microservicios

| Servicio | Carpeta | Paquete | Rutas |
|---|---|---|---|
| Indicadores y Filtros | `backend/services/indicadores/` | `sgsc_indicadores` | `GET /ejecutivo/dashboard`, `/ejecutivo/comparacion`, `/ejecutivo/catalogos` |
| Detalle de Indicadores | `backend/services/detalle/` | `sgsc_detalle` | `GET /ejecutivo/solicitudes`, `/ejecutivo/solicitudes/{id}` |
| Registro Ejecutivo | `backend/services/registro/` | `sgsc_registro` | `POST /ejecutivo/solicitudes`; `GET /ejecutivo/personas`, `/ejecutivo/colonias`, `/ejecutivo/municipios-nacimiento` |
| Reportes y Exportación | `backend/services/reportes/` | `sgsc_reportes` | `GET /ejecutivo/exportar/xlsx`, `/ejecutivo/exportar/pdf` |

- **Estructura de cada servicio:**
  - un `Dockerfile` con dos etapas: `runtime` y `test`, que ejecuta sus pruebas;
  - su propio `requirements.txt`;
  - sus pruebas en `tests/`, incluido `test_isolation.py`, que prohíbe importar el monolito u otro servicio.
- **Rutas de salud:** cada servicio expone `/health` (proceso) y `/health/db` (MySQL). El gateway publica esta última como `/health/<servicio>`.
- **Librería común** `backend/libs/sgsc_common/`:
  - conexión a MySQL (pool configurable);
  - validación de sesión de solo lectura;
  - contrato de filtros;
  - creación de la app FastAPI con CORS, cabeceras y manejo de errores 503.
- Reportes calcula sus agregados por su cuenta: no depende de Indicadores.

## 11. Base de datos MySQL

- Esquema **SSNL** de la Secretaría (`Tbl_SolicitudesApoyo`, `Tbl_Beneficiarios`, `Tbl_Solicitantes`, `Tbl_Users`, catálogos `Cat_*`, INEGI y RBAC `auth_*`). Hoy está en la base `siesas-v2` de Aiven.
- **El esquema base no está en este repositorio.**
- SGSC le agrega, con migraciones aditivas (`backend/manage.py migrate`):
  - `002_ssnl_ejecutivo.sql`: tablas `ejecutivo_*` y el rol `Ejecutivo`;
  - `003_catalogos_solicitud.sql`: `Cat_Colonias` y catálogos socioeconómicos;
  - columnas `ben_dom_colonia_id` y `sol_colonia_id`;
  - `004_ciudadano.sql`: tablas del prototipo Ciudadano.
- Se requiere MySQL 8 con InnoDB, `utf8mb4_unicode_ci`, UTC, `lower_case_table_names=0` y TLS.
- Las tablas, relaciones, índices y catálogos indispensables se detallan en `docs/MIGRACION_INFRAESTRUCTURA.md`.
- `sgsc_salud_desde_cero.sql` y `backend/migrations/001_ejecutivo.sql` corresponden a un esquema anterior. **No deben ejecutarse sobre una base con datos**: el primero contiene `DROP DATABASE`.

## 12. Requisitos para ejecutar el proyecto

| Para | Necesitas |
|---|---|
| Ejecutar con Docker (recomendado) | Docker Engine o Docker Desktop con Compose v2; en Windows, WSL 2 y la virtualización habilitada. La compilación de Flutter web (`sgsc_ejecutiva/build/web`). `backend/.env` y la CA de MySQL (`backend/ca.pem`). |
| Compilar Flutter | Flutter SDK estable, compatible con Dart `^3.13.2` |
| Ejecutar sin Docker y administrar | Python 3.12 (las imágenes usan 3.12; el entorno local del monolito usa 3.14 y sus pruebas pasan) |
| Pruebas de navegador (opcional) | Python con Playwright y Google Chrome |
| Base de datos | MySQL 8 con el esquema SSNL y las migraciones (§11) |

## 13. Instalación local (sin Docker)

Es el modo de desarrollo original: el monolito en `:8000` y Flutter web en `:5173`, solo en el equipo local.

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
Copy-Item .env.example .env          # completar (sección 14) y colocar ca.pem
.\.venv\Scripts\python.exe manage.py migrate     # solo la primera vez sobre una base nueva
cd ..
.\iniciar.ps1 -Recompilar            # compila Flutter (-Flutter <ruta de flutter.bat> si no está en PATH)
.\iniciar.ps1                        # en adelante: http://127.0.0.1:5173
```

- `iniciar.ps1` busca `flutter` en el `PATH` o en `tools.local.json` (`{"flutter": "<ruta>"}`), un archivo ignorado por git.
- Las bitácoras quedan en `backend/*.local.log`.

## 14. Variables de entorno

Se definen en **`backend/.env`**, ignorado por git. La plantilla es `backend/.env.example`.

| Variable | Uso |
|---|---|
| `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD` | Conexión MySQL |
| `DB_SSL` | `true` para exigir TLS |
| `DB_SSL_CA` | Ruta del PEM de la CA de MySQL. Docker la sustituye por `/run/secrets/db_ca`. |
| `CORS_ORIGINS` | Orígenes permitidos para el núcleo, separados por comas |
| `CORS_ORIGIN_REGEX` | Opcional, solo el núcleo. Por omisión admite `*.netlify.app` (prototipo Ciudadano). |
| `AUTH_ENCRYPTION_KEY` | Clave Fernet que cifra los secretos TOTP; consérvala. Se genera con `python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"`. |
| `RESET_URL` | Dirección pública de Flutter web para el enlace de recuperación |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_SSL`, `SMTP_USER`, `SMTP_PASSWORD`, `SMTP_FROM`, `SMTP_FROM_NAME` | Correo. Sin ellas no se envían correos. |
| `GATEWAY_PORT`, `GATEWAY_ORIGINS`, `FLUTTER_WEB_DIR`, `MS_DB_POOL_SIZE`, `MS_DB_MAX_OVERFLOW` | Opcionales, solo para Docker Compose (§15) |

**No** se versionan `.env`, `*.pem`, `*.key` ni `tools.local.json`. Las imágenes Docker tampoco los incluyen (`backend/.dockerignore`).

## 15. Instalación y ejecución con Docker Compose

Desde la raíz del repositorio, con `backend/.env` y `backend/ca.pem` listos:

```powershell
# 1. Flutter web apuntando al gateway
cd sgsc_ejecutiva
flutter build web --dart-define=API_BASE_URL=http://localhost:8080
cd ..

# 2. Construir e iniciar los seis contenedores
docker compose --env-file backend/.env up -d --build

# 3. Abrir http://localhost:8080
```

**Variables de Compose**, en el mismo `.env`:

| Variable | Por omisión | Uso |
|---|---|---|
| `GATEWAY_PORT` | `8080` | Puerto local del gateway (`127.0.0.1`) |
| `GATEWAY_ORIGINS` | `http://localhost:8080,http://127.0.0.1:8080` | CORS de los microservicios |
| `FLUTTER_WEB_DIR` | `./sgsc_ejecutiva/build/web` | Carpeta de Flutter que sirve el gateway |
| `MS_DB_POOL_SIZE` / `MS_DB_MAX_OVERFLOW` | `2` / `2` | Conexiones por microservicio |

> `docker compose config` **sin** `--quiet` imprime las contraseñas sustituidas. Usa `docker compose --env-file backend/.env config --quiet`.

## 16. Comandos para construir, iniciar, detener y verificar

```powershell
docker compose --env-file backend/.env build                          # construir imágenes
docker compose --env-file backend/.env up -d                          # iniciar
docker compose --env-file backend/.env ps                             # estado (todos «healthy»)
docker compose --env-file backend/.env logs -f --tail 100 detalle     # bitácora de un servicio
docker compose --env-file backend/.env up -d --no-deps --build detalle  # reconstruir solo uno
docker compose --env-file backend/.env stop                           # detener
docker compose --env-file backend/.env down                           # detener y retirar contenedores

# Verificación sin sesión
Invoke-RestMethod http://localhost:8080/health/db                     # núcleo → MySQL
foreach ($s in 'indicadores','detalle','registro','reportes') { Invoke-RestMethod "http://localhost:8080/health/$s" }
docker run --rm -v ${PWD}/gateway/nginx.conf:/etc/nginx/conf.d/default.conf:ro nginx:1.27-alpine nginx -t
```

## 17. Procedimiento de pruebas

| Qué | Comando | Base de datos |
|---|---|---|
| Microservicios, librería común, gateway, paridad con el monolito y monolito | `.\pruebas\microservicios\ejecutar_pruebas_locales.ps1` (`-Recrear` rehace los entornos) | No (las variables apuntan a un servidor inexistente) |
| Monolito | `cd backend; .\.venv\Scripts\python.exe -m pytest -q` | No |
| Monolito con MySQL real | `$env:RUN_DB_TESTS='1'` y el comando anterior | **Sí**: escribe dentro de transacciones que se revierten. Requiere autorización. |
| Cada imagen | `docker build -f backend/services/<servicio>/Dockerfile --target test backend` | No |
| Flutter | `cd sgsc_ejecutiva; flutter analyze; flutter test` | No (API simulada) |
| Gateway real (rutas, 401, 404) | `python -m pytest pruebas/microservicios/integracion/test_gateway.py -q` | Solo lectura |
| Independencia de los servicios | `.\pruebas\microservicios\independencia.ps1` | Solo lectura |
| Entorno sin base real | `python pruebas/microservicios/offline/generar_offline.py`, luego `verificar_offline.py` | Ninguna (MySQL ficticio) |
| Recorrido en navegador | `pruebas/microservicios/e2e/` (Playwright y Chrome; ver `pruebas/microservicios/README.md`, §4) | El inicio de sesión escribe la sesión |

Las evidencias de la última validación están en `pruebas/microservicios/evidencias/` y en los informes `INFORME_E2E_FLUTTER.md` e `INFORME_REGISTRO_POST.md`.

## 18. Estructura del repositorio

```
SGSC/
├── README.md                         este documento
├── GUIA_DESPLIEGUE_INSTITUCIONAL.md  instalación en la Secretaría
├── docs/MIGRACION_INFRAESTRUCTURA.md salida de Aiven, Render y Netlify
├── docker-compose.yml                gateway + núcleo + 4 microservicios
├── render.yaml                       despliegue actual del monolito en Render (rama dev)
├── iniciar.ps1                       arranque local sin Docker
├── AGENTS.md                         instrucciones de desarrollo del proyecto
├── sgsc_salud_desde_cero.sql         esquema ANTERIOR (no usar; ver la última sección)
├── gateway/                          Nginx: nginx.conf, Dockerfile, pruebas de rutas
├── backend/
│   ├── app/                          núcleo / monolito FastAPI (routers, services, schemas, plantillas)
│   ├── libs/sgsc_common/             librería común de los microservicios
│   ├── services/{indicadores,detalle,registro,reportes}/   microservicios
│   ├── migrations/                   SQL aditivo (002, 003, 004; 001 es histórico)
│   ├── tests/                        pruebas del monolito
│   ├── manage.py                     migrate, create-user, setup-2fa, cargar-colonias, ciudadano-*
│   ├── serve_web.py                  servidor local de Flutter web (iniciar.ps1)
│   ├── Dockerfile.nucleo, .dockerignore, pytest.ini
│   └── requirements.txt, requirements.lock.txt, .env.example
├── sgsc_ejecutiva/                   app Flutter (lib/, test/, web/, assets/, plataformas)
├── pruebas/
│   ├── microservicios/               pruebas, informes y evidencias de la arquitectura
│   ├── sprint_1/ sprint_2/ sprint_3/ evidencias de pruebas por sprint (tesis)
│   └── usabilidad/                   pruebas de usabilidad (antes/después)
```

`logo/` y `promocion/` ya no forman parte del repositorio. Se archivaron fuera, en la carpeta de la tesis (`TESIS/logo` y `TESIS/promocion`).

### Función de cada carpeta y control de archivos

Cada carpeta tiene una de cuatro clasificaciones:

- **Ejecución**: el sistema la necesita para funcionar o desplegarse.
- **Desarrollo**: no se ejecuta en producción, pero sirve para probar, mantener o arrancar el proyecto en local.
- **Académica**: evidencia o material para la tesis. Ningún código la usa; puede archivarse junto con la tesis.
- **Obsoleta**: ya no se usa. Es candidata a archivar o eliminar (ver la última sección).

| Carpeta / archivo | Función | ¿La usa el sistema? | Clasificación |
|---|---|---|---|
| `backend/app/` | Núcleo FastAPI: autenticación, rutas del Ejecutivo, servicios, esquemas y plantillas de correo | Sí, lo levanta `docker-compose.yml` y también `iniciar.ps1` | Ejecución |
| `backend/services/{indicadores,detalle,registro,reportes}/` | Los cuatro microservicios, cada uno con su `Dockerfile` y sus pruebas | Sí, contenedores de `docker-compose.yml` | Ejecución |
| `backend/libs/sgsc_common/` | Librería común de los microservicios: base de datos, validación de sesión, consultas y utilidades web | Sí, la instala cada microservicio | Ejecución |
| `backend/migrations/` | SQL aditivo que `manage.py migrate` aplica sobre el esquema SSNL (002–004) | Sí, en la instalación | Ejecución (`001` es obsoleta) |
| `backend/manage.py`, `Dockerfile.nucleo`, `requirements*.txt`, `.env.example` | Comandos de administración, imagen del núcleo, dependencias y plantilla de variables | Sí | Ejecución |
| `backend/tests/` | Pruebas del monolito | No | Desarrollo |
| `backend/serve_web.py` | Servidor local de Flutter web que usa `iniciar.ps1` | Solo en local | Desarrollo |
| `backend/seed_comparison_demo.py` | Inserta datos sintéticos para la demostración de comparación | No | Obsoleta |
| `gateway/` | Nginx: único punto de entrada; enruta hacia el núcleo y los microservicios y sirve Flutter web | Sí | Ejecución (`tests/` es Desarrollo) |
| `sgsc_ejecutiva/lib/`, `web/`, `assets/`, `pubspec.*` | App Flutter del Ejecutivo: código, página web base, logo (`nl-logo.png`), municipios y fuente Mulish | Sí, se compila en `build/web` | Ejecución |
| `sgsc_ejecutiva/test/` | Pruebas de widgets y servicios de Flutter | No | Desarrollo |
| `sgsc_ejecutiva/android/`, `ios/`, `linux/`, `macos/`, `windows/` | Plantillas de plataforma generadas por Flutter | No, la app es solo web | Obsoleta salvo que se planee una versión móvil o de escritorio |
| `docker-compose.yml` | Define los seis contenedores (gateway, núcleo y cuatro microservicios) | Sí | Ejecución |
| `render.yaml` | Despliegue actual del monolito en Render desde `dev` | Sí, mientras se use Render | Ejecución temporal |
| `iniciar.ps1` | Arranque local sin Docker | Solo en local | Desarrollo |
| `README.md`, `GUIA_DESPLIEGUE_INSTITUCIONAL.md`, `docs/` | Documentación técnica, de despliegue y de migración de infraestructura | — | Ejecución (documentación que se entrega) |
| `AGENTS.md` | Reglas de desarrollo del proyecto | No | Desarrollo |
| `pruebas/microservicios/` | Pruebas de integración, independencia, entorno offline, recorrido E2E con Playwright, informes y evidencias de la arquitectura | No | Desarrollo (`evidencias/` e informes: también Académica) |
| `pruebas/sprint_1/`, `sprint_2/`, `sprint_3/` | Evidencias de pruebas por sprint | No | Académica |
| `pruebas/usabilidad/` | Pruebas de usabilidad con capturas antes/después | No | Académica |
| `logo/` *(archivada fuera del repo)* | Propuestas de logotipo SIEASAS: ronda 1 (4 conceptos), ronda 2 (4 conceptos y `generar_logos.py`) y las comparativas | **No.** La app usa `assets/nl-logo.png` y ninguna propuesta se integró | Académica |
| `promocion/` *(archivada fuera del repo)* | Material de difusión: guion del póster, página de producto (`sieasas.html`, `sitio/`), guía para publicarla en Lovable (`LOVABLE.md`), calcomanía con QR y tarjetas para el jurado | **No.** Ningún archivo del sistema la referencia | Académica |
| `sgsc_salud_desde_cero.sql` | Esquema anterior `sgsc_salud`; contiene `DROP DATABASE` | No | Obsoleta (riesgo si se ejecuta) |

**Observaciones sobre `logo/` y `promocion/`:** no aportan nada al funcionamiento ni al despliegue, y quitarlas no afecta la app, las pruebas ni Docker. Su valor es la presentación y la defensa (póster, sitio, calcomanía y tarjetas del jurado). Además, `promocion/` tiene duplicados: `Mulish.ttf` es idéntica a `sgsc_ejecutiva/assets/fonts/Mulish.ttf`, las imágenes `.webp` de `img/` se repiten en `sitio/img/`, y `sieasas.html` y `sitio/index.html` son dos versiones casi iguales de la misma página. Por eso ambas carpetas se retiraron del repositorio y se archivaron en la carpeta de la tesis; siguen disponibles en el historial de git.

**Control de archivos:** al agregar una carpeta nueva en la raíz, en `backend/` o en `pruebas/`, añádela a esta tabla con su función y su clasificación. Si algo pasa a Obsoleta, regístralo también en «Archivos y carpetas candidatos a limpieza futura».

## 19. Diferencias entre desarrollo y producción

| Aspecto | Desarrollo (probado) | Producción institucional (pendiente) |
|---|---|---|
| Ejecución | `iniciar.ps1` (monolito en `:8000`, Flutter en `:5173`) o Docker Desktop | Docker Engine en un servidor (Linux recomendado) |
| Base de datos | MySQL 8.4 en Aiven (`siesas-v2`) | MySQL 8 institucional con el esquema SSNL |
| Usuario de MySQL | Uno solo para todos los servicios | Uno por función, con privilegios mínimos |
| Transporte | HTTP en `127.0.0.1` | HTTPS con un dominio institucional (proxy o TLS en el gateway) |
| API pública | Render (monolito) | Gateway propio; Render se retira |
| `API_BASE_URL` de Flutter | `http://localhost:8080` o `http://127.0.0.1:8000` | `https://<dominio>` |
| CORS | `localhost`; `*.netlify.app` en el núcleo | Solo el dominio institucional |
| Correo | SMTP configurado localmente; enlaces a `localhost` | SMTP institucional y `RESET_URL` HTTPS |
| Datos | Expedientes de ejemplo SSNL más algunos registros de prueba marcados «PRUEBA» | Datos reales; depuración previa con autorización |
| Respaldos y monitoreo | Los del proveedor (Aiven) | Política de TI |

## 20. Requisitos para desplegarlo institucionalmente

En resumen; el detalle está en la [guía](GUIA_DESPLIEGUE_INSTITUCIONAL.md) y en [la migración](docs/MIGRACION_INFRAESTRUCTURA.md):

1. **Cambiar variables de entorno no basta.** Se necesita la base SSNL de la Secretaría, a la que luego se aplican las migraciones de SGSC, el catálogo de colonias y las cuentas Ejecutivo.
2. Un servidor con Docker y Compose, o la alternativa que defina TI.
3. MySQL 8 configurado como indica la migración (§3), con TLS y su CA.
4. Dominio y certificado HTTPS. Si hay un proxy delante del gateway, ajustar `real_ip` en Nginx.
5. Flutter web compilado con la URL HTTPS.
6. SMTP institucional.
7. Firewall: usuarios → 443; servidor → MySQL; nada más publicado.
8. Respaldos, bitácoras y actualizaciones de seguridad a cargo de TI.
9. Decisiones de la Secretaría: transferir o no los datos de Aiven, Ciudadano, el administrador PHP y el aviso de privacidad.

## Entrega a la Secretaría

**Necesario para desplegar:**
- `docker-compose.yml`;
- `gateway/` (sin `tests/`);
- `backend/`: `app/`, `libs/sgsc_common/sgsc_common/` (con `pyproject.toml`), `services/*/` (paquete, `Dockerfile` y `requirements.txt`), `migrations/` (002–004), `manage.py`, `Dockerfile.nucleo`, `.dockerignore`, `requirements*.txt` y `.env.example`;
- la compilación `sgsc_ejecutiva/build/web`, o el código para generarla;
- esta documentación.

**Para mantener el código fuente completo:** además de lo anterior,
- `sgsc_ejecutiva/` completo, con `test/`;
- todas las pruebas (`backend/tests`, `backend/services/*/tests`, `backend/libs/sgsc_common/tests`, `gateway/tests`, `pruebas/microservicios/`);
- `backend/pytest.ini` e `iniciar.ps1`;
- `backend/serve_web.py`;
- `AGENTS.md`.

**No se entregan dentro del repositorio:**
- `backend/.env`, la CA y cualquier credencial (se entregan por un canal seguro o los genera TI);
- los entornos `.venv`, `build/` y `.dart_tool/`.

**Evidencia académica que puede archivarse aparte:** `pruebas/sprint_*` y `pruebas/usabilidad`. (`logo/` y `promocion/` ya se archivaron fuera del repositorio.)

## Archivos y carpetas candidatos a limpieza futura

> **Solo `logo/` y `promocion/` se retiraron del repositorio** (archivadas en la carpeta de la tesis). Esta tabla es una propuesta para revisar en los próximos días; cada eliminación requiere autorización. La evidencia de pruebas, la documentación de tesis y las migraciones solo se **archivarían**, nunca se borrarían sin respaldo.

**Rastreados por git:**

| Ruta | Para qué servía | Por qué ya no parece necesario | Referencias | Si se elimina | Recomendación |
|---|---|---|---|---|---|
| `sgsc_salud_desde_cero.sql` | Crear el esquema anterior `sgsc_salud` desde cero | Se reemplazó por el esquema SSNL (`siesas-v2`). Contiene `DROP DATABASE`: es un riesgo si alguien lo ejecuta por error. | `backend/README.md` (advertencia), esta documentación | Ningún código lo usa | **Archivar fuera** (junto con la tesis) y quitar del repo |
| `backend/migrations/001_ejecutivo.sql` | Tablas `ejecutivo_*` para el esquema anterior | `migrate` solo aplica 002–004; 002 recrea lo mismo para SSNL | `docs/MIGRACION_INFRAESTRUCTURA.md` (como histórico) | Ningún efecto en la ejecución | Archivar o eliminar |
| `backend/seed_comparison_demo.py` | Insertar solicitudes sintéticas para demostrar la comparación de periodos | Escribe en la base; no se usa en pruebas ni en `manage.py` | Ninguna | Ninguno | Eliminar (o archivar) |
| `backend/app/routers/catalogos.py`, `dashboard.py`, `indicadores.py`, `solicitudes.py` | Rutas antiguas del Ejecutivo | `main.py` no los publica: no aplicaban la validación de rol y entidad. `executive.py` los sustituye. | No se importan | Ninguno; se elimina código muerto | Eliminar tras revisión |
| Archivos **vacíos** (0 bytes) del backend: `app/schemas/filtros.py`, `app/schemas/solicitudes.py`, `app/services/indicadores_service.py`, `app/services/solicitudes_service.py` | Esqueletos iniciales | No tienen contenido | No se importan | Ninguno | Eliminar |
| Archivos **vacíos** de Flutter: `lib/core/constants.dart`; `lib/models/{beneficiario,indicador,solicitud}.dart`; `lib/screens/auth/forgot_password_screen.dart`; `lib/screens/dashboard/indicator_detail_screen.dart`; `lib/screens/solicitudes/solicitudes_screen.dart`; `lib/services/{auth_service,solicitud_service}.dart`; `lib/widgets/{dashboard_filters,kpi_card,loading_widget,solicitud_card}.dart` | Esqueletos de la estructura inicial | 0 bytes; la funcionalidad vive en otros archivos | Ninguna | Ninguno (`flutter analyze` sin cambios) | Eliminar |
| `sgsc_ejecutiva/lib/screens/perfil/perfil_screen.dart │` | Ninguno: archivo vacío con el carácter «│» en el nombre, creado por error | Nombre inválido en la práctica; puede causar problemas en algunas herramientas | Ninguna | Ninguno | Eliminar |
| `sgsc_ejecutiva/lib/services/api_service.dart`, `dashboard_service.dart` | Clientes HTTP de la primera versión | Los reemplaza `executive_api.dart`; nadie los importa | Ninguna | Ninguno | Eliminar tras revisión |
| `sgsc_ejecutiva/android/`, `ios/`, `linux/`, `macos/`, `windows/` | Plantillas de plataforma de Flutter | La app es solo web y nunca se compiló en esas plataformas | `flutter` las usa solo al compilar para ellas | Se pierde la opción de compilar a esas plataformas sin regenerarlas (`flutter create .`) | Conservar si se planea móvil; si no, eliminar |
| `render.yaml` | Desplegar el monolito en Render | Sobra cuando la Secretaría use su infraestructura | Render lo lee desde `dev` | Render deja de actualizarse desde el repo | **Conservar** mientras Render esté en uso |
| `iniciar.ps1`, `backend/serve_web.py` | Ejecución local sin Docker | Docker Compose cubre el despliegue | `serve_web.py` lo usa `iniciar.ps1` | Se pierde el modo de desarrollo rápido | Conservar (desarrollo) |
| `backend/app/routers/ciudadano.py`, `services/ciudadano_service.py`, `migrations/004_ciudadano.sql`, `manage.py ciudadano-*` | Prototipo Ciudadano (Netlify) | Fuera del alcance actual; el gateway no lo publica | `main.py`, pruebas del monolito, Render | Se rompe el prototipo publicado en Netlify | **Conservar** hasta decidir sobre Ciudadano |
| `pruebas/sprint_1/`, `sprint_2/`, `sprint_3/` (~1.4 MB) | Evidencias de pruebas por sprint | Material de tesis, no de ejecución | Documento de tesis | Se pierde la trazabilidad desde el repo | **Archivar** fuera (con la tesis) |
| `pruebas/usabilidad/` (~3 MB) | Pruebas de usabilidad y capturas antes/después | Material de tesis | Documento de tesis | Igual | Archivar |
| `logo/` (~2.8 MB), `promocion/` (~5.2 MB) | Diseño del logotipo, póster, sitio y calcomanías | Material de difusión; la app usa sus propios assets | Ninguna desde el código | Ninguno en la app | **Hecho:** archivadas en la carpeta de la tesis y retiradas del repo |
| `pruebas/microservicios/evidencias/` | Evidencia de la validación de microservicios | Útil para la tesis y como referencia | Informes E2E y Registro | Se pierde la trazabilidad de la validación | Conservar (o archivar con la tesis) |

**Ignorados por git (solo en disco local, se regeneran):**

| Ruta | Qué es | Tamaño aprox. | Recomendación |
|---|---|---|---|
| `backend/.venv/`, `backend/services/*/.venv/`, `backend/libs/sgsc_common/.venv/`, `gateway/.venv/`, `pruebas/microservicios/codigo/.venv/` | Entornos virtuales de Python por suite | ~0.9 GB en total | Se pueden borrar; `ejecutar_pruebas_locales.ps1 -Recrear` los regenera. Conservar `backend/.venv` para `iniciar.ps1`. |
| `sgsc_ejecutiva/build/`, `sgsc_ejecutiva/.dart_tool/` | Compilación y caché de Flutter | ~180 MB | Se regeneran con `flutter build web`. `build/web` lo sirve el gateway: recompilar antes de `docker compose up`. |
| `**/__pycache__/`, `.pytest_cache/`, `backend/libs/sgsc_common/build/`, `*.egg-info/` | Cachés de Python | < 2 MB | Borrar cuando se quiera |
| `backend/*.local.log`, `backend/*.local.json` (si existen) | Bitácoras locales y respaldo de la corrección de catálogos (`catalog_encoding_backup.local.json`) | Pequeños | Las bitácoras se pueden borrar. El respaldo de catálogos conviene archivarlo antes de borrarlo. |
| `pruebas/microservicios/offline/salida/` | Compose generado para el entorno offline | Pequeño | Se regenera con `generar_offline.py` |
| `backend/.env`, `backend/ca.pem`, `tools.local.json` | Configuración y secretos locales | — | **No borrar** sin un respaldo seguro: son necesarios para ejecutar |
