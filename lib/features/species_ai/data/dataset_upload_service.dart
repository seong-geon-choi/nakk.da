import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/api_keys.dart';

/// 사용자가 확정한 {사진, 어종}을 전용 Google 계정 Drive(Apps Script 웹앱)로 업로드.
///
/// - 업로드 전 **EXIF(GPS) 제거 + 512px 축소** 후 JPEG 재인코딩(용량·사생활 보호).
/// - 동일 사진 **중복 업로드 방지**(로컬 기록).
/// - 엔드포인트(api_keys.dart) 미설정 또는 어종 미확정 시 **no-op**.
///
/// 옵트인 동의(settings.contributeImages) 확인은 호출부에서 수행한다.
class DatasetUploadService {
  static const _uploadedKey = 'dataset_uploaded_keys';
  static const int _maxSide = 512;
  static const int _historyCap = 500;

  bool get isConfigured =>
      kDatasetUploadUrl.isNotEmpty && kDatasetUploadToken.isNotEmpty;

  /// [dedupKey](보통 photoPath)가 이미 업로드됐거나 미설정이면 건너뛴다. 성공 시 true.
  Future<bool> upload({
    required Uint8List photoBytes,
    required String species,
    required String dedupKey,
    double? aiConfidence,
  }) async {
    if (!isConfigured || species.trim().isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getStringList(_uploadedKey) ?? <String>[];
    if (done.contains(dedupKey)) return false;

    final jpeg = _downscaleStripExif(photoBytes);
    if (jpeg == null) return false;

    try {
      var resp = await http.post(
        Uri.parse(kDatasetUploadUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'token': kDatasetUploadToken,
          'species': species.trim(),
          'image': base64Encode(jpeg),
          'aiConfidence': ?aiConfidence,
          'ts': DateTime.now().toIso8601String(),
        }),
      );
      // Apps Script는 302로 결과 URL을 준다 → GET으로 따라가 실제 응답을 받는다.
      // (dart:io는 POST의 리다이렉트를 자동 추종하지 않음)
      if (resp.statusCode >= 301 && resp.statusCode <= 307) {
        final loc = resp.headers['location'];
        if (loc != null) resp = await http.get(Uri.parse(loc));
      }
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        if (body is Map && body['ok'] == true) {
          done.add(dedupKey);
          final trimmed = done.length > _historyCap
              ? done.sublist(done.length - _historyCap)
              : done;
          await prefs.setStringList(_uploadedKey, trimmed);
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  /// 회전 반영 → 512px 이내로 축소 → JPEG 재인코딩(EXIF 제거).
  Uint8List? _downscaleStripExif(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final oriented = img.bakeOrientation(decoded);
    final resized = (oriented.width > _maxSide || oriented.height > _maxSide)
        ? img.copyResize(
            oriented,
            width: oriented.width >= oriented.height ? _maxSide : null,
            height: oriented.height > oriented.width ? _maxSide : null,
          )
        : oriented;
    return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
  }
}
