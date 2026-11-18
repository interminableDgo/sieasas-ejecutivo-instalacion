# Backend SIESAS Ejecutivo

Python 3.12+, FastAPI, SQLAlchemy, PyMySQL y MySQL.

## Instalación y ejecución

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
Copy-Item .env.example .env
.\.venv\Scripts\python.exe manage.py migrate
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

Antes de migrar, completar `.env`: host, puerto, usuario y contraseña de Aiven, DB_NAME=siesas-v2, DB_SSL=true y DB_SSL_CA con la ruta de ca.pem. La conexión valida el certificado y nombre de servidor. No ejecutar `sgsc_salud_desde_cero.sql` sobre una base con datos: contiene DROP DATABASE. La migración nueva es aditiva.

## Administración local

- SSNL conserva sus catálogos originales. `seed-wireframe` está deshabilitado para esta base.
- `python manage.py create-user --correo persona@dominio.mx --nombres Nombre --apellidos Apellido --entidad 19`: autoriza la solicitud de acceso pendiente o pide una contraseña por entrada oculta. No modifica una cuenta existente.
- `python manage.py setup-2fa --correo persona@dominio.mx`: vincula un autenticador y exige un código válido antes de activarlo. Requiere AUTH_ENCRYPTION_KEY; conservar esta clave entre reinicios.

## Correo

Configurar SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASSWORD, SMTP_FROM, SMTP_SSL y RESET_URL. SMTP_SSL=false usa STARTTLS; true usa TLS directo. No se envían correos sin configuración. RESET_URL debe ser la dirección HTTPS pública de Flutter web en producción.

La respuesta de recuperación es genérica y no revela si existe una cuenta. El enlace vence en 30 minutos y es de un solo uso. La entrega ocurre después de responder, mediante una tarea de FastAPI. Fallas SMTP se registran sin datos personales. Para una operación crítica se debe sustituir esta tarea por una cola durable con reintentos.

## Rutas

Autenticación: POST /auth/login, /auth/verify, /auth/logout, /auth/request-access, /auth/forgot-password, /auth/reset-password; GET /auth/me.

Datos: GET /ejecutivo/catalogos, /ejecutivo/dashboard; GET y POST /ejecutivo/solicitudes; GET /ejecutivo/solicitudes/{id}; GET /ejecutivo/exportar/xlsx y /ejecutivo/exportar/pdf.

Datos y perfil requieren Authorization: Bearer. Cada consulta verifica cuenta activa, rol Ejecutivo en `auth_assignment` y entidad asignada. Los routers antiguos permanecen como referencia pero no se publican porque no aplicaban este control.

Filtros compartidos: municipio_id, tipo_apoyo_id, dependencia_id, grupo_vulnerable_id, estatus_id, fecha_inicio, fecha_fin. Lista: page desde cero, 10 filas por página. Exportación HU6: PDF y Excel con indicadores, distribuciones y tendencia de todo el periodo filtrado; no incluye nombres ni filas individuales. Reutiliza filtros y ámbito estatal, sin el antiguo límite de 10,000 filas. Excel conserva cantidades numéricas y trata las etiquetas de catálogo como texto para evitar fórmulas inyectadas. Fechas, filtros, generación UTC y definiciones se incluyen en ambos formatos.

## Pruebas

La descarga Excel usa `app/services/executive_xlsx.py`: seis hojas con resumen,
tendencia azul/naranja, rankings de hasta diez categorías y tablas completas.
Los colores aprobados son `#16A5D8` (registradas) y `#FF8200` (resueltas y barras).
La fecha se presenta en `America/Mexico_City`; instalar los requisitos actualizados
incluye `tzdata`, necesario en Windows. Reiniciar el backend sin `--reload` después
de actualizar el generador. Esta revisión visual corresponde al Excel; el PDF
conserva su generador existente.

```powershell
.\.venv\Scripts\python.exe -m pytest -q
$env:RUN_DB_TESTS='1'
.\.venv\Scripts\python.exe -m pytest -q
```

Las pruebas de MySQL usan una transacción exterior con savepoints y revierten sus filas temporales. Requieren la migración y los catálogos. No ejecutarlas simultáneamente desde el mismo proceso.

La importación original tenía 26 campos de catálogo mal codificados. Se corrigieron sin cambiar claves ni relaciones. Respaldo reversible: catalog_encoding_backup.local.json, excluido de Git.


## SSNL v2 — 21 de septiembre de 2026

La base activa es `siesas-v2`, importada de `SSNL-original.sql`. Sus 31 tablas originales conservan estructura y nombres exactos. Las cinco tablas auxiliares de `migrations/002_ssnl_ejecutivo.sql` sostienen sesiones, tokens, solicitudes de acceso, límites e idempotencia. No hay vistas que simulen la base anterior.

Primero se importa el SQL en una base vacía; después `manage.py migrate` agrega únicamente el soporte ejecutivo. La migración `001_ejecutivo.sql` corresponde al esquema anterior y no debe ejecutarse en SSNL. Los scripts antiguos de demostración también son exclusivos de `sgsc_salud`.

La cuenta inicial se conserva con su hash actual. FastAPI verifica Argon2 y bcrypt de Yii/PHP; los cambios de contraseña nuevos usan Argon2. La migración general de usuarios de David sigue pendiente y deberá preservar cuenta, correo, hash y asignaciones; no sustituir la tabla sin revisar esas relaciones. Las sesiones antiguas no se copian.

