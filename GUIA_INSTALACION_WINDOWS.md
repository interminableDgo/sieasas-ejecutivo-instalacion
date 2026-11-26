# Instalación en Windows Server sin internet (SIESAS · Ejecutivo)

El servidor que asignó la Secretaría es **Windows Server 2019 Standard** (64 bits, 2 × Intel Xeon Gold 6234, 192 GB de RAM) y **no tiene internet**. Windows Server 2019 no ejecuta los contenedores Linux de `docker-compose.yml`, así que en él la aplicación se instala **sin Docker**:

| Con Docker (Linux, [guía](GUIA_DESPLIEGUE_INSTITUCIONAL.md)) | En Windows Server (esta guía) |
|---|---|
| Gateway Nginx + núcleo + 4 microservicios en 6 contenedores | La API completa en un solo proceso de Python (`backend/app`, el monolito) |
| Docker reinicia los contenedores | Tarea programada **«SIEASAS API»**: arranca con el servidor y reinicia la API si termina (`windows/api.ps1`) |
| Nginx sirve Flutter web y reparte `/auth`, `/ejecutivo` y `/health` | **IIS** con URL Rewrite y ARR hace lo mismo (`windows/web.config`) |

> **Estado.** Los scripts se revisaron (sintaxis, XML y paso de argumentos en Windows PowerShell 5.1) y el paquete se comprobó: las librerías se instalan sin internet y la API carga sus 20 rutas. **Falta ensayar `instalar.ps1` completo** en un Windows Server 2019 sin internet (por ejemplo, una máquina virtual) antes del día de la instalación.

## 1. Datos que debe proporcionar la Secretaría

| Dato | Para qué |
|---|---|
| Dominio (p. ej. `sieasas.<dominio institucional>`) y su certificado HTTPS instalado en el servidor | Compilar la app, `RESET_URL`, `CORS_ORIGINS` y el enlace 443 de IIS |
| Cómo llegan los celulares al servidor: publicado a internet por TI, solo red interna o VPN | Que los ejecutivos puedan usar la app |
| MySQL: servidor, puerto, base con el esquema **SSNL**, usuario y certificado `ca.pem` si usa TLS | `backend/.env` y `migrate` |
| Privilegios del usuario de MySQL: `SELECT`, `INSERT`, `UPDATE`, `DELETE`, `CREATE`, `ALTER`, `INDEX`, `REFERENCES` | La instalación agrega 5 catálogos y 2 columnas (README §11.1) |
| SMTP **interno** (servidor, puerto, usuario, contraseña, remitente) | Recuperación de contraseña |
| Quién respalda la base: TI, o el script con `mysqldump` | Paso 4 |
| Permiso para instalar Python 3.12, URL Rewrite 2.1 y ARR 3.0 | Requisitos |
| ¿La base ya tiene el catálogo de colonias? | Si no, se incluye `CPdescarga.txt` de SEPOMEX |
| Lista de ejecutivos: nombre, apellidos, correo y estado | `manage.py create-user` |

## 2. Armar el paquete (en un equipo con internet)

1. Compilar la app con el dominio real (en el equipo con Flutter):
   ```powershell
   cd sgsc_ejecutiva
   flutter build web --release --dart-define=API_BASE_URL=https://<dominio>
   ```
