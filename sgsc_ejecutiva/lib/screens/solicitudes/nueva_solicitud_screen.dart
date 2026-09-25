import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../services/executive_api.dart';
import '../../widgets/executive_widgets.dart';

class NewRequestScreen extends StatefulWidget {
  final ExecutiveApi api;
  final Map<String, dynamic> catalogs;
  final String entity;
  final VoidCallback onBack;
  final ValueChanged<String> onSaved;
  const NewRequestScreen({
    super.key,
    required this.api,
    required this.catalogs,
    required this.entity,
    required this.onBack,
    required this.onSaved,
  });
  @override
  State<NewRequestScreen> createState() => _NewRequestScreenState();
}

class _NewRequestScreenState extends State<NewRequestScreen> {
  static const stepNames = [
    'Beneficiario · Datos personales',
    'Beneficiario · Domicilio',
    'Beneficiario · Información social',
    'Solicitante · Datos personales',
    'Solicitante · Domicilio y contacto',
    'Solicitud · Apoyo y recepción',
    'Solicitud · Descripción',
    'Revisar y registrar',
  ];
  final forms = List.generate(stepNames.length, (_) => GlobalKey<FormState>());
  final labels = <String, String>{};
  final optionsByField = <String, List<dynamic>>{};
  final booleanFields = <String>{};
  final fields = <String, TextEditingController>{};
  final values = <String, int?>{};
  final flags = <String, bool>{};
  final idempotency = const Uuid().v4();
  List<dynamic> birthMunicipalities = [];
  Map<String, dynamic>? beneficiary, applicant;
  bool existingBeneficiary = false, existingApplicant = false, busy = false;
  int step = 0, birthLoad = 0;
  String? error;

  List<int> get visibleSteps => [
    0,
    if (!existingBeneficiary) ...[1, 2],
    3,
    if (!existingApplicant) 4,
    5,
    6,
    7,
  ];

  void moveTo(int nextStep) {
    FocusScope.of(context).unfocus();
    setState(() {
      step = nextStep;
      error = null;
    });
  }

  bool get missingCatalogs {
    final keys = switch (step) {
      0 => existingBeneficiary ? <String>[] : ['generos', 'entidades'],
      1 || 4 => ['municipios'],
      2 => ['seguridad_social', 'grupos'],
      3 => existingApplicant ? <String>[] : ['parentescos'],
      5 => ['apoyos', 'origenes', 'canales', 'unidades'],
      _ => <String>[],
    };
    return keys.any((key) => (widget.catalogs[key] as List? ?? []).isEmpty);
  }

  TextEditingController controller(String key) =>
      fields.putIfAbsent(key, () => TextEditingController());
  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget input(
    String label,
    String key, {
    bool required = true,
    bool number = false,
    int max = 150,
    String? help,
    bool multiline = false,
    int? minimum,
  }) {
    labels[key] = label;
    return LabeledField(
      label,
      TextFormField(
        controller: controller(key),
        enabled: !busy,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        minLines: multiline ? 3 : 1,
        maxLines: multiline ? 6 : 1,
        maxLength: max,
        decoration: InputDecoration(helperText: help, helperMaxLines: 3),
        validator: (v) {
          final value = (v ?? '').trim();
          if (required && value.isEmpty) return 'Completa este campo.';
          if (value.isNotEmpty &&
              number &&
              (int.tryParse(value) == null ||
                  int.parse(value) < (minimum ?? 0))) {
            return 'Ingresa un número válido.';
          }
          if (key.endsWith('codigo_postal') &&
              !RegExp(r'^\d{5}$').hasMatch(value)) {
            return 'Ingresa cinco dígitos.';
          }
          if (key == 'b.curp' &&
              value.isNotEmpty &&
              !RegExp(r'^[A-Za-z0-9]{18}$').hasMatch(value)) {
            return 'La CURP debe tener 18 caracteres.';
          }
          return null;
        },
      ),
    );
  }

