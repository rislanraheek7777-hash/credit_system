import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Saves the generated voucher PDF to the app's documents directory using
/// `path_provider` and returns the file path so the UI can surface it to the
/// operator. Does not launch an external PDF viewer (no `url_launcher` or
/// `open_file` dependency is approved for this story).
Future<String?> viewVoucherPdf(Uint8List bytes, String fileName) async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File(p.join(dir.path, fileName));
  await file.writeAsBytes(bytes);
  return file.path;
}
