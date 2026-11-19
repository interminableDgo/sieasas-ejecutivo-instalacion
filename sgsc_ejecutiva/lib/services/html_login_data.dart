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

/// The three operations the app needs from the HTML login. In the browser
/// they come from html_login_web.dart; tests pass their own.
class HtmlLoginBridge {
  /// True while the HTML login is on screen and waiting for the person.
  final bool Function() isActive;

  /// Calls the callback once, when the HTML form hands over its data.
  final void Function(void Function(HtmlLoginHandoff handoff) onHandoff) listen;

  /// Removes the HTML login once Flutter shows the same screen.
  final void Function() remove;

  const HtmlLoginBridge({
    required this.isActive,
    required this.listen,
    required this.remove,
  });
}
