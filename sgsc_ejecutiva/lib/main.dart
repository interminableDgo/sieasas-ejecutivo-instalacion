import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/theme.dart';
import 'screens/auth/login_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'services/executive_api.dart';

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
              child: user == null
                  ? LoginScreen(
                      api: api,
                      onLogin: (value) => setState(() => user = value),
                    )
                  : DashboardScreen(
                      api: api,
                      user: user!,
                      onLogout: () => setState(() {
                        user = null;
                        api.token = null;
                      }),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
