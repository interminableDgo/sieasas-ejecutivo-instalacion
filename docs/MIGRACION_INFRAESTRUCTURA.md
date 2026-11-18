# Migración de SGSC desde Aiven a la infraestructura de la Secretaría de Salud de Nuevo León

Este documento describe qué hace falta para que SGSC (SIESAS · Ejecutivo) deje de depender de **Aiven** (MySQL administrado), **Render** (API publicada) y **Netlify** (prototipo Ciudadano), y funcione en servidores de la Secretaría.

> **Conclusión principal: no basta con cambiar las variables de entorno.**
>
> SGSC no crea su base de datos desde cero. Trabaja **sobre el esquema de SSNL** (Gestoría de Apoyos), que es un sistema de la propia Secretaría, y le agrega tablas y columnas mediante migraciones.
>
> El esquema base (`SSNL-original.sql`) **no está en este repositorio**. Por eso, primero hay que disponer de una base SSNL compatible. Después se aplican las migraciones de SGSC, se cargan catálogos y cuentas, se configura TLS y se cambian las variables.

Los datos técnicos de este documento se obtuvieron el 17/11/2026 a partir del código del repositorio y de **metadatos** de la base actual (`information_schema`, versión y configuración del servidor, conteos por tabla). No se leyeron, exportaron ni modificaron datos de personas.

---

## 1. Qué servicios se conectan hoy a Aiven

| Componente | Dónde se ejecuta hoy | Cómo se conecta | Código |
|---|---|---|---|
| Núcleo (autenticación `/auth/*`, health, rutas del prototipo Ciudadano) | Docker local (`nucleo`) | SQLAlchemy y PyMySQL, TLS | `backend/app/database.py` |
| Monolito completo (núcleo y rutas del Ejecutivo en un proceso) | **Render** (`render.yaml`, rama `dev`) y local con `iniciar.ps1` | Igual | `backend/app/` |
| Indicadores y Filtros | Docker (`indicadores`) | Igual, mediante la librería común | `backend/libs/sgsc_common/sgsc_common/database.py` |
| Detalle de Indicadores | Docker (`detalle`) | Igual | idem |
| Registro Ejecutivo | Docker (`registro`) | Igual | idem |
| Reportes y Exportación | Docker (`reportes`) | Igual | idem |
| Comandos de administración (`migrate`, `create-user`, `setup-2fa`, `cargar-colonias`, `ciudadano-demo`, `ciudadano-borrar`) | Ejecución manual | `backend/app/database.py` | `backend/manage.py` |
| App Flutter Ejecutiva | Navegador (servida por el gateway o por `serve_web.py`) | **No se conecta a MySQL**; llama a la API | `sgsc_ejecutiva/` |
| App Ciudadano (prototipo) | Netlify. **Su código no está en este repositorio** | Llama a la API publicada en Render (`/ciudadano/*`), que usa Aiven | `backend/app/routers/ciudadano.py` |
| Administrador PHP/Yii 2 de SSNL | **Fuera de este repositorio** | Comparte las tablas `auth_*`, `Tbl_Users`, `admin_*` y catálogos | — |

## 2. Configuración que usa cada servicio

Todos leen las mismas variables, con algunas diferencias:

| Variable | Núcleo y monolito | Microservicios | Uso |
|---|---|---|---|
| `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD` | ✔ | ✔ | Conexión MySQL |
| `DB_SSL` (`true` o `false`), `DB_SSL_CA` (ruta del certificado de la CA) | ✔ | ✔ | TLS con verificación del certificado y del nombre del servidor |
| `DB_POOL_SIZE`, `DB_MAX_OVERFLOW`, `DB_POOL_RECYCLE` | — (fijo 5/10/280) | ✔ (en Compose se toman de `MS_DB_POOL_SIZE` y `MS_DB_MAX_OVERFLOW`, 2/2) | Número de conexiones |
| `CORS_ORIGINS` | ✔ | ✔ (en Compose se toma de `GATEWAY_ORIGINS`; por omisión `http://localhost:8080`) | Orígenes web permitidos |
| `CORS_ORIGIN_REGEX` | ✔ (por omisión `https://[a-z0-9-]+\.netlify\.app`) | — | Prototipo Ciudadano en Netlify |
| `AUTH_ENCRYPTION_KEY` | ✔ | — | Cifra los secretos del segundo factor (TOTP) |
| `RESET_URL`, `SMTP_*` | ✔ | — | Recuperación de contraseña por correo |
| `FORWARDED_ALLOW_IPS` | ✔ (Docker) | ✔ (Docker) | IP del gateway en la que confía `--proxy-headers` |

