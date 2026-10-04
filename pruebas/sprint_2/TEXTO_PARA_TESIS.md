# Texto para tesis — Sprint 2, HU6

Los siguientes apartados están redactados para insertarse en la tesis. Los marcadores de figuras deben sustituirse por las imágenes indicadas al final. Las evidencias corresponden a pruebas aisladas con datos sintéticos; no deben presentarse como resultados operativos de la institución.

## 4.4.5.1 Construcción de la exportación de reportes filtrados

La construcción de la historia de usuario HU6, «Exportar reportes filtrados», se realizó sobre la implementación existente del módulo Ejecutivo de SIESAS. La versión anterior generaba archivos con filas correspondientes a solicitudes individuales. Se modificó este comportamiento para producir un reporte ejecutivo de información agregada en formatos PDF y Excel, conservando el periodo de registro, los filtros seleccionados y el ámbito estatal autorizado del usuario.

El desarrollo mantuvo la arquitectura Flutter–FastAPI–MySQL y reutilizó las consultas del servicio ejecutivo. La información se obtiene de las tablas existentes `Tbl_SolicitudesApoyo` y `Tbl_Beneficiarios`, junto con los catálogos de municipios, tipos de apoyo, dependencias remitentes, grupos vulnerables y estatus de atención. No se incorporaron tablas ni indicadores dependientes de fechas de cierre inexistentes en el esquema.

En Flutter se agregó la selección del periodo de registro al formulario de filtros. Las fechas se conservan como parte de los filtros aplicados y se envían tanto a la consulta del panel y del listado como a la solicitud de exportación. Antes de generar el archivo, la ventana de exportación muestra el periodo y los filtros activos, permite seleccionar PDF o Excel e informa que el contenido consiste en indicadores, gráficas y definiciones, sin nombres de personas ni registros individuales. Durante la generación se deshabilita la acción de descarga para impedir envíos duplicados; ante un error se conserva la selección y se permite reintentar.

[Insertar Figura HU6-C1. Ventana de exportación con el periodo y los filtros aplicados. Captura de una prueba de interfaz con datos sintéticos.]

La ruta `GET /ejecutivo/exportar/{format}` conserva las dependencias de autenticación y consulta, pero deja de invocar el servicio que devuelve solicitudes individuales. En su lugar, obtiene un resumen agregado y lo transforma mediante un conjunto explícito de campos permitidos. Este resumen es la única entrada de los generadores de documentos. El detalle individual continúa disponible dentro de la aplicación mediante su ruta de consulta existente.

```python
# backend/app/routers/executive.py
summary = svc.dashboard(db, user, selected, full_history=True)
report = build_report(summary, user, selected, catalogs(user, db))
content = render_xlsx(report) if format == 'xlsx' else render_pdf(report)
```

El filtrado reutiliza `where_clause`, que aplica obligatoriamente la entidad autorizada y utiliza parámetros enlazados para los valores recibidos. Las opciones de un mismo filtro se combinan como alternativas, mientras que los filtros diferentes deben cumplirse simultáneamente. El periodo utiliza la fecha de registro de la solicitud; la fecha final incluye todo el día mediante una comparación con el inicio del día siguiente.

```python
# backend/app/services/executive_service.py
clauses = ['m.entidad_id=:entidad_id']
params = {'entidad_id': user['entidad_id']}
# Fragmento de la condición de fecha final:
clauses.append('sa.created<DATE_ADD(:fecha_fin, INTERVAL 1 DAY)')
params['fecha_fin'] = selected['fecha_fin']
```

El reporte presenta el total de solicitudes, las solicitudes activas, las resueltas actualmente, las pertenecientes a otros estatus y el porcentaje resuelto respecto del total filtrado. Las solicitudes resueltas corresponden a los estatus «Resuelto» y «Resuelto con observación». El grupo de otros estatus comprende «Cerrado / Cancelado» y «No es competencia». Cuando el total es cero, el porcentaje se identifica como «No aplica» y se presenta un mensaje de ausencia de resultados.

La tendencia mensual agrupa las solicitudes por mes de registro y muestra cuáles de esas solicitudes se encuentran resueltas al momento de consultar el reporte. Por tanto, no representa la cantidad de resoluciones realizadas durante cada mes. Para evitar la omisión de registros históricos, la exportación utiliza el intervalo completo de la consulta; cuando no se establecen fechas, los límites de la tendencia se obtienen de los meses con información. Dentro del intervalo se completan con cero los meses sin registros.

