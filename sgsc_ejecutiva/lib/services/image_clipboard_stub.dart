import 'dart:typed_data';

/// Without a browser clipboard there is nothing to copy to; the caller shares
/// the image instead.
Future<bool> copyPngToClipboard(Future<Uint8List> png) async {
  await png;
  return false;
}