- **Local y Docker:** las variables vienen de `backend/.env`, que git ignora; la plantilla es `backend/.env.example`.
- **Docker:** `docker-compose.yml` entrega a los cuatro microservicios **solo** las variables de MySQL y CORS, y monta el certificado como secreto en `/run/secrets/db_ca`.
- **Render:** las variables se capturan en su panel. El certificado se sube como *Secret File* (`/etc/secrets/ca.pem`).

## 3. Requisitos de MySQL

Configuración de la base actual (Aiven):

| Parámetro | Valor actual | Requisito para la base institucional |
|---|---|---|
| Versión | MySQL **8.4.11** | MySQL 8.x. Es la única versión probada; otra versión debe validarse con las pruebas (§16). |
| Motor | InnoDB | **InnoDB**, obligatorio por las claves foráneas y las transacciones |
| Conjunto de caracteres de la base | `utf8mb4`, colación `utf8mb4_unicode_ci` | Igual. La búsqueda sin acentos ni mayúsculas depende de `utf8mb4_unicode_ci`. Las tablas `auth_*` usan `utf8mb3_unicode_ci` (heredadas de Yii). |
| `sql_mode` | `ANSI` (incluye `ANSI_QUOTES` y `PIPES_AS_CONCAT`), `ONLY_FULL_GROUP_BY`, `STRICT_ALL_TABLES`, `NO_ZERO_IN_DATE`, `NO_ZERO_DATE`, `ERROR_FOR_DIVISION_BY_ZERO`, `NO_ENGINE_SUBSTITUTION` | Se recomienda replicarlo. Es el único probado; las consultas usan comillas simples y `CONCAT`, pero un `sql_mode` distinto debe validarse. |
| `lower_case_table_names` | `0` | **0**: los nombres de tabla distinguen mayúsculas (`Tbl_Users`, `INEGI_Cat_Municipios`). En Windows el valor por omisión es 1; se recomienda un servidor Linux. |
| Zona horaria | `time_zone=SYSTEM` (UTC) | **UTC**. Las fechas de registro (`created`) se guardan y comparan en UTC; los reportes las convierten a `America/Mexico_City`. |
| TLS | TLS 1.2 y 1.3; `require_secure_transport=OFF` | TLS 1.2 o superior. Se recomienda `require_secure_transport=ON` en el servidor institucional. La aplicación siempre exige verificar el certificado. |
| Vistas, procedimientos y *triggers* | Ninguno | No se requieren. |
| Conexiones | `max_connections=76` (máximo usado desde el último reinicio del servidor: 10) | Con Docker: hasta 4 por microservicio (`MS_DB_POOL_SIZE` + `MS_DB_MAX_OVERFLOW` = 2 + 2) más hasta 15 del núcleo, es decir, ~31. Más el monolito de Render, si sigue activo. |

## 4. Tablas, relaciones e índices

La base actual (`siesas-v2`) tiene **52 tablas** y **43 claves foráneas**.

### 4.1 Origen de cada grupo de tablas

| Grupo | Tablas | Origen | ¿Está en este repositorio? |
|---|---|---|---|
| **SSNL base** | `Tbl_SolicitudesApoyo`, `Tbl_Beneficiarios`, `Tbl_Solicitantes`, `Tbl_Telefonos`, `Tbl_Users`, catálogos `Cat_*` (excepto los de 003), `INEGI_Cat_Entidades`, `INEGI_Cat_Municipios`, `INEGI_Cat_Localidades`, `auth_item`, `auth_item_child`, `auth_assignment`, `auth_rule`, `LoginHistory`, `BlockedIps`, `aud_login_attempts`, `audit_controller_access` y la tabla `migration` de Yii | `SSNL-original.sql`, el sistema de la Secretaría | **No** |
| Administrador PHP (Sprint 2–3) | `admin_audit`, `admin_lock`, `admin_role`, `admin_unit` | Migraciones del administrador Yii 2 dentro de SSNL | **No** (confirmar con el repositorio del administrador) |
| Ejecutivo | `ejecutivo_acceso`, `ejecutivo_token`, `ejecutivo_acceso_solicitud`, `ejecutivo_limite`, `ejecutivo_registro`, más el rol `Ejecutivo` en `auth_item` | `backend/migrations/002_ssnl_ejecutivo.sql` | Sí |
| Catálogos del formulario | `Cat_Colonias`, `Cat_ConQuienVive`, `Cat_Ocupaciones`, `Cat_FuentesIngreso`, `Cat_AreasEstudio` (con sus valores iniciales) | `backend/migrations/003_catalogos_solicitud.sql` | Sí |
| Columnas de colonia | `Tbl_Beneficiarios.ben_dom_colonia_id` y `Tbl_Solicitantes.sol_colonia_id`, con FK a `Cat_Colonias` | `backend/manage.py migrate` (`ALTER TABLE` condicional) | Sí. **Modifica dos tablas SSNL.** |
| Prototipo Ciudadano | `ciudadano_cuenta`, `ciudadano_sesion`, `ciudadano_solicitud`, `ciudadano_recuperacion`, el canal «App SIEASAS Ciudadano» y el municipio «No especificado» (`cve_mun` 999) | `backend/migrations/004_ciudadano.sql` | Sí |

