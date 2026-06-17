import 'dart:io';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../../features/memo/domain/models/memo_entry.dart';
import '../../features/location/domain/models/location_status.dart';
import 'saf_service.dart';

/// 하루치 메모(blocks)를 본문 텍스트 + 사진 파일로 안드로이드 시스템 공유 시트에 내보낸다.
/// 사용자가 공유 시트에서 네이버 카페/블로그 등 원하는 앱을 직접 선택해 발행한다.
class MemoShareService {
  final _saf = SafService();

  static bool _isAbsolute(String path) =>
      path.startsWith('/') || RegExp(r'^[A-Za-z]:[/\\]').hasMatch(path);

  Future<void> shareDay({
    required List<dynamic> blocks,
    required String displayName,
    required String savePath,
  }) async {
    final text = _buildText(blocks, displayName);
    // 일부 앱(블로그 등)은 다중 사진 공유 시 본문(EXTRA_TEXT)을 무시한다.
    // 그 경우에도 사용자가 붙여넣을 수 있도록 본문을 클립보드에 복사해 둔다.
    await Clipboard.setData(ClipboardData(text: text));
    final photos = await _resolvePhotos(blocks, savePath);
    if (photos.isEmpty) {
      await Share.share(text, subject: displayName);
    } else {
      await Share.shareXFiles(photos, text: text, subject: displayName);
    }
  }

  // ── 본문 평문 구성 ─────────────────────────────────────────
  String _buildText(List<dynamic> blocks, String displayName) {
    final sb = StringBuffer()..writeln(displayName);
    for (final b in blocks) {
      if (b is MemoEntry) {
        final line = _entryLine(b);
        if (line != null) sb.writeln('${b.timeLabel}  $line');
      } else if (b is LocationStatus) {
        final line = _envLine(b);
        if (line != null) sb.writeln(line);
      }
    }
    return sb.toString().trimRight();
  }

  /// 메모 항목의 텍스트 부분(어종/길이/메모). 사진뿐이고 텍스트 없으면 null.
  String? _entryLine(MemoEntry b) {
    final parts = <String>[];
    final species = b.fishSpecies?.trim();
    if (species != null && species.isNotEmpty) {
      final len = b.fishLength != null ? ' ${_fmtLen(b.fishLength!)}cm' : '';
      parts.add('$species$len');
    }
    final t = b.text?.trim();
    if (t != null && t.isNotEmpty) parts.add(t);
    if (parts.isEmpty) return null;
    return parts.join('  ');
  }

  String _fmtLen(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  String? _envLine(LocationStatus s) {
    final parts = <String>[];
    final addr = s.address?.trim();
    if (addr != null && addr.isNotEmpty) parts.add('📍 $addr');
    if (s.temperature != null) parts.add('🌡 ${s.temperature!.toStringAsFixed(1)}℃');
    if (s.tideName != null && s.tideName!.isNotEmpty) parts.add('🌊 ${s.tideName}');
    if (s.waterTemp != null) parts.add('수온 ${s.waterTemp!.toStringAsFixed(1)}℃');
    if (parts.isEmpty) return null;
    final h = s.timestamp.hour.toString().padLeft(2, '0');
    final m = s.timestamp.minute.toString().padLeft(2, '0');
    return '$h:$m  ${parts.join(' | ')}';
  }

  // ── 사진 파일 해석 (공유 첨부용) ───────────────────────────
  Future<List<XFile>> _resolvePhotos(
      List<dynamic> blocks, String savePath) async {
    final result = <XFile>[];
    Directory? tmp;
    for (final b in blocks) {
      if (b is! MemoEntry || b.photoPath == null) continue;
      final p = b.photoPath!;
      var eff = p;
      if (_isAbsolute(p) && !File(p).existsSync()) {
        eff = 'photos/${p.split('/').last}';
      }

      if (_isAbsolute(eff)) {
        if (File(eff).existsSync()) result.add(XFile(eff, mimeType: 'image/jpeg'));
      } else if (SafService.isSafUri(savePath)) {
        final bytes = await _saf.readSafImage(savePath, eff);
        if (bytes != null) {
          tmp ??= await getTemporaryDirectory();
          final file = File('${tmp.path}/share_${eff.split('/').last}');
          await file.writeAsBytes(bytes);
          result.add(XFile(file.path, mimeType: 'image/jpeg'));
        }
      } else {
        final resolved = '$savePath/$eff';
        if (File(resolved).existsSync()) {
          result.add(XFile(resolved, mimeType: 'image/jpeg'));
        }
      }
    }
    return result;
  }
}
