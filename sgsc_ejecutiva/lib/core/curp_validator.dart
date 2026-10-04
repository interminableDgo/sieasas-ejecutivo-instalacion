/// Validates the structure locally; does not certify registration with RENAPO.
String? validateCurp(String input, {DateTime? today}) {
  final value = input.trim().toUpperCase();
  if (value.isEmpty) return null; // CURP is optional.
  if (value.length > 18) return 'La CURP debe tener 18 caracteres.';
  const patterns = [
    '[A-Z]',
    '[AEIOUX]',
    '[A-Z]',
    '[A-Z]',
    '[0-9]',
    '[0-9]',
    '[0-9]',
    '[0-9]',
    '[0-9]',
    '[0-9]',
    '[HM]',
    '[A-Z]',
    '[A-Z]',
    '[B-DF-HJ-NP-TV-Z]',
    '[B-DF-HJ-NP-TV-Z]',
    '[B-DF-HJ-NP-TV-Z]',
    '[A-Z0-9]',
    '[0-9]',
  ];
  for (var i = 0; i < value.length; i++) {
    if (!RegExp('^${patterns[i]}\$').hasMatch(value[i])) {
      if (i < 4) {
        return 'Revisa las iniciales: letra, vocal interna (o X) y dos letras.';
      }
      if (i < 10) return 'La fecha de la CURP debe usar seis números (AAMMDD).';
      if (i == 10) return 'El sexo en la CURP debe ser H o M (posición 11).';
      if (i < 13) return 'La entidad de nacimiento debe usar dos letras.';
      if (i < 16) {
        return 'Las posiciones 14 a 16 deben ser consonantes internas.';
      }
      if (i == 16) return 'La posición 17 debe ser una letra o un número.';
      return 'El dígito verificador debe ser un número (posición 18).';
    }
  }
  if (value.length >= 10) {
    final year = int.parse(value.substring(4, 6));
    final month = int.parse(value.substring(6, 8));
    final day = int.parse(value.substring(8, 10));
    final century = value.length >= 17 && int.tryParse(value[16]) != null
        ? 1900
        : 2000;
    final birth = DateTime(century + year, month, day);
    if (birth.month != month || birth.day != day) {
      return 'La fecha de nacimiento en la CURP no existe.';
    }
    if (value.length >= 17 && birth.isAfter(today ?? DateTime.now())) {
      return 'La fecha de nacimiento en la CURP no puede ser futura.';
    }
  }
  if (value.length >= 13) {
    const entities = {
      'AS',
      'BC',
      'BS',
      'CC',
      'CL',
      'CM',
      'CS',
      'CH',
      'DF',
      'DG',
      'GT',
      'GR',
      'HG',
      'JC',
      'MC',
      'MN',
      'MS',
      'NT',
      'NL',
      'OC',
      'PL',
      'QT',
      'QR',
      'SP',
      'SL',
      'SR',
      'TC',
      'TS',
      'TL',
      'VZ',
      'YN',
      'ZS',
      'NE',
    };
    if (!entities.contains(value.substring(11, 13))) {
      return 'La clave de entidad de nacimiento no es válida.';
    }
  }
  if (value.length < 18) {
    return 'La CURP debe tener 18 caracteres (llevas ${value.length}).';
  }
  const alphabet = '0123456789ABCDEFGHIJKLMNÑOPQRSTUVWXYZ';
  var sum = 0;
  for (var i = 0; i < 17; i++) {
    sum += alphabet.indexOf(value[i]) * (18 - i);
  }
  if ((10 - sum % 10) % 10 != int.parse(value[17])) {
    return 'El dígito verificador de la CURP es incorrecto. Revisa la clave.';
  }
  return null;
}
