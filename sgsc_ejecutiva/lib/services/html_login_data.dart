/// What the HTML login hands to Flutter: the screen to open, what the person
/// typed and whether to submit right away (they pressed «Iniciar sesión»).
class HtmlLoginHandoff {
  /// `login`, `recover` or `register`.
  final String mode;
  final String email;
  final String password;
  final bool submit;

  const HtmlLoginHandoff({
    required this.mode,
    this.email = '',
    this.password = '',
    this.submit = false,
  });

  static const modes = {'login', 'recover', 'register'};
}
