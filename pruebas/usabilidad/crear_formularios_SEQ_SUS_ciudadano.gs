/**
 * SIEASAS · Prueba de usabilidad del Módulo Ciudadano
 * Crea en tu Google Drive:
 *   - Formulario SEQ (lo llena el moderador después de cada tarea)
 *   - Formulario SUS (lo llena el participante al final)
 *   - Una hoja de cálculo con las respuestas de ambos (pestañas SEQ y SUS),
 *     el puntaje SUS calculado y una pestaña Resumen.
 *
 * Uso: https://script.google.com > Nuevo proyecto > pega este archivo >
 * selecciona la función crearFormularios > Ejecutar > autoriza con tu cuenta.
 * Los enlaces aparecen en el Registro de ejecución.
 */

const TAREAS = [
  'Tarea 1 · Crear cuenta y completar perfil',
  'Tarea 2 · Solicitar apoyo para un familiar',
  'Tarea 3 · Actualizar datos de contacto',
  'Tarea 4 · Consultar el avance',
];

const SUS_PREGUNTAS = [
  'Creo que me gustaría usar esta aplicación con frecuencia.',
  'Encontré la aplicación innecesariamente compleja.',
  'Pensé que la aplicación era fácil de usar.',
  'Creo que necesitaría el apoyo de una persona con conocimientos técnicos para poder usar esta aplicación.',
  'Encontré que las distintas funciones de la aplicación estaban bien integradas.',
  'Pensé que había demasiada inconsistencia en esta aplicación.',
  'Imagino que la mayoría de las personas aprendería a usar esta aplicación muy rápidamente.',
  'Encontré la aplicación muy complicada de usar.',
  'Me sentí con mucha confianza al usar la aplicación.',
  'Necesité aprender muchas cosas antes de poder empezar a usar esta aplicación.',
];

function crearFormularios() {
  const carpeta = DriveApp.createFolder('SIEASAS Ciudadano · Prueba de usabilidad');
  const hoja = SpreadsheetApp.create('SIEASAS Ciudadano · Resultados SEQ y SUS');

  const seq = crearSEQ_();
  const sus = crearSUS_();
  seq.setDestination(FormApp.DestinationType.SPREADSHEET, hoja.getId());
  sus.setDestination(FormApp.DestinationType.SPREADSHEET, hoja.getId());

  prepararHoja_(hoja.getId(), seq.getId(), sus.getId());

  for (const id of [seq.getId(), sus.getId(), hoja.getId()]) {
    DriveApp.getFileById(id).moveTo(carpeta);
  }

  Logger.log('SEQ (moderador) para responder: ' + seq.getPublishedUrl());
  Logger.log('SUS (participante) para responder: ' + sus.getPublishedUrl());
  Logger.log('Hoja de resultados: ' + hoja.getUrl());
  Logger.log('Carpeta en Drive: ' + carpeta.getUrl());
}

function crearSEQ_() {
  const form = FormApp.create('SIEASAS Ciudadano · SEQ por tarea (moderador)');
  form.setDescription(
    'Lo llena el moderador u observador al terminar cada tarea. ' +
    'Leer al participante: «En general, ¿qué tan fácil o difícil fue completar esta tarea?» ' +
    'y registrar su respuesta del 1 al 7.'
  );
  form.setCollectEmail(false);
  form.setShowLinkToRespondAgain(true);
  form.setConfirmationMessage('Registrado. Puedes enviar la siguiente tarea.');

  form.addTextItem().setTitle('Participante').setHelpText('Usa un identificador, no el nombre: P1, P2, P3…').setRequired(true);
  form.addListItem().setTitle('Tarea').setChoiceValues(TAREAS).setRequired(true);
  form.addScaleItem()
    .setTitle('SEQ · En general, ¿qué tan fácil o difícil fue completar esta tarea?')
    .setBounds(1, 7).setLabels('Muy difícil', 'Muy fácil').setRequired(true);
  form.addMultipleChoiceItem().setTitle('Éxito de la tarea')
    .setChoiceValues(['Sin ayuda', 'Con ayuda', 'No completada']).setRequired(true);
  form.addTextItem().setTitle('Tiempo (mm:ss)');
  form.addTextItem().setTitle('Errores o desvíos (número)')
    .setValidation(FormApp.createTextValidation().requireNumber().build());
  form.addParagraphTextItem().setTitle('Observaciones');
  return form;
}