`backend/migrations/001_ejecutivo.sql` y `sgsc_salud_desde_cero.sql` corresponden a un **esquema anterior** (`sgsc_salud`). **No son equivalentes al esquema actual**, no deben usarse para la migración, y el segundo contiene `DROP DATABASE`.

### 4.2 Relaciones que usa SGSC

```
INEGI_Cat_Entidades ─< INEGI_Cat_Municipios ─< Cat_Colonias
        │                     │                      │
        ├──────────────< Tbl_Beneficiarios >─────────┤  (domicilio, nacimiento, colonia)
        │                     │   └─> Cat_GruposVulnerables, Cat_SeguridadSocial
        ├──────────────< Tbl_Solicitantes  >─────────┘  (+ Cat_Parentescos)
        │
Tbl_SolicitudesApoyo ─> Tbl_Beneficiarios, Tbl_Solicitantes, Cat_TipoApoyo, Cat_EnviadoPor,
                         Cat_Dependencias, Cat_PartidosPoliticos, Cat_CanalesRecepcion,
                         Cat_UnidadesTratantes, Cat_StatusAtencion, Tbl_Users (responsable)
ejecutivo_registro   ─> Tbl_SolicitudesApoyo, Tbl_Users       (autor e idempotencia)
ejecutivo_acceso     ─> Tbl_Users, INEGI_Cat_Entidades        (entidad autorizada)
ejecutivo_token      ─> Tbl_Users                             (sesión, reto 2FA, recuperación)
auth_assignment      ─> auth_item                             (rol «Ejecutivo»)
Tbl_Users            ─> admin_unit                            (organigrama)
```

### 4.3 Índices únicos indispensables

- `Tbl_Beneficiarios.ben_gen_curp`: CURP única; admite NULL.
- `ejecutivo_registro.uq_registro_reintento (usuario_id, idempotencia)`: evita duplicados por reintento.
- `Tbl_Users`: correo y cuenta únicos.
- `Cat_Colonias.uq_colonia_ubicacion`.
- `INEGI_Cat_Municipios (entidad, municipio)` y `cvegeo`; `INEGI_Cat_Entidades.cve_ent`.
- `ciudadano_solicitud.uq_ciudadano_reintento`, solo si se conserva Ciudadano.

## 5. Catálogos y datos iniciales indispensables

Sin estos datos, la API responde, pero el formulario se bloquea (muestra «Faltan opciones obligatorias en los catálogos») o el registro devuelve 422 o 503:

| Dato | Uso | Fuente |
|---|---|---|
| `INEGI_Cat_Entidades` (32) e `INEGI_Cat_Municipios` (2,510) | Ámbito por entidad, domicilio y nacimiento | SSNL base (INEGI) |
| `Cat_StatusAtencion` con la descripción exacta **«Inicio»** | Estatus inicial del registro. Las descripciones «Resuelto», «Resuelto con observación», «Cerrado / Cancelado» y «No es competencia» se usan en los indicadores. | SSNL base |
| `Cat_TipoApoyo`, `Cat_EnviadoPor`, `Cat_CanalesRecepcion`, `Cat_UnidadesTratantes`, `Cat_Generos`, `Cat_SeguridadSocial`, `Cat_GruposVulnerables`, `Cat_Parentescos` (con un valor **«Otro»**), `Cat_Dependencias`, `Cat_PartidosPoliticos` (con `is_active=1`) | Formulario y filtros | SSNL base |
| `Cat_ConQuienVive`, `Cat_Ocupaciones`, `Cat_FuentesIngreso`, `Cat_AreasEstudio` | Formulario (información social) | Migración 003 |
| `Cat_Colonias` del estado | Domicilio. Sin colonias no se puede registrar. | `python manage.py cargar-colonias <CPdescarga.txt> --estado 19` (archivo de SEPOMEX) |
| `auth_item` «Ejecutivo» (`type=1`) | Rol exigido en cada petición | Migración 002 |
| Cuentas: `Tbl_Users` activo, `auth_assignment` (Ejecutivo) y `ejecutivo_acceso` (entidad) | Inicio de sesión | `python manage.py create-user …` o el administrador PHP, más `ejecutivo_acceso` |