```python
# backend/app/services/executive_service.py
start, end = selected.get('fecha_inicio'), selected.get('fecha_fin')
if full_history and series:
    start = start or date.fromisoformat(series[0]['mes'] + '-01')
    end = end or date.fromisoformat(series[-1]['mes'] + '-01')
```

La composición del PDF incorpora título, entidad, periodo, fecha y hora de generación en UTC, filtros, resumen de indicadores, tendencia mensual y distribuciones por municipio, tipo de apoyo, dependencia remitente y grupo vulnerable. Se utilizan los colores institucionales presentes en la aplicación, jerarquías tipográficas, barras acompañadas de cantidades, porcentajes y numeración de páginas. Las tablas pueden continuar en páginas posteriores y la tendencia se divide en bloques de hasta doce meses para conservar la legibilidad. El documento incluye definiciones sobre la unidad de análisis, los estatus, los denominadores y el alcance de la información.

[Insertar Figura HU6-C2. Encabezado y resumen de indicadores del PDF generado con datos sintéticos.]

[Insertar Figura HU6-C3. Tendencia mensual y distribuciones agregadas; cada gráfica identifica su escala y su base de cálculo. Evidencia con datos sintéticos.]

El archivo Excel utiliza hojas de resumen, tendencia y distribuciones. Conserva las cantidades como valores numéricos, aplica formatos de porcentaje e incorpora gráficas vinculadas a las celdas agregadas. Los textos de los catálogos se escriben explícitamente como cadenas para impedir su interpretación como fórmulas. Las descripciones extensas de filtros se dividen en filas de continuación para evitar que excedan el espacio disponible en una celda.

```python
# backend/app/services/executive_report.py
if isinstance(cell.value, str):
    cell.data_type = 's'
```

La implementación eliminó el límite anterior de 10,000 solicitudes asociado a la exportación de filas individuales. El archivo contiene agregados, y no una copia de los expedientes consultados. Este cambio no constituye una certificación de rendimiento: los tiempos para grandes volúmenes deberán evaluarse en un entorno de integración autorizado.

## 4.4.6 Pruebas

La verificación del Sprint 2 se organiza en pruebas funcionales, pruebas unitarias, pruebas de API y resultados con evidencia. En esta etapa se documenta la HU6. Los espacios correspondientes a HU7, HU9 y HU8 se reservan para su incorporación posterior, sin atribuirles resultados de las pruebas aquí descritas.

Las pruebas de HU6 se ejecutaron en un entorno aislado. Se deshabilitó la carga del archivo local de configuración y se utilizaron valores sintéticos para las conexiones. En las pruebas HTTP se sustituyeron las dependencias de consulta y de usuario autorizado cuando correspondía; en Flutter se emplearon respuestas HTTP simuladas. Esta estrategia permite comprobar la lógica y los contratos de la exportación sin consultar ni modificar la base activa.

### 4.4.6.1 Pruebas funcionales

**Pruebas a la Historia de Usuario 6: Exportar reportes filtrados**

Se realizaron pruebas enfocadas en la conservación de los filtros, la generación de reportes agregados y el manejo de errores:

1. **Conservación del periodo y los filtros.** Se seleccionó el periodo del 1 al 29 de febrero de 2024 y se comprobó que las mismas fechas se enviaran a las consultas del panel, del listado y de la exportación. La ventana de descarga mostró el periodo aplicado. También se verificó, mediante pruebas de la API con dependencias simuladas, el envío de varias opciones de municipio y de un filtro de estatus.
2. **Selección de formato y contenido del reporte.** Se comprobó la selección entre Excel y PDF y la generación de ambos formatos con datos sintéticos. Los archivos incluyeron el periodo, los filtros, los indicadores y las distribuciones agregadas. Se verificó que el generador excluyera los campos individuales introducidos deliberadamente en los datos de prueba y que la ruta de exportación no consultara el listado de solicitudes.
3. **Error de generación y reintento.** Se simuló una respuesta de error de la API. La interfaz mostró el mensaje correspondiente y mantuvo disponible la opción de reintentar. Se realizaron dos intentos y se comprobó que ambos conservaran las fechas seleccionadas.
4. **Estado de generación.** Se verificó que el botón de descarga permaneciera deshabilitado mientras la operación estaba en curso y que la ventana se cerrara cuando la función de exportación devolviera una respuesta de éxito simulada. Esta comprobación se realizó en ventanas de 360 × 640 y 1440 × 900 píxeles.

