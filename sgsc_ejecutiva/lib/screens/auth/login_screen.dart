import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/executive_api.dart';
import '../../widgets/executive_widgets.dart';

class LoginScreen extends StatefulWidget {
  final ExecutiveApi api;
  final ValueChanged<Map<String, dynamic>> onLogin;
  const LoginScreen({super.key, required this.api, required this.onLogin});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Keep aligned with RegisterInput and ResetInput in backend/app/schemas/auth.py.
  static const minimumPasswordLength = 15;
  static const maximumPasswordLength = 128;
  final form = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  final confirmation = TextEditingController();
  final code = TextEditingController();
  late String mode;
  String? resetToken;
  String? challenge;
  String? error;
  String message = '';
  bool busy = false, show = false;

  Widget passwordRequirements() => ValueListenableBuilder<TextEditingValue>(
    valueListenable: password,
    builder: (context, value, _) {
      // Python/Pydantic count Unicode code points, including spaces.
      final length = value.text.runes.length;
      // Advisory only: length and confirmation remain the only requirements.
      final variety = [
        RegExp(r'[A-ZÁÉÍÓÚÜÑ]').hasMatch(value.text),
        RegExp(r'[0-9]').hasMatch(value.text),
        RegExp(r'[^\p{L}\p{N}\s]', unicode: true).hasMatch(value.text),
      ].where((present) => present).length;
      final strength =
          length < minimumPasswordLength || value.text.runes.toSet().length < 5
          ? 0
          : length >= 24 || (length >= 20 && variety >= 2)
          ? 3
          : length >= 20 || variety >= 2
          ? 2
          : 1;
      final strengthLabel = ['Muy débil', 'Débil', 'Buena', 'Fuerte'][strength];
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final requirement in [
              (
                length >= minimumPasswordLength,
                'Al menos $minimumPasswordLength caracteres',
              ),
              (
                RegExp(r'[A-ZÁÉÍÓÚÜÑ]').hasMatch(value.text),
                'Al menos una letra mayúscula',
              ),
              (RegExp(r'[0-9]').hasMatch(value.text), 'Al menos un número'),
              (
                RegExp(r'[^\p{L}\p{N}\s]', unicode: true).hasMatch(value.text),
                'Al menos un carácter especial',
              ),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      requirement.$1
                          ? Icons.check_circle_outline
                          : Icons.cancel_outlined,
                      size: 16,
                      color: requirement.$1 ? salud : muted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${requirement.$2}: ${requirement.$1 ? 'cumplido' : 'pendiente'}',
                        style: const TextStyle(fontSize: 12, color: muted),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Text(
              'Fortaleza estimada: ${length == 0 ? 'Sin contraseña' : strengthLabel}',
              style: const TextStyle(fontSize: 12, color: ink),
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: length == 0 ? 0 : (strength + 1) / 4,
              backgroundColor: border,
              color: strength < 2 ? brand : salud,
              semanticsLabel: 'Fortaleza estimada',
              semanticsValue: length == 0 ? 'Sin contraseña' : strengthLabel,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            const Text(
              'Una frase larga y fácil de recordar es más segura.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ],
        ),
      );
    },
  );
  @override
  void initState() {
    super.initState();
    resetToken = Uri.base.queryParameters['reset_token'];
    mode = resetToken == null ? 'login' : 'reset';
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    confirmation.dispose();
    code.dispose();
    super.dispose();
  }

  void go(String next) => setState(() {
    mode = next;
    error = null;
    password.clear();
    confirmation.clear();
    code.clear();
    show = false;
  });
  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final api = widget.api;
      if (mode == 'login' || mode == 'verify') {
        final result = mode == 'login'
            ? await api.post('/auth/login', {
                'correo': email.text.trim(),
                'password': password.text,
              })
            : await api.post('/auth/verify', {
                'token': challenge,
                'code': code.text,
              });
        if (!mounted) return;
        if (result['requires_2fa'] == true) {
          challenge = result['token'] as String;
          go('verify');
        } else {
          api.token = result['token'] as String;
          widget.onLogin(Map<String, dynamic>.from(result['user']));
        }
      } else {
        final path = {
          'recover': '/auth/forgot-password',
          'reset': '/auth/reset-password',
          'register': '/auth/request-access',
        }[mode]!;
        final data = mode == 'recover'
            ? {'correo': email.text.trim()}
            : mode == 'reset'
            ? {'token': resetToken, 'password': password.text}
            : {'correo': email.text.trim(), 'password': password.text};
        final result = await api.post(path, data);
        if (!mounted) return;
        message = result['message'] as String;
        go(mode == 'recover' ? 'mail' : 'done');
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final newPassword = mode == 'register' || mode == 'reset';
    final title = {
      'login': 'Iniciar sesión',
      'recover': 'Recuperar contraseña',
      'register': 'Solicitar acceso',
      'reset': 'Restablecer contraseña',
      'verify': 'Verificación en dos pasos',
      'mail': 'Revisa tu correo',
      'done': 'Listo',
    }[mode]!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Image.asset('assets/nl-logo.png', height: 72),
            const SizedBox(height: 18),
            const Text(
              'SIESAS · EJECUTIVO',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: brand,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 28),
            if (mode == 'mail' || mode == 'done') ...[
              Icon(
                mode == 'mail'
                    ? Icons.mark_email_read_outlined
                    : Icons.check_circle_outline,
                size: 54,
                color: salud,
              ),
              const SizedBox(height: 20),
              Notice(message),
              FilledButton(
                onPressed: () => go('login'),
                child: const Text('Volver al inicio de sesión'),
              ),
            ] else
              Form(
                key: form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (mode == 'recover')
                      const Notice(
                        'Escribe el correo asociado a tu cuenta. Te enviaremos un enlace para elegir una nueva contraseña.',
                      ),
                    if (mode == 'login')
                      const Notice(
                        'Consulta las solicitudes y los indicadores de tu estado con tu cuenta autorizada.',
                      ),
                    if (mode != 'verify' && mode != 'reset')
                      LabeledField(
                        'Correo electrónico',
                        TextFormField(
                          controller: email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(
                            hintText: 'correo@ejemplo.com',
                          ),
                          maxLength: 150,
                          validator: (v) =>
                              RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                  .hasMatch(v?.trim() ?? '')
                              ? null
                              : 'Ingresa un correo válido.',
                        ),
                      ),
                    if (mode == 'login' || newPassword) ...[
                      LabeledField(
                        mode == 'reset' ? 'Nueva contraseña' : 'Contraseña',
                        TextFormField(
                          controller: password,
                          obscureText: !show,
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: [
                            newPassword
                                ? AutofillHints.newPassword
                                : AutofillHints.password,
                          ],
                          validator: (v) {
                            final n = (v ?? '').runes.length;
                            return n <
                                        (newPassword
                                            ? minimumPasswordLength
                                            : 1) ||
                                    n > maximumPasswordLength
                                ? (newPassword
                                      ? 'Usa de $minimumPasswordLength a $maximumPasswordLength caracteres.'
                                      : 'Ingresa tu contraseña.')
                                : null;
                          },
                        ),
                      ),
                      if (newPassword) passwordRequirements(),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                        title: const Text('Mostrar contraseña'),
                        value: show,
                        onChanged: (v) => setState(() => show = v!),
                      ),
                    ],
                    if (newPassword) ...[
                      LabeledField(
                        'Confirmar contraseña',
                        TextFormField(
                          controller: confirmation,
                          obscureText: !show,
                          validator: (v) => v == password.text
                              ? null
                              : 'Las contraseñas no coinciden.',
                        ),
                      ),
                      ListenableBuilder(
                        listenable: Listenable.merge([password, confirmation]),
                        builder: (context, _) {
                          final pending = confirmation.text.isEmpty;
                          final matches =
                              !pending && confirmation.text == password.text;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Semantics(
                              liveRegion: true,
                              child: Row(
                                children: [
                                  Icon(
                                    pending
                                        ? Icons.radio_button_unchecked
                                        : matches
                                        ? Icons.check_circle_outline
                                        : Icons.error_outline,
                                    size: 16,
                                    color: matches ? salud : muted,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      pending
                                          ? 'Confirma tu contraseña.'
                                          : matches
                                          ? 'Las contraseñas coinciden.'
                                          : 'Las contraseñas no coinciden.',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: muted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                    if (mode == 'verify') ...[
                      const Notice(
                        'Introduce el código de tu aplicación de autenticación. La verificación vence en 5 minutos.',
                      ),
                      LabeledField(
                        'Código de verificación',
                        TextFormField(
                          controller: code,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          autofillHints: const [AutofillHints.oneTimeCode],
                          validator: (v) => RegExp(r'^\d{6}$').hasMatch(v ?? '')
                              ? null
                              : 'Ingresa los 6 dígitos.',
                        ),
                      ),
                    ],
                    if (mode == 'register')
                      const Notice(
                        'La administración debe autorizar tu cuenta y asignar tu estado antes de habilitar el acceso.',
                      ),
                    if (error != null) Notice(error!, error: true),
                    FilledButton(
                      onPressed: busy ? null : submit,
                      child: busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              {
                                'login': 'Iniciar sesión',
                                'recover': 'Enviar enlace',
                                'reset': 'Guardar contraseña',
                                'register': 'Solicitar acceso',
                                'verify': 'Verificar',
                              }[mode]!,
                            ),
                    ),
                    const SizedBox(height: 16),
                    if (mode == 'login') ...[
                      TextButton(
                        onPressed: busy ? null : () => go('recover'),
                        child: const Text('¿Olvidaste tu contraseña?'),
                      ),
                      TextButton(
                        onPressed: busy ? null : () => go('register'),
                        child: const Text('Solicitar cuenta ejecutiva'),
                      ),
                    ] else
                      TextButton(
                        onPressed: busy ? null : () => go('login'),
                        child: const Text('Volver al inicio de sesión'),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 32),
            const Text(
              'Secretaría de Salud · Nuevo León',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: muted),
            ),
          ],
        ),
      ),
    );
  }
}