function crearSUS_() {
  const form = FormApp.create('SIEASAS Ciudadano · Cuestionario SUS');
  form.setDescription(
    'Gracias por participar. Indica qué tan de acuerdo estás con cada frase sobre la aplicación SIEASAS Ciudadano que acabas de usar. ' +
    'Responde rápido, con tu primera impresión. No hay respuestas correctas ni incorrectas.'
  );
  form.setCollectEmail(false);
  form.setProgressBar(true);
  form.setConfirmationMessage('¡Muchas gracias por tus respuestas!');

  // Primera pantalla: la llena el moderador antes de entregar el equipo.
  form.addTextItem().setTitle('Número de participante')
    .setHelpText('Lo escribe el moderador antes de entregarte el equipo (P1, P2, P3…).')
    .setRequired(true);

  // Una pregunta por pantalla para el participante.
  SUS_PREGUNTAS.forEach((texto, i) => {
    form.addPageBreakItem().setTitle('Pregunta ' + (i + 1) + ' de ' + SUS_PREGUNTAS.length);
    form.addScaleItem()
      .setTitle(texto)
      .setHelpText('Elige un número del 1 al 5.')
      .setBounds(1, 5).setLabels('Totalmente en desacuerdo', 'Totalmente de acuerdo')
      .setRequired(true);
  });
  return form;
}

/** Nombra las pestañas, agrega el puntaje SUS y el resumen. */
function prepararHoja_(hojaId, seqId, susId) {
  let ss, seqSheet, susSheet;
  // Google crea las pestañas de respuestas unos segundos después de enlazar.
  for (let intento = 0; intento < 15 && !(seqSheet && susSheet); intento++) {
    SpreadsheetApp.flush();
    Utilities.sleep(1000);
    ss = SpreadsheetApp.openById(hojaId);
    for (const sh of ss.getSheets()) {
      const url = sh.getFormUrl() || '';
      if (url.indexOf(seqId) >= 0) seqSheet = sh;
      if (url.indexOf(susId) >= 0) susSheet = sh;
    }
  }
  if (!seqSheet || !susSheet) {
    Logger.log('Aviso: no se encontraron las pestañas de respuestas; renómbralas a mano como SEQ y SUS.');
    return;
  }
  seqSheet.setName('SEQ');
  susSheet.setName('SUS');
  for (const sh of ss.getSheets()) {
    if (!sh.getFormUrl() && sh.getName() !== 'Resumen') ss.deleteSheet(sh);
  }

  // Columnas SUS: A marca temporal, B participante, C..L preguntas 1..10.
  susSheet.getRange('M1').setFormula(
    '=ARRAYFORMULA(IF(ROW(B:B)=1,"Puntaje SUS",IF(B:B="","",' +
    '((C:C+E:E+G:G+I:I+K:K)-5+(25-(D:D+F:F+H:H+J:J+L:L)))*2.5)))'
  );

  // Columnas SEQ: A marca temporal, B participante, C tarea, D SEQ, E éxito.
  const resumen = ss.insertSheet('Resumen');
  const filas = [['Tarea', 'Respuestas', 'SEQ promedio (1–7)', 'Sin ayuda', 'Con ayuda', 'No completada']];
  TAREAS.forEach((t, i) => {
    const r = i + 2;
    filas.push([
      t,
      '=COUNTIF(SEQ!C:C,A' + r + ')',
      '=IFERROR(ROUND(AVERAGEIF(SEQ!C:C,A' + r + ',SEQ!D:D),2),"")',
      '=COUNTIFS(SEQ!C:C,A' + r + ',SEQ!E:E,"Sin ayuda")',
      '=COUNTIFS(SEQ!C:C,A' + r + ',SEQ!E:E,"Con ayuda")',
      '=COUNTIFS(SEQ!C:C,A' + r + ',SEQ!E:E,"No completada")',
    ]);
  });
  resumen.getRange(1, 1, filas.length, filas[0].length).setValues(filas);
  resumen.getRange('A8:B10').setValues([
    ['SUS · participantes', '=COUNT(SUS!M:M)'],
    ['SUS · puntaje promedio (0–100)', '=IFERROR(ROUND(AVERAGE(SUS!M:M),1),"")'],
    ['Referencia', 'Más de 68 = por encima del promedio'],
  ]);
  resumen.getRange('A1:F1').setFontWeight('bold');
  resumen.getRange('A8:A10').setFontWeight('bold');
  resumen.autoResizeColumns(1, 6);
  ss.setActiveSheet(resumen);
  ss.moveActiveSheet(1);
}
