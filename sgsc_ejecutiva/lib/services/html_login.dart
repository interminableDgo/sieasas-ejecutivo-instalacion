/// Bridge with the HTML login in web/index.html.
///
/// On the web the first login screen is plain HTML, so the page is usable
/// before Flutter loads. The HTML form only collects what the person typed:
/// when they press a button it hands the data to Flutter, and the Flutter
/// login screen does the rest (validation, API calls, errors, two-step
/// verification). Elsewhere (tests, other platforms) there is no HTML login.
library;

export 'html_login_stub.dart'
    if (dart.library.js_interop) 'html_login_web.dart';