  Widget select(
    String label,
    String key,
    String catalog, {
    bool required = true,
    List<dynamic>? options,
    ValueChanged<int?>? changed,
  }) {
    final rows = options ?? widget.catalogs[catalog] as List? ?? [];
    labels[key] = label;
    optionsByField[key] = rows;
    return LabeledField(
      label,
      DropdownButtonFormField<int>(
        key: ValueKey('$key-${values[key]}-${rows.length}'),
        initialValue: values[key],
        isExpanded: true,
        hint: Text(rows.isEmpty ? 'Sin opciones disponibles' : 'Selecciona…'),
        items: [
          if (!required)
            const DropdownMenuItem<int>(
              value: null,
              child: Text('Sin especificar'),
            ),
          ...rows.map(
            (r) => DropdownMenuItem<int>(
              value: r['id'] as int,
              child: Text('${r['nombre']}', overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged: busy || rows.isEmpty
            ? null
            : (v) {
                setState(() => values[key] = v);
                changed?.call(v);
              },
        validator: (v) =>
            required && v == null ? 'Selecciona una opción.' : null,
      ),
    );
  }

  Widget birthDate(String prefix) {
    labels['$prefix.fecha_nacimiento'] = 'Fecha de nacimiento';
    return LabeledField(
      'Fecha de nacimiento',
      TextFormField(
        controller: controller('$prefix.fecha_nacimiento'),
        readOnly: true,
        decoration: const InputDecoration(
          hintText: 'Selecciona la fecha',
          suffixIcon: Icon(Icons.calendar_month),
        ),
        onTap: busy
            ? null
            : () async {
                final today = DateTime.now();
                final value = await showDatePicker(
                  context: context,
                  initialDate:
                      DateTime.tryParse(
                        controller('$prefix.fecha_nacimiento').text,
                      ) ??
                      DateTime(today.year - 25),
                  firstDate: DateTime(today.year - 150),
                  lastDate: today,
                  helpText: 'Fecha de nacimiento',
                );
                if (value != null && mounted) {
                  setState(
                    () => controller('$prefix.fecha_nacimiento').text = value
                        .toIso8601String()
                        .substring(0, 10),
                  );
                }
              },
        validator: (v) => (v ?? '').isEmpty ? 'Selecciona la fecha.' : null,
      ),
    );
  }

  Widget check(String label, String key) {
    labels[key] = label;
    booleanFields.add(key);
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(fontSize: 14)),
      value: flags[key] ?? false,
      controlAffinity: ListTileControlAffinity.leading,
      onChanged: busy ? null : (v) => setState(() => flags[key] = v ?? false),
    );
  }

  Widget section(String title) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
    ),
  );