## 6. Cómo preparar una base MySQL institucional

1. **TI decide** la plataforma:
   - servidor Linux, máquina virtual o servicio MySQL institucional;
   - versión 8.x, configurada según §3: InnoDB, `utf8mb4`, `utf8mb4_unicode_ci`, `sql_mode` equivalente, `lower_case_table_names=0` y UTC.
2. **La Secretaría provee el esquema SSNL** vigente. Puede ser su base de producción o un *dump* de estructura (`mysqldump --no-data`) con los catálogos.
   - SGSC no puede reconstruir el esquema base: sus 30+ tablas y columnas no se definen en el código.
   - El código y los metadatos sí permiten **verificar** que el esquema provisto tenga las tablas, columnas y claves que SGSC usa (§4).
3. Crear la base, por ejemplo `CREATE DATABASE sgsc CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;`, e importar el esquema SSNL con sus catálogos.
4. Aplicar las migraciones de SGSC (§7).
5. Cargar las colonias (`cargar-colonias`) y crear las cuentas Ejecutivo (`create-user`; `setup-2fa` si aplica).

**No se puede completar todavía sin el esquema base:** crear la base desde cero, validar compatibilidad de columnas y probar contra la base institucional.

## 7. Migraciones de SGSC sobre la base SSNL

Con un `.env` que apunte a la base nueva y un usuario con privilegios de esquema (`CREATE`, `ALTER`, `INDEX`, `REFERENCES`, `INSERT`), solo durante la instalación:

```powershell
cd backend
.\.venv\Scripts\python.exe manage.py migrate
```

- `migrate` aplica `002`, `003` y **`004` (Ciudadano)**, y agrega las columnas `*_colonia_id` (§4.1). Es aditiva y está pensada para poder repetirse; aun así, **haz un respaldo antes**.
- **Si no se usará el prototipo Ciudadano**, `004` agrega 4 tablas, un canal de recepción y el municipio 999 que no hacen falta. TI puede aplicar manualmente solo `002` y `003`, más los dos `ALTER TABLE` de `manage.py` (líneas `COLONY_COLUMNS`), en lugar de `migrate`.
- **No ejecutar** `001_ejecutivo.sql` ni `sgsc_salud_desde_cero.sql`.

## 8. Exportar e importar la información existente (solo con autorización)

Solo aplica si la Secretaría **autoriza por escrito** transferir los datos de Aiven:

1. Respaldo completo de Aiven (*backup* del servicio) y `mysqldump --single-transaction --routines --triggers --set-gtid-purged=OFF --default-character-set=utf8mb4 <base>`, hecho por personal autorizado.
2. Transferencia **cifrada**, sin copias intermedias en equipos personales. El archivo contiene datos personales y de salud: tratarlo conforme al aviso de privacidad y borrarlo de forma segura después de importarlo.
3. Importar en la base institucional vacía con el mismo `sql_mode`, la misma colación y `--default-character-set=utf8mb4`.

Datos de prueba que conviene **no** migrar o depurar, previa decisión de la Secretaría:
- la solicitud sintética **#581** (beneficiario 88, solicitante 100, marcada «[PRUEBA AUTOMATIZADA SGSC – NO ATENDER]»);
- otros registros «PRUEBA…»;
- las cuentas del prototipo Ciudadano;
- los tokens vencidos de `ejecutivo_token` y los contadores de `ejecutivo_limite`.

Si **no** se autoriza transferir datos, se parte de la base SSNL institucional con sus propios registros y solo se aplican §6 y §7.

## 9. Verificar integridad, relaciones y conteos

Después de importar o migrar, comparar contra la base de origen:

```sql
-- Conteos por tabla (comparar origen vs. destino)
SELECT TABLE_NAME, TABLE_ROWS FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE();
SELECT COUNT(*) FROM Tbl_SolicitudesApoyo;  -- repetir con COUNT(*) exacto en las tablas clave

-- Huérfanos (todos deben dar 0)
SELECT COUNT(*) FROM Tbl_SolicitudesApoyo sa LEFT JOIN Tbl_Beneficiarios b ON b.ben_id = sa.solapoyo_beneficiarioid WHERE b.ben_id IS NULL;
SELECT COUNT(*) FROM Tbl_SolicitudesApoyo sa LEFT JOIN Tbl_Solicitantes s ON s.sol_id = sa.solapoyo_solicitanteid WHERE s.sol_id IS NULL;
SELECT COUNT(*) FROM ejecutivo_registro er LEFT JOIN Tbl_SolicitudesApoyo sa ON sa.solapoyo_id = er.solicitud_id WHERE sa.solapoyo_id IS NULL;

-- Claves foráneas presentes (deben ser al menos las 43 de §4)
SELECT COUNT(*) FROM information_schema.KEY_COLUMN_USAGE WHERE TABLE_SCHEMA = DATABASE() AND REFERENCED_TABLE_NAME IS NOT NULL;

-- Datos indispensables
SELECT id FROM Cat_StatusAtencion WHERE descripcion = 'Inicio' AND is_active = 1;
SELECT name FROM auth_item WHERE name = 'Ejecutivo' AND type = 1;
```

