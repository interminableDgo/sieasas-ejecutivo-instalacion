import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'html_login_data.dart';

export 'html_login_data.dart';

/// `window.siesasLogin`, created by web/index.html.
JSObject? get _bridge => globalContext['siesasLogin'] as JSObject?;

/// True while the HTML login is on screen and waiting for the person.
bool htmlLoginActive() => (_bridge?['activo'] as JSBoolean?)?.toDart ?? false;

/// Calls [onHandoff] once, when the HTML form hands over its data (right away
/// if that already happened while Flutter was loading).
void listenHtmlLogin(void Function(HtmlLoginHandoff handoff) onHandoff) {
  final bridge = _bridge;
  if (bridge == null) return;
  var done = false;
  void receive() {
    final data = bridge['entrada'] as JSObject?;
    if (done || data == null) return;
    done = true;
    // The password must not stay in a page global once Flutter has it.
    bridge['entrada'] = null;
    String text(String key) => (data[key] as JSString?)?.toDart ?? '';
    final mode = text('modo');
    onHandoff(
      HtmlLoginHandoff(
        mode: HtmlLoginHandoff.modes.contains(mode) ? mode : 'login',
        email: text('correo'),
        password: text('password'),
        submit: (data['enviar'] as JSBoolean?)?.toDart ?? false,
      ),
    );
  }

  bridge['alEntregar'] = receive.toJS;
  receive();
}

/// Removes the HTML login once Flutter shows the same screen.
void removeHtmlLogin() {
  final bridge = _bridge;
  if (bridge != null && bridge.has('quitar')) {
    bridge.callMethod<JSAny?>('quitar'.toJS);
  }
}
