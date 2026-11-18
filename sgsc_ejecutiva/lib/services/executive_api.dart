import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core/api_config.dart';

class ApiException implements Exception {
  final String message;
  final int status;
  ApiException(this.message, [this.status = 0]);
  @override
  String toString() => message;
}

class ExecutiveApi {
  final http.Client client;
  final String baseUrl;
  String? token;
  ExecutiveApi({http.Client? client, String? baseUrl})
    : client = client ?? http.Client(),
      baseUrl = baseUrl ?? ApiConfig.baseUrl;
  Future<http.Response> request(
    String path, {
    Map<String, dynamic>? body,
    // Values are a String or an Iterable<String> (repeated ?key=a&key=b).
    Map<String, Object> query = const {},
    Duration timeout = const Duration(seconds: 30),
    String timeoutMessage = 'La conexión tardó demasiado. Intenta nuevamente.',
  }) async {
    final uri = Uri.parse('$baseUrl$path')
        .replace(queryParameters: query.isEmpty ? null : query);
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    http.Response response;
    try {
      response =
          await (body == null
                  ? client.get(uri, headers: headers)
                  : client.post(uri, headers: headers, body: jsonEncode(body)))
              .timeout(timeout);
    } on TimeoutException {
      throw ApiException(timeoutMessage);
    } on http.ClientException {
      throw ApiException(
        'No se pudo conectar. Revisa tu conexión e intenta nuevamente.',
      );
    }
    if (response.statusCode >= 400) {
      String message = 'No fue posible completar la operación.';
      try {
        final detail =
            (jsonDecode(utf8.decode(response.bodyBytes)) as Map)['detail'];
        message = detail is String
            ? detail
            : 'Revisa los campos del formulario.';
      } catch (_) {}
      throw ApiException(message, response.statusCode);
    }
    return response;
  }

  Future<Map<String, dynamic>> get(
    String path, [
    Map<String, Object> query = const {},
  ]) async =>
      jsonDecode(utf8.decode((await request(path, query: query)).bodyBytes))
          as Map<String, dynamic>;
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async =>
      jsonDecode(utf8.decode((await request(path, body: body)).bodyBytes))
          as Map<String, dynamic>;
  // A report gathers every indicator and builds a file, so it gets more time
  // than a screen query.
  Future<Uint8List> export(String format, Map<String, Object> filters) async =>
      (await request(
        '/ejecutivo/exportar/$format',
        query: filters,
        timeout: const Duration(minutes: 2),
        timeoutMessage: 'El reporte tardó demasiado en generarse. Revisa tu conexión e intenta nuevamente.',
      )).bodyBytes;
  void dispose() => client.close();
}
