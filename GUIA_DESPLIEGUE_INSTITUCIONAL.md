# Guía de despliegue institucional de SGSC (SIESAS · Ejecutivo)

Esta guía explica cómo montar SGSC en un servidor de la Secretaría de Salud de Nuevo León, desde un servidor vacío hasta tener la aplicación del Ejecutivo funcionando.

Sobre la base de datos se complementa con [`docs/MIGRACION_INFRAESTRUCTURA.md`](docs/MIGRACION_INFRAESTRUCTURA.md): las referencias «Migración §N» apuntan a ese documento.

> **Estado.** La arquitectura se probó **localmente**: Windows 11, Docker Desktop 4.99 con WSL 2, y MySQL 8.4 en Aiven. **No se ha desplegado** en un servidor institucional, con HTTPS, con una base institucional ni con usuarios de privilegios mínimos. Esta guía **no** declara el sistema listo para producción: indica qué falta validar.

Leyenda: ✅ probado localmente · ⏳ pendiente de validar en la infraestructura institucional · ❓ decisión que debe confirmar la Secretaría o TI.

---

## 1. Requisitos previos

| Requisito | Detalle | Estado |
|---|---|---|
| Servidor de aplicación | Linux x86-64 con Docker Engine y Docker Compose v2 o posterior. Las imágenes son Linux (`python:3.12-slim`, `nginx:1.27-alpine`). Windows con Docker Desktop solo se probó para desarrollo. | ✅ en Docker Desktop · ⏳ en servidor Linux · ❓ SO y si se permite Docker |
| Recursos orientativos | 2 vCPU, 4 GB de RAM y 20 GB de disco para seis contenedores, imágenes y bitácoras. Es una estimación; no se midió con carga. | ⏳ |
| Base de datos | MySQL 8.x con el esquema **SSNL** y las migraciones de SGSC (Migración §3–§7) | ✅ MySQL 8.4.11 (Aiven) · ⏳ institucional |
| Dominio y certificado HTTPS | Por ejemplo `sgsc.<dominio institucional>`, con su certificado | ❓ |
| Correo SMTP | Para recuperar contraseñas | ✅ con el SMTP actual · ❓ institucional |
| Equipo de compilación | Flutter SDK (canal estable) para generar `sgsc_ejecutiva/build/web`. Puede ser otro equipo; solo se copia la carpeta resultante. | ✅ |
| Acceso al repositorio | Rama `dev` del repositorio GitHub del proyecto | ✅ |

## 2. Inventario de servicios

| Contenedor | Imagen | Función | Rutas que atiende | Puerto |
|---|---|---|---|---|
| `gateway` | `sgsc-gateway` (Nginx 1.27) | Punto único de entrada: sirve Flutter web y reparte las peticiones | `/`, `/ejecutivo/*`, `/auth/*`, `/health*` | **El único publicado**: `127.0.0.1:${GATEWAY_PORT:-8080}` → 80 |
| `nucleo` | `sgsc-nucleo` (FastAPI, `backend/app`) | Inicio de sesión, segundo factor, recuperación, perfil y solicitud de acceso | `/auth/*`, `/health`, `/health/db` | Interno 8000 |
| `indicadores` | `sgsc-indicadores` | Tablero, comparación de periodos y catálogos de filtros | `/ejecutivo/dashboard`, `/comparacion`, `/catalogos` | Interno 8000 |
| `detalle` | `sgsc-detalle` | Listado filtrado y detalle de una solicitud | `GET /ejecutivo/solicitudes`, `/ejecutivo/solicitudes/{id}` | Interno 8000 |
| `registro` | `sgsc-registro` | Nueva solicitud y búsquedas del formulario | `POST /ejecutivo/solicitudes`, `/personas`, `/colonias`, `/municipios-nacimiento` | Interno 8000 |
| `reportes` | `sgsc-reportes` | Exportación a Excel y PDF | `/ejecutivo/exportar/{xlsx,pdf}` | Interno 8000 |

- Todos los contenedores están en la red interna `sgsc` (`172.30.0.0/24`; el gateway usa `172.30.0.10`) y se conectan **directamente** a MySQL. No se llaman entre sí.
- Si un microservicio se detiene, solo sus rutas responden 503 ✅ (`pruebas/microservicios/independencia.ps1`).
- **No incluidos:**
  - el prototipo **Ciudadano**: el gateway responde 404 en `/ciudadano/*`;
  - el administrador PHP/Yii 2 de SSNL;
  - la base de datos (Migración, sección «Sustitución de Render, Netlify y Aiven»).

