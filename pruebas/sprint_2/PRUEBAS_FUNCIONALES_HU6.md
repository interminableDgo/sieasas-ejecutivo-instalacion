#### 4.4.6.1 Pruebas funcionales

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
