import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

/// Writes the PNG with `navigator.clipboard.write`. The clipboard item is
/// created right away with a pending image, so the browser still sees the
/// click that started it while the chart is being rendered.
Future<bool> copyPngToClipboard(Future<Uint8List> png) async {
  final navigator = globalContext['navigator'] as JSObject?;
  final clipboard = navigator?['clipboard'] as JSObject?;
  final itemType = globalContext['ClipboardItem'] as JSFunction?;
  final blobType = globalContext['Blob'] as JSFunction?;
  if (clipboard == null ||
      itemType == null ||
      blobType == null ||
      !clipboard.has('write')) {
    await png;
    return false;
  }
  try {
    final blob = png.then<JSObject>((bytes) {
      final options = JSObject()..['type'] = 'image/png'.toJS;
      return blobType.callAsConstructor<JSObject>(
        <JSAny>[bytes.toJS].toJS,
        options,
      );
    });
    final data = JSObject()..['image/png'] = blob.toJS;
    final item = itemType.callAsConstructor<JSObject>(data);
    await clipboard
        .callMethod<JSPromise<JSAny?>>('write'.toJS, <JSAny>[item].toJS)
        .toDart;
    return true;
  } catch (_) {
    return false;
  }
}
