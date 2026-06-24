import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nakkda/features/file_list/data/file_list_repository_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FileListRepositoryImpl', () {
    late FileListRepositoryImpl repository;
    late Directory tempDir;

    setUp(() async {
      // 요약 캐시(_loadCache)가 SharedPreferences를 사용하므로 목을 깔아준다.
      SharedPreferences.setMockInitialValues({});
      repository = FileListRepositoryImpl();
      tempDir = await Directory.systemTemp.createTemp('file_list_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('listFiles', () {
      test('빈 디렉토리이면 빈 리스트를 반환한다', () async {
        final result = await repository.listFiles(tempDir.path);

        expect(result, isEmpty);
      });

      test('존재하지 않는 경로이면 빈 리스트를 반환한다', () async {
        final nonExistentPath = '${tempDir.path}/nonexistent';

        final result = await repository.listFiles(nonExistentPath);

        expect(result, isEmpty);
      });

      test('날짜 형식 .md 파일이 있으면 FileSummary 리스트를 반환한다', () async {
        final mdFile = File('${tempDir.path}/2025-06-01.md');
        await mdFile.writeAsString('### 09:30\n메모 내용\n### 10:15\n두 번째 메모\n');

        final result = await repository.listFiles(tempDir.path);

        expect(result.length, 1);
        expect(result.first.displayName, '2025-06-01');
        expect(result.first.entryCount, 2);
      });

      test('날짜 형식이 아닌 .md 파일은 무시된다', () async {
        final validFile = File('${tempDir.path}/2025-06-01.md');
        await validFile.writeAsString('### 09:00\n내용\n');
        final invalidFile = File('${tempDir.path}/notes.md');
        await invalidFile.writeAsString('### 09:00\n내용\n');

        final result = await repository.listFiles(tempDir.path);

        expect(result.length, 1);
        expect(result.first.displayName, '2025-06-01');
      });

      test('여러 파일이 있으면 날짜 내림차순으로 정렬된다', () async {
        final file1 = File('${tempDir.path}/2025-06-01.md');
        await file1.writeAsString('### 09:00\n내용\n');
        final file2 = File('${tempDir.path}/2025-06-03.md');
        await file2.writeAsString('### 10:00\n내용\n');
        final file3 = File('${tempDir.path}/2025-06-02.md');
        await file3.writeAsString('### 11:00\n내용\n');

        final result = await repository.listFiles(tempDir.path);

        expect(result.length, 3);
        expect(result[0].displayName, '2025-06-03');
        expect(result[1].displayName, '2025-06-02');
        expect(result[2].displayName, '2025-06-01');
      });
    });

    group('_countEntries (### HH:mm 패턴 카운트)', () {
      test('### HH:mm 패턴이 3개인 파일은 entryCount 3을 반환한다', () async {
        final file = File('${tempDir.path}/2025-06-01.md');
        await file.writeAsString(
          '# 2025-06-01\n\n'
          '### 09:00\n음성 메모 내용\n\n'
          '### 12:30\n점심 후 기록\n\n'
          '### 18:45\n저녁 메모\n',
        );

        final result = await repository.listFiles(tempDir.path);

        expect(result.first.entryCount, 3);
      });

      test('### 로 시작하지 않는 헤더는 카운트하지 않는다', () async {
        final file = File('${tempDir.path}/2025-06-01.md');
        await file.writeAsString(
          '# 제목\n'
          '## 부제목\n'
          '### 09:00\n실제 메모\n'
          '#### 하위 헤더\n',
        );

        final result = await repository.listFiles(tempDir.path);

        expect(result.first.entryCount, 1);
      });

      test('메모가 없는 빈 파일은 entryCount 0을 반환한다', () async {
        final file = File('${tempDir.path}/2025-06-01.md');
        await file.writeAsString('# 2025-06-01\n\n아무 메모도 없음\n');

        final result = await repository.listFiles(tempDir.path);

        expect(result.first.entryCount, 0);
      });
    });
  });
}