## 3. Preparación del servidor

1. Instalar el sistema operativo aprobado por TI y aplicar sus actualizaciones de seguridad ❓.
2. Crear un usuario de servicio sin privilegios de administrador para operar SGSC. Agregarlo al grupo `docker` solo si la política lo permite; si no, usar `sudo` ❓.
3. Sincronizar la hora (NTP). La sesión de 8 horas, los enlaces de recuperación de 30 minutos y el segundo factor (TOTP) dependen de la hora.
4. Crear la carpeta de instalación, por ejemplo `/opt/sgsc`, con permisos solo para el usuario de servicio.

## 4. Instalación de dependencias

1. **Docker Engine y el complemento Compose**, siguiendo el procedimiento oficial de Docker para la distribución elegida. Comprobar con `docker version` y `docker compose version`.
2. **git**, para obtener el código.
3. **Flutter**, solo en el equipo donde se compila la app web. No hace falta en el servidor.
4. **Python 3.12**, solo si se ejecutan los comandos de `backend/manage.py` fuera de Docker. Alternativa ⏳: ejecutarlos dentro del contenedor `nucleo` con `docker compose … exec nucleo python manage.py …`; la imagen incluye `manage.py` y sus migraciones, pero esta forma no se ha probado.

```bash
cd /opt/sgsc
git clone --branch dev <url del repositorio> .
```

## 5. Base de datos institucional

Seguir Migración §3 (requisitos), §6 (preparación) y §10 (usuarios). En resumen:

- MySQL 8.x con InnoDB, `utf8mb4` y `utf8mb4_unicode_ci`, un `sql_mode` equivalente, `lower_case_table_names=0` y UTC.
- **El esquema SSNL base lo proporciona la Secretaría**; no está en el repositorio. ❓
- Usuarios: uno de instalación, temporal, y uno de ejecución con privilegios mínimos. ⏳ Hoy todos los servicios usan el mismo usuario.
- Acceso de red a MySQL solo desde el servidor de SGSC.

## 6. Migración o creación del esquema

Con la base SSNL ya importada y un `.env` que apunte a ella con el usuario de instalación:

```bash
cd /opt/sgsc/backend
python3.12 -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/python manage.py migrate                                    # 002, 003, 004 + columnas de colonia
.venv/bin/python manage.py cargar-colonias CPdescarga.txt --estado 19  # catálogo SEPOMEX
.venv/bin/python manage.py create-user --correo persona@salud.nl.gob.mx --nombres Nombre --apellidos Apellido --entidad 19
.venv/bin/python manage.py setup-2fa --correo persona@salud.nl.gob.mx   # opcional
```

- `migrate` es aditiva y está pensada para poder repetirse ✅ (sobre Aiven). Hacer un respaldo antes.
- Si no se usará Ciudadano, ver Migración §7.
- No ejecutar `sgsc_salud_desde_cero.sql` ni `backend/migrations/001_ejecutivo.sql`.
- El archivo de SEPOMEX se descarga del sitio de Correos de México (formato TXT, separado por «|»).
- Si se transfieren datos desde Aiven, solo con autorización: Migración §8 y §9.

## 7. Variables de entorno

```bash
cp backend/.env.example backend/.env
chmod 600 backend/.env
```

Completar según Migración §12:
- `DB_*` con el usuario **de ejecución**;
- `CORS_ORIGINS` y `RESET_URL` con el dominio HTTPS;
- `SMTP_*`;
- `AUTH_ENCRYPTION_KEY`, generada una vez y conservada.

**Variables de Docker Compose**, opcionales. Se leen del mismo archivo, porque se pasa con `--env-file`:

| Variable | Por omisión | Uso |
|---|---|---|
| `GATEWAY_PORT` | `8080` | Puerto del gateway en `127.0.0.1` |
| `GATEWAY_ORIGINS` | `http://localhost:8080,http://127.0.0.1:8080` | `CORS_ORIGINS` de los cuatro microservicios. **Fijarlo al dominio HTTPS.** |
| `FLUTTER_WEB_DIR` | `./sgsc_ejecutiva/build/web` | Carpeta de Flutter que sirve el gateway |
| `MS_DB_POOL_SIZE` / `MS_DB_MAX_OVERFLOW` | `2` / `2` | Conexiones por microservicio |