Funcionalmente, el tablero (total, activas, resueltas), los conteos por municipio y una exportación deben coincidir entre origen y destino para la misma cuenta y los mismos filtros. `pruebas/microservicios/integracion/test_paridad.py` compara dos despliegues con el mismo token.

## 10. Usuarios y privilegios por servicio

Hoy todos los servicios usan **el mismo usuario** de MySQL. Para producción se recomienda separar:

| Usuario | Servicio | Privilegios mínimos |
|---|---|---|
| `sgsc_admin` | Instalación (`manage.py migrate`, `cargar-colonias`, `create-user`) | Esquema y datos durante la instalación; **deshabilitarlo después** |
| `sgsc_nucleo` | Núcleo (`/auth`) | `SELECT` en `Tbl_Users`, `auth_assignment`, `auth_item`, `ejecutivo_acceso`, `INEGI_Cat_Entidades`. `SELECT, INSERT, UPDATE` en `ejecutivo_token`, `ejecutivo_limite` y `ejecutivo_acceso_solicitud`. `UPDATE` en `ejecutivo_acceso` y en `Tbl_Users` (columnas de contraseña). Con Ciudadano, además: `SELECT, INSERT, UPDATE, DELETE` en `ciudadano_*`; `INSERT, UPDATE` en `Tbl_Beneficiarios`, `Tbl_Solicitantes`, `Tbl_SolicitudesApoyo`; `INSERT` en `Cat_Colonias`. |
| `sgsc_indicadores`, `sgsc_detalle`, `sgsc_reportes` | Lectura | `SELECT` en `Tbl_SolicitudesApoyo`, `Tbl_Beneficiarios`, `Tbl_Solicitantes`, `Cat_*`, `INEGI_*`, y las tablas de sesión (`ejecutivo_token`, `ejecutivo_acceso`, `Tbl_Users`, `auth_*`) |
| `sgsc_registro` | Registro | Lo mismo que lectura, más `INSERT` en `Tbl_Beneficiarios`, `Tbl_Solicitantes` y `Tbl_SolicitudesApoyo`, y `SELECT, INSERT` en `ejecutivo_registro` |

**Adaptación pendiente.** `docker-compose.yml` hoy entrega las mismas `DB_USER` y `DB_PASSWORD` a los cuatro microservicios (bloque `x-db-env`). Para usar usuarios distintos, TI debe definir `DB_USER` y `DB_PASSWORD` por servicio, por ejemplo con un archivo de variables por servicio o un `docker-compose.override.yml`. El código no necesita cambios.

Antes de producción conviene una prueba completa con privilegios mínimos (§16).

## 11. Certificados TLS institucionales

- La aplicación usa `ssl.create_default_context(cafile=DB_SSL_CA)`, que exige que el certificado del servidor esté firmado por esa CA y que su nombre (CN o SAN) **coincida con `DB_HOST`**. Si se conecta por IP, el certificado debe incluir esa IP en el SAN.
- **CA propia de la Secretaría:** colocar el certificado de la CA, o la cadena completa (raíz e intermedias) en un solo archivo PEM, en `backend/ca.pem` o en otra ruta.
  - Local: `DB_SSL_CA` apunta a esa ruta.
  - Docker: `docker-compose.yml` monta `./backend/ca.pem` como `/run/secrets/db_ca`. Basta con reemplazar el archivo, o cambiar `secrets.db_ca.file`.
- **Certificado de una CA pública:** `DB_SSL_CA` puede quedar vacía y se usan las CA del sistema; en Docker, las de la imagen.
- **No** usar `DB_SSL=false` fuera de una red aislada y controlada.
- `ca.pem` (y cualquier `*.pem` o `*.key`) está excluido de git (`.gitignore`) y de las imágenes (`backend/.dockerignore`).

## 12. Variables de entorno que cambian

En `backend/.env` (no se versiona; partir de `backend/.env.example`):

