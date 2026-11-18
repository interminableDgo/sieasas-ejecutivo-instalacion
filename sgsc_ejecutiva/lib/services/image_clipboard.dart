/// Copies a PNG image to the system clipboard where the platform allows it.
/// On the web this uses the asynchronous Clipboard API; elsewhere it reports
/// that copying is not available so the caller can share the file instead.
library;

export 'image_clipboard_stub.dart'
    if (dart.library.js_interop) 'image_clipboard_web.dart';
