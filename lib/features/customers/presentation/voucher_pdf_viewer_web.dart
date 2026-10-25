import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart';

/// Triggers a browser download of the generated voucher PDF. Returns `null`
/// because the download is handled directly by the browser; no local file
/// path is produced on Web.
Future<String?> viewVoucherPdf(Uint8List bytes, String fileName) async {
  final parts = JSArray<BlobPart>();
  parts.add(bytes.toJS);
  final blob = Blob(parts);
  final url = URL.createObjectURL(blob);
  final anchor = HTMLAnchorElement()
    ..href = url
    ..download = fileName;
  anchor.click();
  URL.revokeObjectURL(url);
  return null;
}