| Variable | Valor nuevo |
|---|---|
| `DB_HOST`, `DB_PORT` | Servidor MySQL institucional |
| `DB_NAME` | Base institucional (hoy `siesas-v2`) |
| `DB_USER`, `DB_PASSWORD` | Usuario de ejecución (§10), no el administrador |
| `DB_SSL=true`, `DB_SSL_CA` | Ruta del PEM de la CA institucional (en Docker la sobrescribe Compose) |
| `CORS_ORIGINS` | Solo el dominio HTTPS institucional de la app, por ejemplo `https://sgsc.salud.nl.gob.mx` (a confirmar). Si Flutter se sirve desde el mismo gateway, no hay peticiones de otro origen. |
| `CORS_ORIGIN_REGEX` | Su valor por omisión admite cualquier `*.netlify.app`. En producción, fijarlo al dominio institucional del prototipo Ciudadano o a `^$` si no se usa. |
| `RESET_URL` | `https://<dominio institucional>` (el enlace de recuperación apunta a la app Flutter) |
| `SMTP_*` | Servidor de correo institucional |
| `AUTH_ENCRYPTION_KEY` | **Conservar** la actual si se migran cuentas con 2FA. Si cambia, hay que volver a vincular el segundo factor (`setup-2fa`). |

Además, la app Flutter se compila con la dirección pública de la API:
`flutter build web --dart-define=API_BASE_URL=https://<dominio institucional>`.

## 13. Archivos con referencias a Aiven, Render o Netlify

| Archivo | Referencia | Acción |
|---|---|---|
| `backend/.env` (local, ignorado) | Host, puerto y usuario de Aiven; `DB_SSL_CA` | Reemplazar (§12) |
| `backend/ca.pem` (local, ignorado) | CA de Aiven | Reemplazar por la CA institucional |
| `render.yaml` | Despliegue en Render (rama `dev`); comentarios sobre Aiven; `/etc/secrets/ca.pem` | Retirar o ignorar si se deja de usar Render |
| `backend/app/main.py` | `CORS_ORIGIN_REGEX` por omisión para `*.netlify.app` | Definir la variable (§12) |
| `docker-compose.yml`, `backend/libs/sgsc_common/sgsc_common/database.py` | Comentarios sobre Aiven | Solo documentación |
| `README.md`, `backend/README.md`, `pruebas/**` (informes y evidencias) | Mencionan Aiven como entorno de pruebas | Documentación histórica |

Ningún archivo versionado contiene credenciales de Aiven.

## 14. Red, puertos y firewall

- Desde los contenedores (o el servidor de la API) hacia MySQL: puerto TCP de MySQL (3306 o el que defina TI), **solo** desde el servidor de SGSC.
- Desde los usuarios hacia el gateway: **443/TCP** (HTTPS), y 80 solo para redirigir a 443.
  - Hoy `docker-compose.yml` publica `127.0.0.1:8080`, solo para el equipo local.
  - En producción, TI publica el gateway detrás de su balanceador o proxy con certificado, o agrega `listen 443 ssl` a `gateway/nginx.conf` y monta el certificado.
- Los microservicios y el núcleo **no publican puertos**: solo son accesibles en la red interna `sgsc` (`172.30.0.0/24`). Si esa subred choca con la red institucional, se cambia en `docker-compose.yml` (`networks.sgsc` y `ipv4_address` del gateway) junto con `FORWARDED_ALLOW_IPS`.
- Salida hacia SMTP, si se usa recuperación por correo.

## 15. Cómo asegurarse de que no quedan conexiones a Aiven

1. Buscar referencias a Aiven en la configuración: `Select-String -Path backend\.env -Pattern 'aiven'` (o `grep -i aiven backend/.env`). Debe salir vacío.
2. Desde un contenedor, comprobar contra qué servidor se conecta, sin imprimir secretos:
   `docker compose --env-file backend/.env exec registro python -c "from sgsc_common.database import engine; print(engine.url.host)"`
3. En el panel de Aiven, revisar que no haya conexiones activas (métricas de conexiones) después del corte.
4. En el firewall institucional, bloquear la salida hacia los dominios `*.aivencloud.com`.
5. Revocar el usuario de la aplicación en Aiven, o rotar su contraseña, una vez validado el corte (§18).
6. Desactivar el servicio de Render y el sitio de Netlify, o apuntarlos a la nueva API, para que ninguna instancia antigua siga escribiendo en Aiven.

## 16. Validar cada microservicio contra la base nueva

Sin token y sin escribir nada:

```powershell
docker compose --env-file backend/.env up -d --build
docker compose --env-file backend/.env ps                       # todos «healthy»
Invoke-WebRequest http://localhost:8080/health/db               # núcleo → MySQL
foreach ($s in 'indicadores','detalle','registro','reportes') {
  (Invoke-WebRequest "http://localhost:8080/health/$s").Content  # cada servicio → MySQL
}
```

