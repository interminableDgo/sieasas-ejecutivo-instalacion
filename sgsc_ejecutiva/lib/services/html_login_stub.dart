import 'html_login_data.dart';

export 'html_login_data.dart';

/// Without a browser there is no HTML login: Flutter shows its own.
bool htmlLoginActive() => false;

void listenHtmlLogin(void Function(HtmlLoginHandoff handoff) onHandoff) {}

void removeHtmlLogin() {}