### Reglas de consulta

- Municipio: domicilio del beneficiario, con entidad y municipio coherentes. La autorización por entidad permanece obligatoria.
- Identificación: “Solicitud #ID”, calculada a partir de la clave; no se inventa un folio de negocio.
- Periodos y gráficas: `Tbl_SolicitudesApoyo.created`. Las resueltas se cuentan por su estatus actual dentro de cada cohorte de registro, no por una fecha de cierre inexistente.
- Resueltas: `Resuelto` y `Resuelto con observación`. Activas: excluye esas dos, `Cerrado / Cancelado` y `No es competencia`.
- Dependencia: remitente; unidad tratante se muestra por separado.
- Se retiraron filtros/regiones, prioridad por solicitud y fecha de cierre, que no están relacionados o almacenados en el original.

### Registro

Tres pasos: beneficiario, solicitante y solicitud. Se puede buscar una persona existente por nombre (o CURP del beneficiario), siempre dentro del estado autorizado, o capturar todos los campos obligatorios. Alta transaccional e idempotente: un fallo no deja personas huérfanas; un reintento no duplica solicitudes.

El backend asigna `Inicio`, autores y fechas. No agrega valores ficticios para datos personales. `ben_dom_colonia` es un entero obligatorio sin catálogo en el SQL recibido: se pide la clave numérica del expediente. Hace falta confirmar su catálogo o recibir la corrección de ese campo en una migración posterior.

Los expedientes de demostración incluidos en el SQL original se conservaron. Los que tienen municipio y entidad incompatibles no se ofrecen en los selectores ni se cuentan dentro del estado; se deben corregir en origen con información verificada.

### Retorno

La base `sgsc_salud` permanece intacta. Para volver también hay que restaurar el código previo y su configuración: el backend actual consulta las tablas SSNL directamente. Se guardó un respaldo privado completo de la base anterior y una copia privada del código/configuración antes del cambio. No publicar esos respaldos: contienen datos y secretos locales.

## Ejecución con Docker (gateway y microservicios)

Arquitectura de la tesis (2.8.4, 3.9 y Figura 53): App Ejecutiva → API Gateway Nginx → cuatro microservicios FastAPI, más el núcleo (`app/`, sin cambios) para `/auth/*`. La ejecución local con `iniciar.ps1` y el despliegue de Render siguen usando `app/` sin cambios.

| Servicio | Carpeta | Rutas |
|---|---|---|
| Indicadores y Filtros | `services/indicadores` | `GET /ejecutivo/dashboard`, `/comparacion`, `/catalogos` |
| Detalle de Indicadores | `services/detalle` | `GET /ejecutivo/solicitudes`, `/solicitudes/sugerencias`, `/solicitudes/{sid}` |
| Registro Ejecutivo | `services/registro` | `POST /ejecutivo/solicitudes`, `GET /personas`, `/colonias`, `/municipios-nacimiento` |
| Reportes y Exportación | `services/reportes` | `GET /ejecutivo/exportar/{xlsx\|pdf}` |
| Núcleo | `app/` | `/auth/*`, `/health`, `/health/db` |

- Cada servicio tiene su aplicación FastAPI, `requirements.txt`, `Dockerfile` (etapas `runtime` y `test`) y pruebas. Ninguno importa a otro ni lo llama por HTTP; comparten solo la librería `libs/sgsc_common` (conexión, validación de sesión de solo lectura y contrato de filtros y agregados).
- Reportes calcula sus agregados con la misma función que Indicadores, por lo que exporta aunque Indicadores esté detenido.
- Escrituras en MySQL: solo Registro (`Tbl_Beneficiarios`, `Tbl_Solicitantes`, `Tbl_SolicitudesApoyo`, `ejecutivo_registro`) y el núcleo. Los demás solo leen.
- Solo el gateway publica un puerto (`127.0.0.1:8080`). `.env` y `ca.pem` nunca entran a las imágenes: las variables llegan por Compose y `ca.pem` se monta en `/run/secrets/db_ca`. Los microservicios solo reciben las variables de MySQL y CORS.
- El gateway no publica `/ciudadano/*` (fuera del alcance) ni `/docs`.

Desde la raíz del repositorio, con Docker Desktop (WSL 2) disponible:

```powershell
cd sgsc_ejecutiva; flutter build web --dart-define=API_BASE_URL=http://localhost:8080; cd ..
docker compose --env-file backend/.env up -d --build
docker compose --env-file backend/.env ps                                  # todos healthy
docker compose --env-file backend/.env up -d --no-deps --build reportes    # actualizar un solo servicio
docker build -f backend/services/detalle/Dockerfile --target test backend  # pruebas dentro de la imagen
```

No ejecutes `docker compose config` sin `--quiet`: imprime los valores de `backend/.env`. La compilación web para el gateway reemplaza la de `iniciar.ps1` (que apunta a `http://127.0.0.1:8000`); usa `FLUTTER_WEB_DIR` para montar otra carpeta.

Pruebas sin Docker ni base de datos: `pruebas/microservicios/ejecutar_pruebas_locales.ps1`. Pruebas con contenedores: ver `pruebas/microservicios/README.md`.