`/health/<servicio>` responde `{"database":"connected"}` solo si ese servicio llega a MySQL con TLS válido.

Con una cuenta Ejecutivo y un token (el inicio de sesión **escribe** en `ejecutivo_token` y `ejecutivo_limite`):
- `pruebas/microservicios/integracion/test_gateway.py`: rutas, servicio que atiende, 401 sin sesión y 404 de rutas no publicadas;
- `pruebas/microservicios/independencia.ps1`: independencia de los servicios;
- el recorrido de Flutter (`pruebas/microservicios/e2e/`).

El registro de una solicitud **escribe datos de negocio**: hacerlo solo con autorización y con datos sintéticos claramente marcados.

## 17. Autenticación y permisos

- Cada petición del Ejecutivo exige un token de sesión vigente (`ejecutivo_token`), una cuenta activa (`Tbl_Users.is_active=1`), el rol `Ejecutivo` en `auth_assignment` y una entidad en `ejecutivo_acceso`. Todas las consultas se limitan a esa entidad.
- Comprobaciones:
  - una cuenta sin `ejecutivo_acceso` o sin rol recibe 401 al iniciar sesión;
  - una cuenta con otra entidad solo ve datos de esa entidad;
  - `POST /auth/logout` revoca el token (después, 401).
- Las contraseñas existentes en bcrypt (Yii) se aceptan; las nuevas se guardan con Argon2.
- El límite de intentos usa la IP real del cliente. En Docker funciona porque uvicorn confía en `--proxy-headers` solo desde la IP del gateway. Si hay otro proxy delante, TI debe propagar `X-Forwarded-For` y ajustar `FORWARDED_ALLOW_IPS`.

## 18. Respaldo, restauración y recuperación

- Respaldo diario cifrado de la base (`mysqldump --single-transaction` o la herramienta institucional), con retención definida por la Secretaría y una **prueba periódica de restauración** en un servidor aislado.
- Respaldo **antes** de cada migración o actualización de SGSC.
- Los contenedores no guardan estado: se reconstruyen desde el repositorio. Hay que respaldar `backend/.env`, la CA, `AUTH_ENCRYPTION_KEY` y los certificados HTTPS en una bóveda de secretos institucional.
- Recuperación: restaurar la base y levantar con `docker compose --env-file backend/.env up -d` la misma versión del repositorio (etiqueta o commit).

## 19. Migración controlada y cambio definitivo

1. **Preparación (sin impacto):**
   - base institucional con el esquema SSNL, las migraciones y los catálogos;
   - servidor con Docker;
   - `.env` nuevo y certificados;
   - pruebas de §16 con una copia de datos o datos sintéticos.
2. **Ensayo:** importar un respaldo reciente, validar §9 y §16, y medir tiempos. Registrar cuánto tarda.
3. **Ventana de mantenimiento**, anunciada a los usuarios:
   1. Detener las escrituras: Render, el prototipo Ciudadano y el administrador PHP si comparte la base.
   2. Respaldo final de Aiven.
   3. Importarlo en la base institucional.
   4. Validar §9: conteos iguales y 0 huérfanos.
   5. Cambiar `.env` y desplegar.
   6. Ejecutar §16 y el recorrido funcional.
4. **Cambio definitivo:**
   - publicar el dominio institucional (DNS);
   - compilar Flutter con la nueva `API_BASE_URL`;
   - desactivar Render y Netlify o reapuntarlos;
   - aplicar §15.
5. **Reversión**, si falla la validación dentro de la ventana:
   - volver a apuntar la configuración a Aiven, que sigue intacta porque no se borró;
   - reactivar Render;
   - anunciar el regreso.
   - Las escrituras hechas en la base nueva durante la ventana deben conciliarse manualmente; por eso conviene mantener las escrituras detenidas hasta validar.

## 20. Protección de los datos sensibles de ciudadanos y solicitudes

`Tbl_Beneficiarios`, `Tbl_Solicitantes` y `Tbl_SolicitudesApoyo` contienen datos personales y **sensibles** (salud, seguridad social, situación socioeconómica, CURP, domicilio y teléfono). Su tratamiento debe seguir la legislación de protección de datos personales en posesión de sujetos obligados (general y del Estado de Nuevo León) y el aviso de privacidad de la Secretaría. El área jurídica y la de transparencia deben confirmar qué disposiciones aplican.

