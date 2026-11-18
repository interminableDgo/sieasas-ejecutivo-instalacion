# Pruebas de los microservicios del Ejecutivo

Comprueban que los cuatro microservicios de la Figura 53 (Indicadores y Filtros, Detalle de Indicadores, Registro Ejecutivo, y Reportes y Exportación) están desacoplados y conservan el comportamiento del monolito.

## 1. Sin Docker ni base de datos

```powershell
.\pruebas\microservicios\ejecutar_pruebas_locales.ps1          # -Recrear vuelve a crear los entornos
```

Cada suite corre en su propio entorno virtual (`.venv` dentro de su carpeta, ignorado por git), con las variables `DB_*` apuntando a un servidor inexistente. Así ninguna prueba llega a Aiven.

| Suite | Qué demuestra |
|---|---|
| `sgsc_common` | Contrato de filtros y agregados, validación de sesión de solo lectura (token opaco, rol Ejecutivo, entidad), cabeceras, 503 ante fallas de MySQL, `/health`, CORS sin el patrón de Netlify y documentación desactivada |
| `indicadores`, `detalle`, `registro`, `reportes` | Rutas, 401 sin sesión, 422 con parámetros inválidos, alcance por entidad y reglas de negocio. Cada servicio se instala **solo** con sus dependencias y la librería: si sus pruebas pasan, no necesita el monolito ni otro servicio. `test_isolation.py` además rechaza imports de `app`, de otro `sgsc_*` y de clientes HTTP |
| `gateway` | Simula la selección de `location` de Nginx sobre `gateway/nginx.conf`: cada una de las 16 rutas que usa Flutter (extraídas de `sgsc_ejecutiva/lib`) llega a su servicio; el `/ejecutivo/` final no oculta las regex; `/ciudadano`, `/docs` y rutas desconocidas responden 404; el registro de accesos no guarda consultas (tokens) |
| `paridad_codigo` | Mientras Render use el monolito, la lógica copiada es **textualmente idéntica** a la de `backend/app`, y cada endpoint del Ejecutivo existe en exactamente un servicio con el mismo contrato OpenAPI (método, parámetros, cuerpo, respuestas) |
| `monolito` | `backend/tests` sin cambios: Render no se afecta |

Los resultados quedan en `evidencias/`.

## 2. Con los contenedores

Requisitos: Docker con Compose v2 (en Windows: virtualización habilitada, WSL 2 y Docker Desktop). Ejecutado y aprobado en Docker Desktop 4.99 contra Aiven: ver `evidencias/`.

```powershell
cd sgsc_ejecutiva; flutter build web --dart-define=API_BASE_URL=http://localhost:8080; cd ..
docker compose --env-file backend/.env up -d --build
docker run --rm -v ${PWD}/gateway/nginx.conf:/etc/nginx/conf.d/default.conf:ro nginx:1.27-alpine nginx -t
foreach ($s in 'indicadores','detalle','registro','reportes') { docker build -f backend/services/$s/Dockerfile --target test backend }
```

Solo lectura (el token se obtiene iniciando sesión en la app; las pruebas no llaman a `/auth/login` porque escribe en la base):

```powershell
$env:GATEWAY_URL = 'http://localhost:8080'; $env:SGSC_TEST_TOKEN = '<token>'
python -m pytest pruebas/microservicios/integracion/test_gateway.py -q     # enrutamiento real, 401, 404, health
$env:MONOLITO_URL = 'http://127.0.0.1:8000'                                  # iniciar.ps1 en paralelo
python -m pytest pruebas/microservicios/integracion/test_paridad.py -q     # mismo JSON y mismo Excel que el monolito
.\pruebas\microservicios\independencia.ps1                                 # detener o reconstruir uno no afecta a los demás
```

`independencia.ps1` verifica lo siguiente:

- Con cada servicio detenido, los otros tres siguen respondiendo y el suyo devuelve 503. En particular, la exportación sigue funcionando sin Indicadores.
- `up --no-deps --build detalle` no reinicia los demás contenedores.
- Solo el gateway publica puertos.
- Ninguna imagen contiene `.env` ni certificados.
- Los microservicios no reciben las variables SMTP ni `AUTH_ENCRYPTION_KEY`.

## 3. Entorno sin base de datos real (offline)

Genera, a partir de `docker-compose.yml` y sin modificarlo, un Compose independiente cuyos servicios apuntan a un MySQL ficticio (`db.invalid`). Sirve para probar el gateway, el enrutamiento, la independencia y los 503 sin tocar ninguna base:

```powershell
python pruebas/microservicios/offline/generar_offline.py     # escribe offline/salida/ (ignorada por git)
python pruebas/microservicios/offline/verificar_offline.py   # sale con 1 si encuentra .env, ca.pem o Aiven
docker compose -p sgsc-offline -f pruebas/microservicios/offline/salida/compose.offline.yml `
  --env-file pruebas/microservicios/offline/salida/offline.env up -d --build
```

Usa la misma subred y el mismo puerto 8080 que la pila normal: detén una antes de iniciar la otra. Copia la compilación de Flutter en `offline/salida/web/` si quieres abrir la interfaz.

## 4. Recorridos en el navegador (`e2e/`)

Scripts de Playwright que controlan un Chrome **visible** por CDP (`127.0.0.1:9223`) con la app abierta en `http://localhost:8080`. Flutter web dibuja en canvas, así que se usan los controles del árbol de accesibilidad. Nunca imprimen ni guardan el token ni las credenciales.

```powershell
python -m pip install playwright
& "C:\Program Files\Google\Chrome\Application\chrome.exe" --remote-debugging-port=9223 --user-data-dir="$env:TEMP\sgsc-e2e" http://localhost:8080
python pruebas/microservicios/e2e/e01_login.py salida_login.json        # espera el inicio de sesión manual (o SGSC_E2E_CORREO / SGSC_E2E_CLAVE)
python pruebas/microservicios/e2e/e2e_recorrido.py salida.json descargas  # tablero, filtros, detalle, exportación y cierre de sesión
python pruebas/microservicios/e2e/r01_registro.py salida_registro.json 8  # llena el formulario hasta el paso 8 SIN enviar
```

- `r01_registro.py … enviar` sí registra una solicitud sintética y prueba la idempotencia: **escribe en la base**.
- `SGSC_HIJOS` elige la respuesta a «¿Tiene hijos?» (`No` por omisión, o una cantidad).
- `registro_d1…d4_*.py` son consultas de solo lectura dentro del contenedor `registro` (índices, catálogos y conteos antes y después, verificación del registro).
- Los resultados están en `INFORME_E2E_FLUTTER.md` e `INFORME_REGISTRO_POST.md`.

## 5. Requieren autorización expresa (escriben en Aiven)

- Iniciar sesión, porque escribe en `ejecutivo_token`, `ejecutivo_limite` y `ultimo_acceso`.
- Registrar una solicitud por el gateway (dos veces con la misma `idempotencia` debe devolver el mismo folio).
- `RUN_DB_TESTS=1`.
- Recuperación de contraseña.
