import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../../core/constants/api_keys.dart';

/// 현재 사용 중인 모델 상태.
class ModelStatus {
  final bool isRemote; // 원격 다운로드 모델 사용 중(false=번들 기본 모델)
  final DateTime? updatedAt; // 원격 모델 버전(=Drive 저장 시각). 번들이면 null.
  const ModelStatus({required this.isRemote, this.updatedAt});
}

/// 원격(전용계정 Drive + Apps Script) 모델의 OTA 업데이트.
///
/// 콜드 스타트 시 매니페스트 버전을 확인해, 변경됐으면 백그라운드로 내려받아
/// 앱 문서 폴더에 원자적으로 교체 저장한다. **다음 콜드 스타트부터 반영**된다.
/// 실패·오프라인·미설정 시 조용히 no-op(기존/번들 모델 유지).
class ModelUpdateService {
  static const _versionKey = 'model_version';
  static const _dirName = 'species_model';
  static const _modelName = 'fish_model.tflite';
  static const _labelsName = 'labels.txt';

  bool get _configured =>
      kDatasetUploadUrl.isNotEmpty && kDatasetUploadToken.isNotEmpty;

  // 앱 생애 1회만 실행되도록 공유되는 체크 작업.
  // SpeciesRecognizer.load()가 이 Future를 기다려, 콜드 스타트 1회 안에
  // "체크→다운로드→로드"가 이어지게 한다(안 그러면 다음 콜드 스타트에야 반영됨).
  static Future<void>? _pending;

  /// 다운로드된 로컬 모델 폴더 경로(추론기와 공유).
  static Future<Directory> localDir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/$_dirName');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<File> localModelFile() async =>
      File('${(await localDir()).path}/$_modelName');
  static Future<File> localLabelsFile() async =>
      File('${(await localDir()).path}/$_labelsName');

  /// 현재 로드될 모델의 상태(원격/번들, 원격이면 저장 시각).
  Future<ModelStatus> currentStatus() async {
    final modelFile = await localModelFile();
    final labelsFile = await localLabelsFile();
    final isRemote = await modelFile.exists() && await labelsFile.exists();
    if (!isRemote) return const ModelStatus(isRemote: false);
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_versionKey);
    return ModelStatus(
      isRemote: true,
      updatedAt: ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null,
    );
  }

  Future<void> checkAndUpdate() => _pending ??= _checkAndUpdate();

  Future<void> _checkAndUpdate() async {
    if (!_configured) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final localVer = prefs.getInt(_versionKey) ?? 0;

      final manifest = await _get('manifest');
      if (manifest == null || manifest['ok'] != true) return;
      final remoteVer = (manifest['version'] as num).toInt();

      final modelFile = await localModelFile();
      final labelsFile = await localLabelsFile();
      final haveLocal = await modelFile.exists() && await labelsFile.exists();
      if (remoteVer == localVer && haveLocal) return; // 이미 최신

      final modelResp = await _get('model');
      final labelsResp = await _get('labels');
      if (modelResp == null || modelResp['ok'] != true) return;
      if (labelsResp == null || labelsResp['ok'] != true) return;

      final modelBytes = base64Decode(modelResp['data'] as String);
      final labelsText = (labelsResp['text'] as String);
      if (labelsText.trim().isEmpty) return;

      // 검증: 실제 로드 가능한 tflite인지 확인 후에만 교체(깨진 모델 방지)
      try {
        Interpreter.fromBuffer(modelBytes).close();
      } catch (_) {
        return;
      }

      // 원자적 교체: temp에 쓰고 rename
      final dir = await localDir();
      final tmpModel = File('${dir.path}/$_modelName.tmp');
      final tmpLabels = File('${dir.path}/$_labelsName.tmp');
      await tmpModel.writeAsBytes(modelBytes, flush: true);
      await tmpLabels.writeAsString(labelsText, flush: true);
      await tmpModel.rename(modelFile.path);
      await tmpLabels.rename(labelsFile.path);

      await prefs.setInt(_versionKey, remoteVer);
    } catch (_) {}
  }

  /// 마지막 학습에 쓰인 어종별/전체 이미지 수(stats.json). 없거나 실패하면 null.
  Future<Map<String, dynamic>?> fetchTrainStats() async {
    if (!_configured) return null;
    try {
      final resp = await _get('stats');
      if (resp == null || resp['ok'] != true) return null;
      final text = resp['text'] as String?;
      if (text == null) return null;
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _get(String action) async {
    final uri = Uri.parse(kDatasetUploadUrl).replace(queryParameters: {
      'action': action,
      'token': kDatasetUploadToken,
    });
    // GET 리다이렉트(302→googleusercontent)는 dart:io가 자동 추종.
    final resp = await http.get(uri);
    if (resp.statusCode != 200) return null;
    final decoded = jsonDecode(resp.body);
    return decoded is Map<String, dynamic> ? decoded : null;
  }
}
