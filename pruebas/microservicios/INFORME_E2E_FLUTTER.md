# Pruebas end-to-end: Flutter → Nginx → microservicios → Aiven

**Fecha:** 17/11/2026 · **Rama:** `local/docker` (sin commits) · **Base de datos:** Aiven real (MySQL 8.4, TLS 1.3)

## Cómo se ejecutó

- **Navegador real:** Chrome 157 visible, con un perfil temporal y controlado por Playwright 1.65 (Python) mediante CDP en `127.0.0.1:9223`. Las acciones son clics y teclado reales sobre la app Flutter web servida por el gateway en `http://localhost:8080`. **No se llamaron funciones de Python** para validar la interfaz.
- **Árbol de accesibilidad:** Flutter dibuja en un `canvas`. Los controles se localizan por su árbol de accesibilidad: rol y nombre de botones, celdas, campos y casillas.
- **Comprobación del recorrido:**
  - La cabecera `X-SGSC-Service` de cada respuesta que recibe la app.
  - El registro de acceso de Nginx, donde la IP del contenedor que atendió cada petición identifica al servicio.
- **Datos:** valores existentes en la base real (municipio *Hidalgo*, periodo 2025, folios tomados del listado). No se inventaron identificadores.
- **Seguridad:**
  - El inicio de sesión lo hizo el usuario en la ventana visible.
  - El token se tomó de los encabezados de la propia app y se usó **solo en memoria** para la paridad. No se imprimió, guardó ni registró.
  - No hubo trazas, videos ni HAR de Playwright.
  - El registro de Nginx no guarda la parte de consulta de las URL.
  - Escrituras en Aiven: solo inicio y cierre de sesión (autorizadas). **Ningún POST de Registro** (verificado en Nginx: 0).
- **Scripts:** `pruebas/microservicios/e2e/` (`e01_login.py`, `e2e_recorrido.py`, `e2e_comun.py`).
- **Evidencias:** `evidencias/e2e_flutter_*.json`.

## Resultados de la corrida final (oficial)

**11 de 12 escenarios aprobados (91.7 %) · 1 fallido · 0 omitidos**

| # | Escenario | Resultado esperado | Resultado obtenido | Estado | Microservicio · HTTP · tiempo |
|---|---|---|---|---|---|
| E01 | Inicio de sesión (2FA si aplica) | Sesión válida y tablero cargado | Login 200 en el primer intento; la cuenta no tiene 2FA; tablero, listado y catálogos cargados | ✅ Aprobada | núcleo `POST /auth/login` 200 · 1404 ms; indicadores, detalle |
| E02 | Tablero e indicadores | Pantalla = API; estatus y municipios suman el total; 12 meses | 563 en pantalla y API; 230 activas, 197 resueltas; suma por estatus 563; suma por municipio 563; 12 meses | ✅ Aprobada | indicadores `GET /dashboard` 200 · 489 ms |
| E03 | Filtro por municipio | Selector = API = pantalla = listado | Hidalgo: 23 = 23 = 23 = 23; `municipio_id` en la petición | ✅ Aprobada | indicadores 200 · 437 ms; detalle 200 · 246 ms |
| E04 | Filtro por periodo | Fechas en la petición; tendencia de ene a dic 2025; pantalla = API | `2025-01-01..2025-12-31`; 204 en pantalla y API; tendencia 2025-01..2025-12 | ✅ Aprobada | indicadores 200 · 462 ms; detalle 200 · 260 ms |
| E05 | Combinación de filtros | Ambos filtros; total ≤ cada filtro por separado | 13 (municipio solo 23, periodo solo 204); solo Hidalgo en la respuesta | ✅ Aprobada | indicadores 200 · 440 ms; detalle 200 · 246 ms |
| E06 | Comparación de dos periodos | ≥2 periodos y variaciones correctas | **No se ejecutó la aserción:** la automatización no encontró el botón «Meses» después de abrir la comparación | ❌ Fallida (automatización) | — |
| E07 | Navegación del indicador al detalle | Pulsar «Hidalgo» filtra el listado y el tablero igual | Listado 23, mismo `municipio_id` en ambas peticiones, pestaña «Solicitudes (23)» | ✅ Aprobada | detalle 200 · 247 ms; indicadores 200 · 441 ms |
| E08 | Listado, paginación y ordenamiento | Cambio de página de uno en uno; orden aplicado en el servidor | Página 0→1, 10 filas, total 23; orden por folio ascendente y verificado | ✅ Aprobada | detalle 200 · 251 ms y 242 ms |
| E09 | Búsqueda y apertura de una solicitud | Folio sugerido y listado; abrir trae su detalle | Folio en sugerencias y en el listado filtrado; abierta «Solicitud #5»; detalle con 16 campos | ✅ Aprobada | detalle (sugerencias 346 ms, listado 242 ms, detalle 204 ms) |
| E10 | Exportación Excel | Archivo = respuesta; filtros en la petición y en el reporte; total = tablero | Descargado 25 KB, idéntico a la respuesta; 6 hojas; total 13 = tablero; municipio y periodo en el reporte | ✅ Aprobada | reportes `GET /exportar/xlsx` 200 · 2957 ms |
| E11 | Exportación PDF | Archivo = respuesta; municipio, periodo y total en el texto | Descargado 18 KB, idéntico; contiene «Hidalgo», «2025-01-01 al 2025-12-31» y el total 13 | ✅ Aprobada | reportes `GET /exportar/pdf` 200 · 1623 ms |
| E12 | Cierre de sesión y revocación | Logout 200; el mismo token da 401; vuelve al login | Logout 200; `/auth/me` 401; `/ejecutivo/dashboard` 401 (indicadores); pantalla de login | ✅ Aprobada | núcleo `POST /auth/logout` 200 · 293 ms |

