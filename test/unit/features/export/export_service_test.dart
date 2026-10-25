import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:credit_system/features/export/export_service.dart';

void main() {
  group('ExportService', () {
    late Directory tempDir;
    late ExportService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('export_test_');
      service = ExportService();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('exportCsv masks PII by default and calls audit', () async {
      final rows = [
        {'name': 'Alice', 'phone': '0771234567', 'balance': 100},
      ];
      final path = p.join(tempDir.path, 'out.csv');
      final audits = <String>[];
      await service.exportCsv(rows, path, onAudit: audits.add);
      final content = await File(path).readAsString();
      expect(content, contains('****4567'));
      expect(content, contains('100'));
      expect(audits, isNotEmpty);
      expect(audits.first, contains('export_csv'));
    });

    test('exportCsv can disable masking', () async {
      final rows = [
        {'name': 'Alice', 'phone': '0771234567'},
      ];
      final path = p.join(tempDir.path, 'out2.csv');
      await service.exportCsv(rows, path, maskPii: false);
      final content = await File(path).readAsString();
      expect(content, contains('0771234567'));
      expect(content, isNot(contains('****')));
    });

    test('exportCsv empty writes empty file', () async {
      final path = p.join(tempDir.path, 'empty.csv');
      final audits = <String>[];
      await service.exportCsv([], path, onAudit: audits.add);
      expect(await File(path).readAsString(), isEmpty);
      expect(audits, contains('export_csv_empty'));
    });

    test('exportPdf writes non-empty bytes and audits', () async {
      final rows = [
        {'name': 'Alice', 'phone': '0771234567', 'balance': 100},
      ];
      final path = p.join(tempDir.path, 'out.pdf');
      final audits = <String>[];
      await service.exportPdf(rows, path, onAudit: audits.add);
      final bytes = await File(path).readAsBytes();
      expect(bytes, isNotEmpty);
      expect(audits, isNotEmpty);
      expect(audits.first, contains('export_pdf'));
    });
  });
}
