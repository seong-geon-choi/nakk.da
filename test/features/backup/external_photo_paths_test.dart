import 'package:flutter_test/flutter_test.dart';
import 'package:nakkda/features/backup/presentation/backup_provider.dart';

void main() {
  group('BackupNotifier.externalPhotoPaths', () {
    test('절대경로 사진만 추출하고 photos/ 상대경로는 제외', () {
      const content = '''
# 2026-01-17

---

### 2026-01-17 08:00:00 | 🛰 37.4, 126.5
![](/storage/emulated/0/DCIM/Camera/IMG_1.jpg)
첫 메모

---

### 2026-01-17 09:00:00 | 🛰 37.4, 126.5
![](photos/import_1.jpg)
복사된 메모
''';
      final paths = BackupNotifier.externalPhotoPaths(content);
      expect(paths, ['/storage/emulated/0/DCIM/Camera/IMG_1.jpg']);
    });

    test('content:// 및 동영상 참조는 제외', () {
      const content = '''
### 2026-01-17 10:00:00
![](content://media/external/images/media/123)
[video](content://media/external/video/media/9)
''';
      expect(BackupNotifier.externalPhotoPaths(content), isEmpty);
    });

    test('여러 절대경로 모두 추출', () {
      const content = '''
![](/storage/emulated/0/DCIM/a.jpg)
![](/storage/emulated/0/Pictures/b.jpg)
''';
      expect(BackupNotifier.externalPhotoPaths(content), [
        '/storage/emulated/0/DCIM/a.jpg',
        '/storage/emulated/0/Pictures/b.jpg',
      ]);
    });

    test('사진 없으면 빈 목록', () {
      expect(BackupNotifier.externalPhotoPaths('# 2026-01-17\n메모만'), isEmpty);
    });
  });
}