> `docker compose config` sin `--quiet` imprime las variables ya sustituidas, **incluidas las contraseñas**. Usar siempre `docker compose --env-file backend/.env config --quiet`.

## 8. Certificados

- **CA de MySQL:** copiar el PEM de la CA institucional, o la cadena completa, a `backend/ca.pem` con `chmod 600`. Compose lo monta como secreto en `/run/secrets/db_ca`. El nombre del certificado del servidor debe coincidir con `DB_HOST` (Migración §11).
  - ✅ con la CA de Aiven.
  - ⏳ con una CA institucional.
- **Certificado HTTPS** del dominio: ver §10.
- Ningún certificado ni `.env` entra a git ni a las imágenes ✅ (verificado por `independencia.ps1`).

## 9. Construcción y ejecución de contenedores

1. **Compilar Flutter web** con la dirección pública de la API. Como el gateway sirve la app y la API en el mismo dominio, es la misma dirección:

   ```bash
   cd sgsc_ejecutiva
   flutter build web --dart-define=API_BASE_URL=https://sgsc.<dominio institucional>
   cd ..
   ```

   ✅ con `http://localhost:8080`. Si se compila en otro equipo, copiar `sgsc_ejecutiva/build/web` al servidor o definir `FLUTTER_WEB_DIR`.

2. **Validar la configuración:**

   ```bash
   docker compose --env-file backend/.env config --quiet
   docker run --rm -v "$PWD/gateway/nginx.conf:/etc/nginx/conf.d/default.conf:ro" nginx:1.27-alpine nginx -t
   ```

3. **Construir e iniciar**, y revisar que los seis contenedores queden `healthy`:

   ```bash
   docker compose --env-file backend/.env up -d --build
   docker compose --env-file backend/.env ps
   ```

4. **Operación habitual:**

   ```bash
   docker compose --env-file backend/.env logs -f --tail 100 registro     # bitácora de un servicio
   docker compose --env-file backend/.env restart detalle                 # reiniciar uno
   docker compose --env-file backend/.env up -d --no-deps --build reportes  # actualizar solo uno
   docker compose --env-file backend/.env stop                            # detener todo
   docker compose --env-file backend/.env down                            # detener y retirar contenedores
   ```

- Los contenedores usan `restart: unless-stopped`: vuelven a iniciar cuando arranca Docker. Habilitar el servicio Docker al inicio del sistema (por ejemplo, `systemctl enable docker`).
- Los servicios Python corren con el usuario no privilegiado `sgsc`.

## 10. Dominio y HTTPS ⏳

El gateway escucha HTTP en el puerto 80 del contenedor y Compose lo publica solo en `127.0.0.1`. Hay dos opciones; **ninguna se ha probado**:

- **A. Proxy o balanceador institucional delante** (recomendada si ya existe). El proxy termina TLS y reenvía a `http://<servidor>:8080`.
  - Cambiar en `docker-compose.yml` el puerto publicado de `127.0.0.1:` a la IP interna que alcanza el proxy, y restringirlo con el firewall.
  - **Adaptación necesaria:** el gateway hoy envía `X-Forwarded-For $remote_addr`, que con un proxy delante sería la IP del proxy. Eso afecta el límite de intentos de inicio de sesión: el de Nginx (`limit_req`) y el del núcleo, que trabajan por IP. Hay que agregar en `gateway/nginx.conf` `set_real_ip_from <IP del proxy>;` y `real_ip_header X-Forwarded-For;`, y probarlo.
- **B. TLS en el propio gateway.**
  - Agregar un bloque `listen 443 ssl;` con `ssl_certificate` y `ssl_certificate_key` montados como volumen de solo lectura (carpeta `gateway/certs/`, ya ignorada por git).
  - Redirigir el puerto 80 a 443 y publicar el 443 en Compose.
  - Agregar `Strict-Transport-Security`.

En ambos casos:
- DNS del dominio institucional ❓;
- `CORS_ORIGINS`, `GATEWAY_ORIGINS` y `RESET_URL` con `https://…`;
- Flutter compilado con esa `API_BASE_URL`.

