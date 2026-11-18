# Validación del microservicio Registro (POST) con la base real de Aiven

**Fecha:** 17/11/2026 · **Rama:** `local/docker` (sin commits) · **Escrituras autorizadas por el usuario:** 4 registros sintéticos, más un inicio y un cierre de sesión.

## Verificación previa del código

- Durante las pruebas E2E **no se modificó código funcional**. No hay cambios en `backend/app`, `backend/tests`, `sgsc_ejecutiva/lib` y `test`, `pubspec.yaml`, `render.yaml`, `iniciar.ps1`, los `requirements` ni las migraciones.
- Los microservicios, el gateway y la configuración Docker son del 16/11, antes de las E2E.
- Lo creado a partir de las E2E son solo scripts de `pruebas/microservicios/e2e/`, evidencias e informes.

## Endpoint revisado

`POST /ejecutivo/solicitudes` en el servicio **registro**, que usa `sgsc_registro/registration.py`, copia literal de `app/services/ssnl_registration.py`.

- **Validaciones:**
  - Pydantic con `extra='forbid'`; los catálogos deben estar activos.
  - Los municipios deben pertenecer a la entidad del usuario, y la colonia, a su municipio.
  - Debe existir el estatus «Inicio».
- **Transacción única:**
  1. `Tbl_Beneficiarios` (si es nuevo)
  2. `Tbl_Solicitantes` (si es nuevo)
  3. `Tbl_SolicitudesApoyo` (estatus «Inicio», `createdBy` = usuario)
  4. `ejecutivo_registro` (solicitud, usuario y clave)
  5. Un solo `COMMIT`.
- **Idempotencia:**
  - Antes de escribir, busca la clave del usuario y, si ya existe, devuelve el mismo folio.
  - La base lo garantiza con el índice único `uq_registro_reintento (usuario_id, idempotencia)`, con reintento ante `IntegrityError`.
  - La CURP del beneficiario es única; la prueba la deja vacía.

## Datos sintéticos utilizados

Ninguno corresponde a una persona:

| | |
|---|---|
| Beneficiario | «PRUEBA E2E SGSC / REGISTRO SINTETICO 17NOV2026», sin CURP, 2000-01-01, Monterrey, colonia «Centro» (CP 64000) |
| Solicitante | «PRUEBA E2E SGSC / SOLICITANTE SINTETICO», «El mismo / Ella misma», mismo domicilio, teléfono 0000000000 |
| Solicitud | «Peticiones Administrativas», origen «Otro», canal y unidad «No especificado», descripción «[PRUEBA AUTOMATIZADA SGSC – NO ATENDER] …» |
| Clave de idempotencia | La generó la app: `a367de33-41e8-46e2-b404-646b8b7160a1` |

## Resultados

| # | Prueba | Esperado | Obtenido | Estado |
|---|---|---|---|---|
| R01 | Formulario Flutter de 8 pasos (Playwright, Chrome real) | Avanzar los 7 pasos y mostrar la revisión | 7/7 pasos; la revisión muestra los datos sintéticos; listas dependientes servidas por registro (`municipios-nacimiento`, `colonias`, 200) | ✅ |
| R02 | POST desde Flutter por el gateway | 201 desde **registro** con folio | **201**, `X-SGSC-Service: registro`, «**Solicitud #581**» (Nginx: upstream registro, 1.19 s) | ✅ |
| R03 | Folio válido | «Solicitud #id» igual al id persistido | `solapoyo_id = 581` | ✅ |
| R04 | Persistencia | +1 en cada tabla, en una transacción | 563→**564**, 75→**76**, 82→**83**, 553→**554** | ✅ |
| R05 | Integridad de relaciones | Solicitud → beneficiario y solicitante; registro → solicitud; mismo autor | 581 → beneficiario 88 y solicitante 100; `ejecutivo_registro` 581; `createdBy` igual en las 4 tablas; estatus «Inicio»; domicilio copiado al solicitante | ✅ |
| R06 | Segundo envío con la **misma clave** (por el gateway, mismo cuerpo) | Mismo folio, sin duplicados | **201**, «Solicitud #581»; 1 sola fila con la clave; 1 solo beneficiario, solicitante y solicitud sintéticos; conteos sin cambio (Nginx: 0.21 s) | ✅ |
| R07 | Errores en Nginx y Registro | Ninguno | 2 POST con 201 y 0 errores 5xx o *tracebacks* | ✅ |
| R08 | Reflejo en Flutter | El tablero incluye la nueva solicitud | Pantalla y API: **564** (231 activas); igual al monolito (3/3) | ✅ |
| E06 | Repetición de la comparación de periodos | Aserciones de la prueba E2E | Comparación desde **indicadores**: 3 periodos (4, 13, 6), variaciones correctas, filtro conservado; paridad 5/5 con el monolito | ✅ (repetida) |
| E12 | Cierre de sesión | Token revocado | Logout 200; `/auth/me` y `/ejecutivo/dashboard` → 401 | ✅ |

**Total: 10 de 10 aprobadas · 0 fallidas · 0 pendientes de esta etapa.**

## Cómo quedan los datos de prueba

- Permanecen en Aiven: la solicitud **#581** (estatus «Inicio»), el beneficiario **88**, el solicitante **100** y su fila en `ejecutivo_registro`.
- Aparecen en el tablero (564), en los reportes y en la vista SSNL, identificados por «PRUEBA E2E SGSC» y «[PRUEBA AUTOMATIZADA SGSC – NO ATENDER]».
- SGSC no tiene un mecanismo para retirarlos. Retirarlos requiere autorización aparte, con una de dos opciones:
  - borrar esas 4 filas por su id;
  - cambiar el estatus de la 581 a «Cerrado / Cancelado» desde SSNL.
- Ya existía un beneficiario «PRUEBA…» anterior; no se tocó.

## Evidencias

- `evidencias/registro_post_flutter.json`: pasos, cuerpo sintético enviado, respuestas y peticiones.
- `evidencias/registro_post_verificacion.json`: SELECT de verificación.
- `evidencias/registro_post_conteos_antes.txt`: conteos previos.
- `evidencias/registro_post_logs.txt`: Nginx y registro.
- `evidencias/registro_post_tablero_y_cierre.json`: tablero en 564 y cierre de sesión.
- `evidencias/e2e_e06_repeticion.json`: repetición de E06.
- Scripts: `e2e/r01_registro.py` y `e2e/registro_d*.py`.

Ningún archivo contiene tokens, contraseñas ni datos de personas reales.

## Conclusión

**Registro funciona con la arquitectura de microservicios:**
- El formulario Flutter llega por Nginx al microservicio registro.
- Escribe en Aiven de forma transaccional, con folio válido y relaciones íntegras.
- Es idempotente: el reenvío con la misma clave devuelve el mismo folio sin duplicar.
- No hubo errores.