**Sobre E06.** En la corrida final no se ejecutó la aserción, así que **no se cuenta como aprobada**. Antecedentes:
- En las seis corridas de depuración anteriores (sesión anterior, sin cierre de sesión, mismas aserciones), E06 obtuvo `GET /ejecutivo/comparacion` 200 desde **indicadores**: 3 periodos por año (4, 13 y 6), variaciones correctas y filtro de municipio conservado. Sus respuestas también fueron idénticas a las del monolito.
- La causa de esta falla es el desplazamiento automático hasta el botón «Meses» en una sesión recién iniciada. **No es un error de la app.**
- Queda pendiente repetirlo, lo que requiere un nuevo inicio de sesión.

## Verificación por Nginx (ventana de la corrida final)

| Ruta | Servicio que atendió | Peticiones | Códigos | ms promedio |
|---|---|---|---|---|
| `POST /auth/login` | núcleo | 1 | 200 | 1401 |
| `GET /ejecutivo/dashboard` | indicadores | 15 | 200 (14) y 401 (1, verificación de revocación) | 467 |
| `GET /ejecutivo/catalogos` | indicadores | 1 | 200 | 1322 |
| `GET /ejecutivo/solicitudes` | detalle | 20 | 200 | 285 |
| `GET /ejecutivo/solicitudes/sugerencias` | detalle | 1 | 200 | 345 |
| `GET /ejecutivo/solicitudes/{id}` | detalle | 1 | 200 | 203 |
| `GET /ejecutivo/exportar/xlsx` | reportes | 1 | 200 | 2955 |
| `GET /ejecutivo/exportar/pdf` | reportes | 1 | 200 | 1620 |
| `POST /auth/logout` | núcleo | 1 | 200 | 291 |
| `GET /auth/me` | núcleo | 1 | 401 (token revocado) | 202 |

- **Rutas del Ejecutivo atendidas por el núcleo: 0.** Flutter usa los microservicios para todas las funciones migradas; solo la autenticación pasa por el núcleo.
- **POST de Registro: 0.**
- **Errores de consola del navegador: 0.**

## Paridad HTTP con el monolito (Aiven, mismo token en memoria)

Cada GET que hizo la app a través del gateway se repitió contra el monolito original (`127.0.0.1:8000`) con el mismo token:

| Ruta | Respuestas idénticas |
|---|---|
| `/ejecutivo/dashboard` | 6/6 |
| `/ejecutivo/solicitudes` | 8/8 |
| `/ejecutivo/solicitudes/sugerencias` | 1/1 |
| `/ejecutivo/solicitudes/{id}` | 1/1 |
| `/ejecutivo/exportar/xlsx` | 1/1 (celdas; se excluye solo la celda B6 de cada hoja: fecha y hora de generación) |
| `/ejecutivo/exportar/pdf` | 1/1 (texto; se excluye solo la fecha y hora de generación) |
| **Total** | **18/18** (mismo código HTTP y mismo JSON o contenido) |

**Diferencias con el monolito:** ninguna en datos, totales, estructura ni códigos.

Diferencias esperadas por diseño:
- La cabecera `X-SGSC-Service`.
- La fecha y hora de generación de los reportes.

## Hallazgos durante la automatización (no son errores de SGSC)

1. Flutter expone en el árbol de accesibilidad solo lo que está en pantalla, y el clic sintético no siempre llega al control. Se resolvió desplazando la vista y haciendo clic real del ratón en el centro visible del control.
2. La tabla de solicitudes se desplaza en horizontal: la caja de cada fila excede el área visible, así que hay que pulsar la celda del folio.
3. Flutter fusiona el buscador de solicitudes con su contenedor; se enfoca el campo por programación.
4. La app conserva la página del listado y el modo de comparación entre acciones. Las pruebas lo contemplan.
5. Con un periodo activo, la comparación envía `fecha_inicio` y `fecha_fin`, y el backend los reemplaza por los periodos comparados, como está diseñado.

## Actualización (17/11/2026, sesión del Registro)

- **E06 repetido y APROBADO** en una ejecución real (E03 + E06):
  - `GET /ejecutivo/comparacion` 200 desde **indicadores**;
  - 3 periodos (4, 13, 6) con variaciones correctas;
  - filtro de municipio conservado;
  - paridad 5/5 con el monolito.
  - Evidencia: `evidencias/e2e_e06_repeticion.json`.
- Con eso, los 12 escenarios de consulta quedaron aprobados en ejecuciones reales. El resultado de la corrida final de arriba (E06 fallido por la automatización) se conserva como registro histórico.
- **Registro (POST)** validado: ver `INFORME_REGISTRO_POST.md`.