2. Armar el paquete (requiere Python 3.12):
   ```powershell
   .\windows\armar_paquete.ps1 -Web .\sgsc_ejecutiva\build\web -Colonias <ruta>\CPdescarga.txt
   ```
   Genera `paquete_sieasas\` y `paquete_sieasas.zip` (~60 MB) junto a la carpeta del repositorio:

   | Carpeta | Contenido |
   |---|---|
   | `codigo\` | El repositorio, sin `.env`, `ca.pem`, entornos ni compilados |
   | `web\` | La app compilada |
   | `librerias\` | Librerías de Python para Windows x64 y Python 3.12 |
   | `instaladores\` | Python 3.12.10, URL Rewrite 2.1 y ARR 3.0 (se verifica su firma digital) |
   | `CPdescarga.txt` | Catálogo de SEPOMEX, si se indicó |
   | `LEEME.txt`, `SHA256SUMS.txt` | Pasos resumidos y sumas para comprobar el traslado |

   El script comprueba que las librerías se instalan sin internet y que la API carga.

## 3. Instalar en el servidor

1. Copiar el paquete al servidor (por ejemplo a `C:\SIEASAS`) y comprobar las sumas de `SHA256SUMS.txt` si se trasladó por USB.
2. Copiar `codigo\backend\.env.example` a `codigo\backend\.env` y llenarlo: `DB_*`, `CORS_ORIGINS` y `RESET_URL` con `https://<dominio>`, y `SMTP_*`. Copiar el `ca.pem` de MySQL y apuntar `DB_SSL_CA` a él. `AUTH_ENCRYPTION_KEY` puede quedar vacía: el script la genera.
3. En PowerShell **como administrador**:
   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass
   C:\SIEASAS\codigo\windows\instalar.ps1 -SinRespaldo        # si TI ya respaldó la base
   # o bien: -MySqlDump 'C:\ruta\mysqldump.exe' para que el script haga el respaldo
   # con el certificado ya instalado: -Certificado <huella> -Dominio <dominio>
   ```

`instalar.ps1` ejecuta nueve pasos y se detiene con un mensaje claro si algo falta. Se puede volver a ejecutar: cada paso revisa lo que ya existe.

| Paso | Qué hace |
|---|---|
| 1. Requisitos | Administrador; instala Python 3.12 del paquete si falta; revisa `.env`, el certificado de MySQL y la app web; genera `AUTH_ENCRYPTION_KEY` si falta; deja `.env` legible solo por administradores y SYSTEM |
| 2. Entorno de Python | Crea `backend\.venv` e instala las librerías desde `librerias\` |
| 3. Conexión | Prueba MySQL y que la base tenga las tablas de SSNL |
| 4. Respaldo | `mysqldump` completo a `backend\respaldos\`, o se omite con `-SinRespaldo` |
| 5. Base | `manage.py migrate`: 5 catálogos y 2 columnas; repetible |
| 6. Colonias | `manage.py cargar-colonias` si el paquete trae `CPdescarga.txt` |
| 7. API | Registra y arranca la tarea «SIEASAS API» como SYSTEM: uvicorn en `127.0.0.1:8000` con 2 procesos; bitácora en `backend\logs\api.log` |
| 8. IIS | Instala las funciones de IIS, URL Rewrite y ARR del paquete; activa el proxy de ARR (2 minutos para exportaciones); crea el sitio «SIEASAS» en `C:\inetpub\sieasas` (puerto 8080 por omisión) con `web.config`; quita la consulta de la bitácora de IIS para no guardar el token de recuperación |
| 9. Verificación | `/health` y `/health/db` directo y a través de IIS, y la página principal |

4. **HTTPS:** si no se usó `-Certificado`, TI agrega al sitio «SIEASAS» el enlace 443 con el certificado del dominio.
5. **Ejecutivos:** uno por uno,
   ```powershell
   cd C:\SIEASAS\codigo\backend
   .venv\Scripts\python manage.py create-user --correo CORREO --nombres NOMBRES --apellidos APELLIDOS --entidad 19
   ```
6. **Prueba en un celular:** iniciar sesión, ver el tablero, registrar una solicitud, exportar y recuperar la contraseña.

## 4. Operación

- **Estado de la API:** `Get-ScheduledTask -TaskName 'SIEASAS API'` y `backend\logs\api.log`.
- **Reiniciar la API:** `Stop-ScheduledTask 'SIEASAS API'; Start-ScheduledTask 'SIEASAS API'`.
- **Actualizar:** armar un paquete nuevo, respaldar la base y `backend\.env`, reemplazar `codigo\` (conservando `.env`, `ca.pem` y `.venv`) y volver a ejecutar `instalar.ps1`.
- **Desinstalar:** `Unregister-ScheduledTask 'SIEASAS API'`, quitar el sitio y el grupo de aplicaciones «SIEASAS» de IIS y borrar la carpeta. Los cambios en la base son aditivos (README §11.1).

## 5. Diferencias con el gateway Nginx

- IIS no limita las peticiones a `/auth/login` como Nginx (30 por minuto). La API conserva su propio límite: 30 intentos por IP y 6 por cuenta cada 15 minutos (`app/security.py`). Para que cuente la IP real del celular, ARR envía `X-Forwarded-For` sin el puerto y uvicorn lo lee (`--proxy-headers`, solo desde 127.0.0.1). Si TI lo requiere, se puede agregar *Dynamic IP Restrictions* de IIS.
- `/health/indicadores`, `/health/detalle`, `/health/registro` y `/health/reportes` no existen: con un solo proceso basta `/health/db`.
- La API corre como SYSTEM. Si la política de TI lo exige, se puede cambiar la cuenta de la tarea a una cuenta de servicio con permiso de lectura sobre `codigo\` y escritura sobre `backend\logs\`.