Lo que ya hace SGSC:
- TLS con verificación del certificado hacia MySQL.
- Contraseñas con Argon2, o bcrypt heredado.
- Tokens de sesión opacos: solo se guarda su hash, duran 8 horas y Flutter los mantiene en memoria.
- Segundo factor (TOTP) cifrado con `AUTH_ENCRYPTION_KEY`.
- Cada consulta se limita a la entidad autorizada de la cuenta.
- Los reportes PDF y Excel no incluyen nombres ni filas individuales.
- El gateway no registra las consultas (*query strings*) en sus bitácoras.
- Las fallas SMTP se registran sin datos personales.
- `.env` y los certificados no entran a git ni a las imágenes.

Lo que debe decidir y operar TI:
- **Acceso a la base:** solo desde el servidor de SGSC y desde administradores nominales. Sin acceso público.
- **Usuarios separados** con privilegios mínimos (§10). Desactivar el usuario de instalación después de usarlo.
- **Cifrado en reposo** del disco o de la base, y de los respaldos (§18).
- **Secretos** (`.env`, `AUTH_ENCRYPTION_KEY`, contraseñas de MySQL y SMTP) en una bóveda o archivo con permisos restringidos al servicio. Rotarlos si se exponen.
- **Bitácoras:** retención definida. Evitar que los registros de MySQL (consultas generales o lentas) guarden datos personales en texto claro.
- **Copias de datos** para pruebas o desarrollo: solo anonimizadas. No usar la base de producción para pruebas automatizadas.
- **Bajas:** desactivar la cuenta (`Tbl_Users.is_active=0`) revoca el acceso en la siguiente petición. Las sesiones vigentes se invalidan al cambiar la contraseña.
- **Ejercicio de derechos ARCO** y depuración de datos de prueba: procedimiento a cargo de la Secretaría. SGSC no implementa la eliminación de expedientes.

## 21. Información y accesos que debe proporcionar TI de la Secretaría

- **Esquema SSNL vigente** (estructura y catálogos), la versión de MySQL, `sql_mode`, la colación y la zona horaria del servidor institucional.
- El servidor o los servidores: sistema operativo, CPU, RAM, disco, red y si se permite Docker (Docker Engine y Compose) o se requiere otro mecanismo.
- Host, puerto y nombre de la base. Usuarios de instalación y de ejecución, con sus privilegios (§10).
- Certificado o cadena de la **CA** de MySQL, y el **certificado HTTPS** y el dominio público de la app.
- Reglas de firewall: servidor de la API → MySQL, usuarios → 443, salida a SMTP.
- Servidor SMTP institucional y remitente.
- Política de respaldos, retención y monitoreo; bitácoras centralizadas.
- Decisión sobre la **transferencia de datos** desde Aiven (§8) y sobre los datos de prueba.
- Decisión sobre el **prototipo Ciudadano**: si se despliega, dónde y con qué dominio.
- Relación con el **administrador PHP/Yii 2**: si comparte la base, cómo se despliega y quién lo mantiene.
- Responsables de operación, cuentas iniciales del rol Ejecutivo y la entidad de cada una.

---

## Sustitución de Render, Netlify y Aiven

| Hoy | Reemplazo institucional | Estado |
|---|---|---|
| **Aiven** (MySQL) | MySQL 8 institucional (§3–§12) | Documentado. Requiere el esquema SSNL de la Secretaría. |
| **Render** (monolito `backend/app` publicado) | `docker-compose.yml`: el gateway Nginx publica `/auth/*` (núcleo) y `/ejecutivo/*` (cuatro microservicios). Render deja de ser necesario para el Ejecutivo. | Implementado y probado localmente (Docker Desktop, Aiven) |
| Flutter web del Ejecutivo (hoy `serve_web.py` local) | El mismo gateway sirve `sgsc_ejecutiva/build/web` (volumen `FLUTTER_WEB_DIR`) | Implementado y probado localmente |
| **Netlify** (prototipo Ciudadano) | **No incluido en Docker.** Su código Flutter no está en este repositorio, y el gateway **no publica** `/ciudadano/*` (responde 404). Para alojarlo: compilar esa app y servirla desde Nginx u otro servidor web, y publicar `/ciudadano/*` hacia el núcleo, que ya contiene esas rutas, cambiando `location ^~ /ciudadano/` en `gateway/nginx.conf`. | **Pendiente**, fuera del alcance actual (tesis, «Trabajos a futuro») |
| Administrador PHP/Yii 2 de SSNL | Lo despliega TI con su propia infraestructura (PHP-FPM y servidor web), sobre la misma base | Fuera de este repositorio |
| HTTPS | Certificado institucional en el gateway o en un proxy frontal | Pendiente de configurar en la infraestructura |