La siguiente captura muestra la ventana de exportación con el periodo aplicado, la selección de formato y la indicación de que el reporte contiene información agregada.

![Ventana de exportación con periodo aplicado y selección de formato](C:/Users/aldop/Documents/Codex/2026-10-02/referenced-chatgpt-conversation-this-is-an/outputs/evidencias/interfaz/HU6-exportacion-filtros-datos-sinteticos.png)

*Figura [número pendiente]. Exportación de reportes con el periodo aplicado. Prueba de interfaz con datos sintéticos y API simulada. Fuente: elaboración propia.*

La segunda captura muestra el mensaje presentado ante un error de generación. El periodo y el formato seleccionado permanecen visibles para permitir el reintento.

![Mensaje de error de exportación y opción de reintento](C:/Users/aldop/Documents/Codex/2026-10-02/referenced-chatgpt-conversation-this-is-an/outputs/evidencias/interfaz/HU6-error-reintento-datos-sinteticos.png)

*Figura [número pendiente]. Manejo de un error de exportación y disponibilidad del reintento. Prueba de interfaz con respuesta de error simulada. Fuente: elaboración propia.*

Las pruebas descritas se aprobaron en un entorno controlado. Las capturas documentan el comportamiento de la interfaz con respuestas simuladas; no constituyen evidencia de una descarga integrada con MySQL. La descarga completa desde un navegador conectado a una base de pruebas autorizada permanece pendiente de validación.

**Pruebas a la Historia de Usuario 7: Administrar usuarios institucionales**

[Espacio reservado para las pruebas funcionales y sus capturas.]

**Pruebas a la Historia de Usuario 9: Asignar permisos a un rol**

[Espacio reservado para las pruebas funcionales y sus capturas.]

**Pruebas a la Historia de Usuario 8: Administrar roles de forma escalable**

[Espacio reservado para las pruebas funcionales y sus capturas.]

### 4.4.6.2 Pruebas unitarias y evidencia

#### 4.4.6.2.1 Pruebas unitarias

**HU6.** Se comprobaron la construcción del modelo de reporte mediante campos permitidos, la conservación de valores numéricos en Excel, el cálculo de otros estatus y del porcentaje resuelto, el tratamiento de resultados vacíos, los periodos abiertos y la conservación del historial completo. También se verificaron etiquetas con caracteres de fórmula o marcado, textos extensos y la presencia de todas las categorías y meses en los archivos resultantes. Las consultas se inspeccionaron con una función de acceso a datos sustituida, comprobando parámetros, ámbito estatal y condición inclusiva de la fecha final; no se ejecutó SQL contra MySQL en estas pruebas.

En Flutter se añadieron cuatro casos específicos de HU6: aplicación y conservación del periodo con reintento, generación y éxito simulado en dos tamaños de ventana, y representación de periodos abiertos. Se actualizó además la prueba existente de exportación para exigir que el periodo aparezca en el resumen previo a descargar.

**HU7.** [Espacio reservado para pruebas unitarias y resultados.]

**HU9.** [Espacio reservado para pruebas unitarias y resultados.]

**HU8.** [Espacio reservado para pruebas unitarias y resultados.]

#### 4.4.6.2.2 Pruebas API

**HU6.** Se utilizó `TestClient` de FastAPI para solicitar ambos formatos, comprobar los filtros múltiples y las fechas recibidas por el servicio, verificar los encabezados de descarga y desactivación de caché, y confirmar que no se consulta el listado individual. Se verificó la respuesta 422 ante un formato no admitido, un intervalo invertido y un identificador de filtro inválido. La solicitud sin autenticación devolvió 401; una excepción de consulta simulada produjo 503. También se verificó que un resumen con un total superior a 10,000 no activa el límite antiguo de exportación por filas. Este último caso utiliza un resumen sustituido y no constituye una prueba de carga de 10,001 registros reales.

Estas comprobaciones validan la ruta y su integración con los generadores de archivos bajo dependencias controladas. No acreditan la integración completa con MySQL ni todas las combinaciones reales de roles y entidades. Las pruebas existentes que requieren conexión MySQL se omitieron expresamente durante esta ejecución.

**HU7.** [Espacio reservado para contratos, autenticación, autorización y resultados API.]