## 11. Firewall y accesos

| Origen → destino | Puerto | Regla |
|---|---|---|
| Usuarios → proxy o gateway | 443/TCP (80 solo para redirigir) | Permitir desde la red que defina la Secretaría (intranet o Internet) ❓ |
| Servidor SGSC → MySQL | Puerto de MySQL | Permitir **solo** desde el servidor de SGSC |
| Servidor SGSC → SMTP | Puerto SMTP | Permitir |
| Cualquier origen → puertos 8000 de los servicios | — | No están publicados (✅). La red `sgsc` es interna de Docker. |
| Servidor SGSC → `*.aivencloud.com` | — | **Bloquear** después del corte (Migración §15) |
| Administración (SSH) | 22/TCP | Solo desde la red de administración de TI |

Si la subred `172.30.0.0/24` choca con la red institucional, cambiarla en `docker-compose.yml`, junto con la IP del gateway y `FORWARDED_ALLOW_IPS`.

## 12. Validaciones posteriores a la instalación

Sin sesión y sin escribir datos:

```bash
curl -s http://127.0.0.1:8080/nginx-health                        # ok
curl -s http://127.0.0.1:8080/health/db                           # núcleo → MySQL
for s in indicadores detalle registro reportes; do curl -s http://127.0.0.1:8080/health/$s; echo; done
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/ejecutivo/dashboard   # 401 sin sesión
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/docs                  # 404
```

Cada `/health/<servicio>` debe responder `"database":"connected"`.

Con una cuenta Ejecutivo (iniciar sesión **escribe** el token):
- abrir `https://<dominio>`;
- iniciar sesión y revisar tablero, filtros, detalle y exportaciones;
- cerrar sesión.

Las pruebas automatizadas de `pruebas/microservicios/` (§13) se pueden ejecutar desde un equipo con PowerShell y Python que alcance el gateway.

## 13. Pruebas funcionales y de seguridad

| Prueba | Cómo | Estado |
|---|---|---|
| Pruebas unitarias de los cuatro servicios, la librería común, el gateway (tabla de rutas de Nginx), la paridad con el monolito y el monolito | `pruebas/microservicios/ejecutar_pruebas_locales.ps1` (sin base de datos) | ✅ |
| Pruebas dentro de cada imagen | `docker build -f backend/services/<s>/Dockerfile --target test backend` | ✅ |
| Enrutamiento real, 401 y 404 | `pruebas/microservicios/integracion/test_gateway.py` | ✅ (Aiven y entorno offline) |
| Independencia: un servicio caído, reconstruir solo uno, sin puertos ni secretos | `pruebas/microservicios/independencia.ps1` | ✅ (36/36 con Windows PowerShell 5.1) |
| Mismas respuestas que el monolito | `integracion/test_paridad.py` | ✅ |
| Recorrido en Flutter (inicio de sesión, tablero, filtros, detalle, exportación, cierre de sesión) | `pruebas/microservicios/e2e/` (Playwright y Chrome) | ✅ (`INFORME_E2E_FLUTTER.md`) |
| Registro por gateway e idempotencia | `INFORME_REGISTRO_POST.md` (con autorización y datos sintéticos) | ✅ |
| Pruebas de Flutter | `cd sgsc_ejecutiva && flutter analyze && flutter test` | ✅ (76/76) |
| Todo lo anterior contra la base institucional y con HTTPS | Igual | ⏳ |
| Seguridad: escaneo de vulnerabilidades de imágenes y dependencias, configuración TLS, cabeceras, prueba de penetración | Herramientas de TI | ⏳ ❓ |
| Usuarios de base de datos con privilegios mínimos | Migración §10 | ⏳ |
| Carga y concurrencia | No realizada | ⏳ |

## 14. Respaldos y mantenimiento

