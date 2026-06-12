import 'package:flutter_test/flutter_test.dart';
import 'package:nakkda/features/file_list/domain/models/file_summary.dart';

void main() {
  group('FileSummary', () {
    test('생성자에서 모든 필드가 올바르게 저장된다', () {
      final date = DateTime(2025, 6, 1);
      const filePath = '/storage/emulated/0/VoRec/2025-06-01.md';
      const displayName = '2025-06-01';
      const entryCount = 3;

      final summary = FileSummary(
        date: date,
        filePath: filePath,
        displayName: displayName,
        entryCount: entryCount,
      );

      expect(summary.date, date);
      expect(summary.filePath, filePath);
      expect(summary.displayName, displayName);
      expect(summary.entryCount, entryCount);
    });

    test('entryCount가 0인 경우에도 올바르게 저장된다', () {
      final date = DateTime(2025, 1, 15);

      final summary = FileSummary(
        date: date,
        filePath: '/some/path/2025-01-15.md',
        displayName: '2025-01-15',
        entryCount: 0,
      );

      expect(summary.entryCount, 0);
    });

    test('날짜 외 이름(displayName)도 허용된다', () {
      final date = DateTime(2025, 3, 10);

      final summary = FileSummary(
        date: date,
        filePath: '/some/path/meeting-notes.md',
        displayName: 'meeting-notes',
        entryCount: 5,
      );

      expect(summary.displayName, 'meeting-notes');
    });
  });
}