  Future<void> loadBirth(int? entity) async {
    final version = ++birthLoad;
    setState(() {
      birthMunicipalities = [];
      values['b.municipio_nacimiento_id'] = null;
      error = null;
    });
    if (entity == null) return;
    try {
      final result = await widget.api.get('/ejecutivo/municipios-nacimiento', {
        'entidad_id': '$entity',
      });
      if (mounted && version == birthLoad) {
        setState(() => birthMunicipalities = result['items'] as List);
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> findPerson(bool isBeneficiary) async {
    final search = TextEditingController();
    List<dynamic> rows = [];
    String? lookupError;
    bool loading = false;
    final chosen = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            isBeneficiary ? 'Buscar beneficiario' : 'Buscar solicitante',
          ),
          content: SizedBox(
            width: 440,
            height: 370,
            child: Column(
              children: [
                TextField(
                  controller: search,
                  decoration: InputDecoration(
                    labelText: isBeneficiary ? 'Nombre o CURP' : 'Nombre',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: loading
                      ? null
                      : () async {
                          update(() {
                            loading = true;
                            lookupError = null;
                          });
                          try {
                            final result = await widget.api.get(
                              '/ejecutivo/personas',
                              {
                                'tipo': isBeneficiary
                                    ? 'beneficiario'
                                    : 'solicitante',
                                'q': search.text.trim(),
                              },
                            );
                            if (context.mounted) {
                              update(() => rows = result['items'] as List);
                            }
                          } catch (e) {
                            if (context.mounted) {
                              update(() => lookupError = e.toString());
                            }
                          } finally {
                            if (context.mounted) update(() => loading = false);
                          }
                        },
                  child: Text(loading ? 'Buscando…' : 'Buscar'),
                ),
                if (lookupError != null)
                  Text(lookupError!, style: const TextStyle(color: Colors.red)),
                Expanded(
                  child: rows.isEmpty
                      ? const Center(
                          child: Text(
                            'Busca por nombre. Si no aparece, registra un expediente nuevo.',
                          ),
                        )
                      : ListView(
                          children: rows
                              .map(
                                (r) => ListTile(
                                  title: Text('${r['nombre']}'),
                                  onTap: () => Navigator.pop(
                                    context,
                                    Map<String, dynamic>.from(r),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      ),
    );
    // Dialog exit animations may still use its controller; do not dispose it before removal.
    if (chosen != null && mounted) {
      setState(() {
        if (isBeneficiary) {
          beneficiary = chosen;
        } else {
          applicant = chosen;
        }
      });
    }
  }

  List<Widget> address(String prefix) => [
    select(
      'Municipio de domicilio · ${widget.entity}',
      '$prefix.municipio_id',
      'municipios',
    ),
    input('Calle', '$prefix.calle'),
    input(
      'Número exterior / interior',
      '$prefix.numero',
      max: prefix == 'b' ? 15 : 20,
    ),
    if (prefix == 'b')
      input(
        'Clave de colonia del expediente',
        'b.colonia_id',
        number: true,
        max: 10,
        minimum: 1,
        help: 'SSNL guarda una clave numérica. Usa la clave registrada en el expediente; no el nombre de la colonia.',
      )
    else
      input('Colonia', 's.colonia'),
    input('Código postal', '$prefix.codigo_postal', number: true, max: 5),
  ];

  List<Widget> beneficiaryFields() => [
    if (step == 0) ...[
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Usar beneficiario existente'),
        value: existingBeneficiary,
        onChanged: busy ? null : (v) => setState(() => existingBeneficiary = v),
      ),
      if (existingBeneficiary) ...[
        if (beneficiary != null) Notice('${beneficiary!['nombre']}'),
        OutlinedButton(
          onPressed: busy ? null : () => findPerson(true),
          child: const Text('Buscar beneficiario'),
        ),
      ] else ...[
        input('Nombre(s)', 'b.nombres'),
        input('Apellidos', 'b.apellidos'),
        input('CURP (opcional)', 'b.curp', required: false, max: 18),
        birthDate('b'),
        select('Género', 'b.genero_id', 'generos'),
        select(
          'Estado de nacimiento',
          'birth_entity',
          'entidades',
          changed: loadBirth,
        ),
        select(
          'Municipio de nacimiento',
          'b.municipio_nacimiento_id',
          '',
          options: birthMunicipalities,
        ),
      ],
    ],
    if (step == 1) ...[
      section('Domicilio'),
      ...address('b'),
      input('Años de residencia', 'b.tiempo_residencia', number: true, max: 3),
    ],
    if (step == 2) ...[
      section('Información social'),
      input('¿Con quién vive?', 'b.con_quien_vive', max: 50),
      input('Número de hijos', 'b.numero_hijos', number: true, max: 3),
      check('Algún hijo tiene seguridad social', 'b.hijo_seguridad_social'),
      check('Estudia actualmente', 'b.estudia'),
      if (flags['b.estudia'] == true)
        input('Área de estudio (opcional)', 'b.area_estudio', required: false),
      input('Profesión (opcional)', 'b.profesion', required: false),
      input(
        'Fuente de ingresos (opcional)',
        'b.fuente_ingresos',
        required: false,
      ),
      select('Seguridad social', 'b.seguridad_social_id', 'seguridad_social'),
      input('Número de afiliación (opcional)', 'b.afiliacion', required: false),
      select('Grupo vulnerable', 'b.grupo_vulnerable_id', 'grupos'),
      check('Realiza el trámite personalmente', 'b.tramita_personalmente'),
      check('Es migrante', 'b.migrante'),
      check('Pertenece a Código 2024', 'b.codigo2024'),
    ],
  ];

  List<Widget> applicantFields() => [
    if (step == 3) ...[
      const Notice(
        'El solicitante es quien realiza el trámite. SSNL requiere sus datos aunque sea el propio beneficiario.',
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Usar solicitante existente'),
        value: existingApplicant,
        onChanged: busy ? null : (v) => setState(() => existingApplicant = v),
      ),
      if (existingApplicant) ...[
        if (applicant != null) Notice('${applicant!['nombre']}'),
        OutlinedButton(
          onPressed: busy ? null : () => findPerson(false),
          child: const Text('Buscar solicitante'),
        ),
      ] else ...[
        input('Nombre(s)', 's.nombres', max: 100),
        input('Apellidos', 's.apellidos', max: 100),
        select(
          'Parentesco con el beneficiario',
          's.parentesco_id',
          'parentescos',
        ),
        input(
          'Otro parentesco (si aplica)',
          's.otro_parentesco',
          max: 100,
          required: false,
        ),
        birthDate('s'),
      ],
    ],
    if (step == 4) ...[
      ...address('s'),
      input('Teléfono', 's.telefono', max: 15),
    ],
  ];

  List<Widget> requestFields() => [
    if (step == 5) ...[
      const Notice(
        'La solicitud se guardará con estatus Inicio y la fecha de registro. Se conservará quién realizó el alta.',
      ),
      select('Tipo de apoyo', 'tipo_apoyo_id', 'apoyos'),
      select('Origen de la solicitud', 'enviado_por_id', 'origenes'),
      select(
        'Dependencia remitente (opcional)',
        'dependencia_id',
        'dependencias',
        required: false,
      ),
      select(
        'Partido político remitente (opcional)',
        'partido_id',
        'partidos',
        required: false,
      ),
      select(
        'Municipio remitente (opcional)',
        'municipio_remitente_id',
        'municipios',
        required: false,
      ),
      input('Detalles del envío (opcional)', 'detalles_envio', required: false),
      select('Canal de recepción', 'canal_id', 'canales'),
      select('Unidad tratante', 'unidad_tratante_id', 'unidades'),
    ],
    if (step == 6) ...[
      input(
        'Descripción de la solicitud',
        'descripcion',
        max: 5000,
        multiline: true,
      ),
      input(
        'Observaciones (opcional)',
        'observaciones',
        max: 5000,
        multiline: true,
        required: false,
      ),
    ],
  ];

  String reviewValue(String key) {
    if (booleanFields.contains(key)) return flags[key] == true ? 'Sí' : 'No';
    if (optionsByField.containsKey(key)) {
      for (final row in optionsByField[key]!) {
        if (row['id'] == values[key]) return '${row['nombre']}';
      }
      return 'Sin especificar';
    }
    final value = fields[key]?.text.trim() ?? '';
    return value.isEmpty ? 'Sin especificar' : value;
  }

  Widget reviewCard(
    String title,
    String prefix,
    Map<String, dynamic>? person,
  ) => ExecutiveCard(
    title: title,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (person != null)
          Text('${person['nombre']} · Expediente #${person['id']}')
        else
          for (final entry in labels.entries)
            if ((prefix.isEmpty
                ? !entry.key.contains('.') && entry.key != 'birth_entity'
                : entry.key.startsWith('$prefix.') ||
                      prefix == 'b' && entry.key == 'birth_entity'))
              LabeledField(entry.value, Text(reviewValue(entry.key))),
      ],
    ),
  );

  List<Widget> reviewFields() => [
    const Notice(
      'Revisa la información antes de registrar. Usa Paso anterior para corregir los datos.',
    ),
    reviewCard('Beneficiario', 'b', existingBeneficiary ? beneficiary : null),
    reviewCard('Solicitante', 's', existingApplicant ? applicant : null),
    reviewCard('Solicitud', '', null),
  ];

  Map<String, dynamic> personData(String prefix) {
    final result = <String, dynamic>{};
    const numeric = {'colonia_id', 'tiempo_residencia', 'numero_hijos'};
    for (final e in fields.entries.where((e) => e.key.startsWith('$prefix.'))) {
      final key = e.key.substring(2), value = e.value.text.trim();
      result[key] = value.isEmpty
          ? null
          : numeric.contains(key)
          ? int.tryParse(value)
          : key == 'curp'
          ? value.toUpperCase()
          : value;
    }
    for (final e in values.entries.where((e) => e.key.startsWith('$prefix.'))) {
      result[e.key.substring(2)] = e.value;
    }
    for (final e in flags.entries.where((e) => e.key.startsWith('$prefix.'))) {
      result[e.key.substring(2)] = e.value;
    }
    return result;
  }

  Future<void> next() async {
    if (!forms[step].currentState!.validate()) return;
    if (step == 0 && existingBeneficiary && beneficiary == null ||
        step == 3 && existingApplicant && applicant == null) {
      setState(() => error = 'Selecciona un expediente para continuar.');
      return;
    }
    if (step < 7) {
      moveTo(visibleSteps[visibleSteps.indexOf(step) + 1]);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final body = <String, dynamic>{
        'idempotencia': idempotency,
        if (existingBeneficiary)
          'beneficiario_id': beneficiary!['id']
        else
          'beneficiario': personData('b'),
        if (existingApplicant)
          'solicitante_id': applicant!['id']
        else
          'solicitante': personData('s'),
        for (final e in values.entries.where(
          (e) => !e.key.contains('.') && e.key != 'birth_entity',
        ))
          e.key: e.value,
        for (final e in fields.entries.where((e) => !e.key.contains('.')))
          e.key: e.value.text.trim().isEmpty ? null : e.value.text.trim(),
      };
      final result = await widget.api.post('/ejecutivo/solicitudes', body);
      if (mounted) widget.onSaved('${result['folio']}');
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: ValueKey(step),
    padding: const EdgeInsets.all(22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeading('Nueva solicitud', onBack: busy ? () {} : widget.onBack),
        Text(
          'Paso ${visibleSteps.indexOf(step) + 1} de ${visibleSteps.length} · ${stepNames[step]}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(
          value: (visibleSteps.indexOf(step) + 1) / visibleSteps.length,
        ),
        const SizedBox(height: 16),
        if (missingCatalogs)
          const Notice(
            'Faltan opciones obligatorias en los catálogos. La administración debe completarlas para continuar.',
            error: true,
          ),
        Form(
          key: forms[step],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: step < 3
                ? beneficiaryFields()
                : step < 5
                ? applicantFields()
                : step < 7
                ? requestFields()
                : reviewFields(),
          ),
        ),
        if (error != null) Notice(error!, error: true),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy || missingCatalogs ? null : next,
          child: Text(
            busy
                ? 'Guardando…'
                : step < 7
                ? 'Continuar'
                : 'Registrar solicitud',
          ),
        ),
        if (step > 0)
          TextButton(
            onPressed: busy
                ? null
                : () => moveTo(visibleSteps[visibleSteps.indexOf(step) - 1]),
            child: const Text('Paso anterior'),
          ),
      ],
    ),
  );
}
