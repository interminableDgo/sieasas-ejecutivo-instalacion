import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/theme.dart';
import 'screens/auth/login_screen.dart';
// Carga diferida: el tablero (gráficas, exportación, registro) no se descarga ni se procesa
// para mostrar el inicio de sesión; se precarga en cuanto el usuario interactúa con él.
import 'screens/dashboard/dashboard_screen.dart' deferred as dashboard;
import 'services/executive_api.dart';
import 'services/html_login.dart';

void main() {
  runApp(const SgscApp());
}

class SgscApp extends StatefulWidget {
  final ExecutiveApi? api;
  const SgscApp({super.key, this.api});
  @override
  State<SgscApp> createState() => _SgscAppState();
}

class _SgscAppState extends State<SgscApp> {
  late final ExecutiveApi api = widget.api ?? ExecutiveApi();
  Map<String, dynamic>? user;
  Future<void>? _dashboardLoad;

  /// En la web, el primer inicio de sesión es HTML (web/index.html): Flutter
  /// se carga detrás mientras la persona escribe y toma el control cuando
  /// presiona un botón, con lo que escribió.
  bool _waitingForHtml = false;
  HtmlLoginHandoff? _handoff;

  Future<void> _loadDashboard() =>
      _dashboardLoad ??= dashboard.loadLibrary().catchError((Object error) {
        _dashboardLoad = null; // permite reintentar
        throw error;
      });

  @override
  void initState() {
    super.initState();
    if (!htmlLoginActive()) return;
    _waitingForHtml = true;
    // La persona ya está escribiendo: el tablero se descarga mientras tanto.
    _loadDashboard().ignore();
    listenHtmlLogin((handoff) {
      if (!mounted) return;
      setState(() {
        _waitingForHtml = false;
        _handoff = handoff;
      });
      // El HTML se retira cuando Flutter ya dibujó la misma pantalla.
      WidgetsBinding.instance.addPostFrameCallback((_) => removeHtmlLogin());
    });
  }

  @override
  void dispose() {
    if (widget.api == null) api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('es', 'MX'),
      supportedLocales: const [Locale('es', 'MX')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      title: 'SGSC Ejecutiva',
      theme: executiveTheme(),
      // Mobile-first: on a wide browser window (quick tests before running on
      // iPhone) the whole navigator, including sheets, dialogs and menus,
      // behaves like a phone screen. On a phone this changes nothing.
      builder: (context, child) => LayoutBuilder(
        builder: (context, box) {
          final width = box.maxWidth.clamp(0.0, phoneMaxWidth);
          return ColoredBox(
            color: border,
            child: Center(
              child: SizedBox(
                width: width,
                child: MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(size: Size(width, box.maxHeight)),
                  child: child!,
                ),
              ),
            ),
          );
        },
      ),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: phoneMaxWidth),
              child: user == null && _waitingForHtml
                  // Debajo del formulario HTML: nada que enfocar ni leer.
                  ? const SizedBox.expand()
                  : user == null
                  ? Listener(
                      onPointerDown: (_) => _loadDashboard().ignore(),
                      child: Focus(
                        canRequestFocus: false,
                        skipTraversal: true,
                        onFocusChange: (_) => _loadDashboard().ignore(),
                        child: LoginScreen(
                          key: ObjectKey(_handoff),
                          api: api,
                          initialMode: _handoff?.mode,
                          initialEmail: _handoff?.email ?? '',
                          initialPassword: _handoff?.password ?? '',
                          submitOnStart: _handoff?.submit ?? false,
                          onLogin: (value) => setState(() {
                            user = value;
                            _handoff = null; // no conservar la contraseña
                          }),
                        ),
                      ),
                    )
                  : FutureBuilder<void>(
                      future: _loadDashboard(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Center(
                            child: CircularProgressIndicator(
                              semanticsLabel: 'Cargando tablero',
                            ),
                          );
                        }
                        if (snapshot.hasError) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'No se pudo cargar el tablero. '
                                    'Revisa tu conexión.',
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton(
                                    onPressed: () => setState(() {}),
                                    child: const Text('Reintentar'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        return dashboard.DashboardScreen(
                          api: api,
                          user: user!,
                          onLogout: () => setState(() {
                            user = null;
                            api.token = null;
                          }),
                        );
                      },
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