- **Base de datos:** respaldo diario cifrado y prueba periódica de restauración (Migración §18).
- **Configuración:** respaldar `backend/.env`, `backend/ca.pem`, el certificado HTTPS y `AUTH_ENCRYPTION_KEY` en la bóveda de TI. Los contenedores no guardan datos.
- **Bitácoras:** `docker compose logs`. Configurar rotación en el demonio de Docker (`log-opts` `max-size` y `max-file`) ⏳. El gateway no registra consultas, para no guardar tokens de recuperación.
- **Actualizaciones de seguridad:** reconstruir periódicamente las imágenes con `--pull` para recibir parches de `python:3.12-slim` y `nginx:1.27-alpine`, y revisar las dependencias de `requirements.txt` ❓.
- **Depuración:** `ejecutivo_token` acumula sesiones vencidas. No hay tarea automática de limpieza; TI puede programar `DELETE FROM ejecutivo_token WHERE expira < UTC_TIMESTAMP() - INTERVAL 30 DAY` ⏳.
- **Espacio en disco:** `docker image prune` después de las actualizaciones.

## 15. Actualización del sistema y reversión

**Actualizar:**

```bash
cd /opt/sgsc
git fetch && git log --oneline HEAD..origin/dev        # revisar qué cambia
# respaldo de la base si la versión trae migraciones
git checkout <etiqueta o commit aprobado>
(cd sgsc_ejecutiva && flutter build web --dart-define=API_BASE_URL=https://<dominio>)   # si cambió Flutter
docker compose --env-file backend/.env up -d --build
docker compose --env-file backend/.env ps
```

Después, repetir §12.

Si solo cambió un servicio:

```bash
docker compose --env-file backend/.env up -d --no-deps --build <servicio>
```

Los demás servicios no se reinician ✅.

**Revertir:**
1. `git checkout <commit anterior>`.
2. Volver a compilar Flutter si cambió.
3. `docker compose --env-file backend/.env up -d --build`.
4. Si la versión aplicó migraciones, restaurar el respaldo de la base. Las migraciones actuales son aditivas: una versión anterior funciona con tablas o columnas adicionales.

Se recomienda que TI etiquete cada versión desplegada (`git tag`).

## 16. Responsabilidades y pendientes del equipo de TI

| Tema | Responsable | Estado |
|---|---|---|
| Esquema SSNL base y catálogos | Secretaría, TI | ❓ |
| Servidor, SO, Docker y recursos | TI | ❓ |
| MySQL institucional, usuarios, TLS y respaldos | TI | ⏳ |
| Separar usuarios de base de datos por servicio (cambio en `docker-compose.yml`) | TI con el equipo de desarrollo | ⏳ |
| Dominio, DNS y certificado HTTPS; `real_ip` si hay un proxy delante | TI | ⏳ |
| SMTP institucional y `RESET_URL` | TI | ❓ |
| `CORS_ORIGIN_REGEX` (hoy admite `*.netlify.app`) y `GATEWAY_ORIGINS` | TI | ⏳ |
| Cuentas Ejecutivo iniciales y entidad de cada una | Secretaría | ❓ |
| Transferencia de datos desde Aiven y depuración de datos de prueba | Secretaría (autorización), TI | ❓ |
| Retiro de Render y Netlify, y revocación del usuario de Aiven | Responsables actuales del proyecto | ⏳ |
| Prototipo Ciudadano (fuera del alcance actual) | Secretaría | ❓ |
| Administrador PHP/Yii 2 de SSNL | TI | ❓ |
| Pruebas de seguridad, de carga y de restauración | TI | ⏳ |
| Aviso de privacidad y tratamiento de datos personales (Migración §20) | Jurídico, Transparencia | ❓ |

### Qué está probado y qué falta

**Probado localmente:**
- Seis contenedores con Docker Compose en Docker Desktop (Windows 11 y WSL 2), conectados a MySQL 8.4 en Aiven con TLS verificado.
- El gateway sirve Flutter web y enruta a cada servicio; un servicio caído no afecta a los demás.
- Recorrido completo del Ejecutivo en Flutter: inicio de sesión, tablero, filtros, comparación, detalle, exportación, registro con idempotencia y cierre de sesión.
- Imágenes sin secretos; solo el gateway publica un puerto.

**Pendiente antes de operar en producción:**
- Servidor Linux institucional.
- MySQL institucional con el esquema SSNL.
- HTTPS y dominio, con proxy o TLS en el gateway.
- Usuarios de base de datos con privilegios mínimos.
- SMTP institucional.
- Rotación de bitácoras.
- Pruebas de seguridad, carga y restauración.
- Decisión sobre Ciudadano y el administrador PHP.
- Retiro de Render, Netlify y Aiven.
