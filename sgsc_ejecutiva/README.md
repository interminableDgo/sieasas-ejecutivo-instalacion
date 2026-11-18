# Flutter · SIESAS Ejecutivo

Desde SGSC, `./iniciar.ps1` abre los servicios locales ya compilados; la aplicación está en https://127.0.0.1:5173.

Para desarrollo, usa Flutter 3.47.5 / Dart 3.13.4 o una versión compatible con pubspec.yaml:

```powershell
flutter pub get
flutter test --no-pub
flutter build web --no-pub --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

En esta computadora se utilizó `dart pub get` y luego `flutter ... --no-pub` porque Windows no tiene habilitado el soporte de enlaces simbólicos para plugins de escritorio. Web compila y se prueba sin cambiar ajustes del sistema. La compilación de escritorio Windows requiere configurar ese soporte.

API_BASE_URL se define al compilar. En Android emulado, el valor predeterminado es http://10.0.2.2:8000; en web y escritorio, http://127.0.0.1:8000. Un dispositivo físico y cualquier publicación deben usar la URL HTTPS del backend.

Los datos de prueba de test/widget_test.dart sólo existen en el cliente HTTP simulado de las pruebas; nunca se utilizan en la aplicación. SCREENSHOT_DIR permite capturar vistas de verificación durante las pruebas.

Consulta ../README.md para alcance, estados vacíos y pendientes de configuración.