**HU9.** [Espacio reservado para contratos, autenticación, autorización y resultados API.]

**HU8.** [Espacio reservado para contratos, autenticación, autorización y resultados API.]

#### 4.4.6.2.3 Resultados y evidencia

**HU6.** La ejecución final del backend registró 59 pruebas aprobadas y 5 omitidas. Dentro de las aprobadas se incluyen 17 casos específicos de exportación en `test_export.py`; las restantes corresponden a regresión de funcionalidades existentes. Se emitieron dos advertencias de deprecación de dependencias, sin fallos de pruebas. La suite completa de Flutter registró 59 pruebas aprobadas, incluidas las cuatro nuevas de HU6; estas cuatro se repitieron tras un ajuste únicamente visual del entorno de captura y volvieron a aprobarse. El análisis estático no reportó problemas y la compilación web finalizó correctamente.

La inspección visual de las dos páginas del PDF de prueba permitió comprobar encabezados, espacios, etiquetas, tablas, gráficas y numeración. Las capturas de la ventana de exportación se revisaron en formato estrecho y amplio. En Excel se verificaron la estructura del archivo, los tipos de datos, porcentajes, gráficas embebidas y conservación de categorías mediante lectura del documento generado; no se realizó una inspección visual en Microsoft Excel.

| Evidencia | Resultado |
|---|---|
| Backend, suite completa | 59 aprobadas; 5 omitidas por requerir MySQL; 2 advertencias de deprecación. |
| Backend, HU6 | 17 casos aprobados incluidos en la suite anterior. |
| Flutter, suite completa | 59 pruebas aprobadas. |
| Flutter, HU6 | 4 casos aprobados; ejecución específica final también aprobada. |
| Análisis Flutter | Sin problemas detectados. |
| Compilación web | Correcta; salida generada en `build/web`. |
| PDF | Generado y revisado visualmente en sus dos páginas, con datos sintéticos. |
| Excel | Generado y verificado estructuralmente, con datos sintéticos; inspección visual nativa pendiente. |
| Integración MySQL y descarga real desde navegador | No ejecutadas en esta sesión. |

La evidencia obtenida respalda el comportamiento automatizado de HU6 en condiciones controladas. Antes de documentar una aceptación operativa, permanece pendiente ejecutar la descarga completa desde un navegador conectado a un entorno MySQL de pruebas autorizado, contrastar los agregados contra ese entorno y revisar el Excel en la aplicación de destino.

**HU7.** [Espacio reservado para resultados, incidencias y evidencias.]

**HU9.** [Espacio reservado para resultados, incidencias y evidencias.]

**HU8.** [Espacio reservado para resultados, incidencias y evidencias.]

---

## Guía editorial para colocar fragmentos y figuras

Esta guía no forma parte del texto de tesis anterior.

- C1 y P1: `evidencias/interfaz/HU6-exportacion-filtros-datos-sinteticos.png`.
- C2: página 1 de `HU6-reporte-prueba.pdf`.
- C3: páginas 1 y 2 del mismo PDF actualizado.
- P2: `evidencias/interfaz/HU6-error-reintento-datos-sinteticos.png`.
- Evidencia de adaptación: capturas `HU6-exportacion-360-datos-sinteticos.png` y `HU6-exportacion-1440-datos-sinteticos.png`.
- Fragmento principal: `backend/app/routers/executive.py`, función `export`, líneas 90–101.
- Filtros y ámbito: `backend/app/services/executive_service.py`, función `where_clause`, desde la línea 47.
- Historial completo: mismo archivo, función `dashboard`, desde la línea 109.
- Campos permitidos: `backend/app/services/executive_report.py`, función `build_report`, desde la línea 42.
- Composición de archivos: funciones `render_xlsx` y `render_pdf` del mismo archivo. Para la tesis basta un fragmento breve; no es necesario mostrar todo el generador.
- Selección de fechas: `sgsc_ejecutiva/lib/widgets/filter_sheet.dart`, función `choosePeriod`, desde la línea 244.
- Envío de filtros: `sgsc_ejecutiva/lib/screens/dashboard/dashboard_screen.dart`, función `export`, desde la línea 235. `ExecutiveApi.export` ya existía y se reutilizó sin modificar el archivo del servicio HTTP.
- Los identificadores C1–P2 son marcadores editoriales, no la numeración definitiva del índice de figuras.
