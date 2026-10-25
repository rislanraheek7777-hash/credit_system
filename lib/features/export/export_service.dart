import 'dart:io';
import 'package:pdf/widgets.dart' as pw;

class ExportService {
  static const _piiKeywords = ['phone', 'email', 'nid', 'national', 'ssn', 'address', 'name'];

  bool _isPiiField(String fieldName) {
    final lower = fieldName.toLowerCase();
    return _piiKeywords.any((k) => lower.contains(k));
  }

  String _maskPii(String value) {
    if (value.length <= 4) return '****';
    return '****${value.substring(value.length - 4)}';
  }

  Future<void> exportCsv(
    List<Map<String, dynamic>> rows,
    String path, {
    bool maskPii = true,
    void Function(String action)? onAudit,
  }) async {
    if (rows.isEmpty) {
      await File(path).writeAsString('');
      onAudit?.call('export_csv_empty');
      return;
    }
    final headers = rows.first.keys.toList();
    final buffer = StringBuffer();
    buffer.writeln(headers.join(','));
    for (final row in rows) {
      final values = headers.map((h) {
        final v = row[h]?.toString() ?? '';
        final masked = (maskPii && _isPiiField(h)) ? _maskPii(v) : v;
        return '"$masked"';
      }).join(',');
      buffer.writeln(values);
    }
    await File(path).writeAsString(buffer.toString());
    onAudit?.call('export_csv rows=${rows.length} masked=$maskPii');
  }

  Future<void> exportPdf(
    List<Map<String, dynamic>> rows,
    String path, {
    bool maskPii = true,
    void Function(String action)? onAudit,
  }) async {
    final pdf = pw.Document();
    if (rows.isEmpty) {
      pdf.addPage(pw.Page(build: (_) => pw.Center(child: pw.Text('No data'))));
    } else {
      final headers = rows.first.keys.toList();
      pdf.addPage(
        pw.Page(
          build: (_) => pw.TableHelper.fromTextArray(
            headers: headers,
            data: rows.map((r) => headers.map((h) {
                  final v = r[h]?.toString() ?? '';
                  return (maskPii && _isPiiField(h)) ? _maskPii(v) : v;
                }).toList()).toList(),
          ),
        ),
      );
    }
    final bytes = await pdf.save();
    await File(path).writeAsBytes(bytes);
    onAudit?.call('export_pdf rows=${rows.length} masked=$maskPii');
  }
}