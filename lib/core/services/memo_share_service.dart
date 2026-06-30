import 'dart:io';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:lunar/lunar.dart';
import '../../features/memo/domain/models/memo_entry.dart';
import '../../features/location/domain/models/location_status.dart';
import '../../features/weather/data/weather_service.dart';
import '../../features/tide/data/astro_calc.dart';
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
    List<XFile> extraImages = const [],
  }) async {
    final text = _buildText(blocks, displayName);
    // 일부 앱(블로그 등)은 다중 사진 공유 시 본문(EXTRA_TEXT)을 무시한다.
    // 그 경우에도 사용자가 붙여넣을 수 있도록 본문을 클립보드에 복사해 둔다.
    await Clipboard.setData(ClipboardData(text: text));
    final photos = await _resolvePhotos(blocks, savePath);
    // 현장정보 카드 이미지를 사진 앞에 붙여 함께 공유
    final files = [...extraImages, ...photos];
    if (files.isEmpty) {
      await Share.share(text, subject: displayName);
    } else {
      await Share.shareXFiles(files, text: text, subject: displayName);
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
        final detail = _envDetail(b);
        if (detail != null) sb.writeln(detail);
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

  /// 현장 정보를 상세보기 카드와 동일한 포맷으로 구성.
  /// 물때 자료가 있으면 음력·일출몰·조차·만조/간조 표까지 덧붙인다(상세 팝업과 동일).
  String? _envDetail(LocationStatus s) {
    final lines = <String>[];

    // 카드 1행: 시각 + 주소
    final addr = s.address?.trim();
    final addrText = (addr != null && addr.isNotEmpty)
        ? addr
        : (s.latitude != null
            ? '${s.latitude!.toStringAsFixed(4)}, ${s.longitude!.toStringAsFixed(4)}'
            : '-');
    final h = s.timestamp.hour.toString().padLeft(2, '0');
    final m = s.timestamp.minute.toString().padLeft(2, '0');
    lines.add('$h:$m  📍 $addrText');

    // 카드 2행: 기온 | 수온
    final temp = s.temperature != null ? '기온: ${s.temperature}°C' : '기온: -°C';
    final water = s.waterTemp != null ? '수온 ${s.waterTemp}°C' : '수온 -°C';
    lines.add('🌡 $temp | 💧 $water');

    // 카드 3행: 관측소 | 물때
    final station = (s.stationName != null && s.stationDistance != null)
        ? '${s.stationName} (${s.stationDistance!.toStringAsFixed(1)}km)'
        : '- (-.--km)';
    final tide = (s.tideName != null && s.tideTime != null)
        ? '${s.tideName} (${s.tideTime})'
        : '-물 (- --:--)';
    lines.add('관측소: $station | 🌊 $tide');

    // 카드 4행(있을 때): 바람 | 날씨
    final wx = _weatherLine(s);
    if (wx != null) lines.add(wx);

    // 물때 상세(자료 있을 때만 — 상세 팝업과 동일)
    if (s.tides.isNotEmpty) {
      lines.add('—');
      lines.addAll(_tideDetail(s));
    }

    return lines.join('\n');
  }

  String? _weatherLine(LocationStatus s) {
    final parts = <String>[];
    if (s.windSpeed != null && s.windDeg != null) {
      parts.add(
          '🌬 ${windDegToDirection(s.windDeg!)} ${s.windSpeed!.toStringAsFixed(1)}m/s');
    }
    if (s.weatherCode != null) {
      parts.add('⛅ ${weatherCodeToDesc(s.weatherCode!)}');
    }
    return parts.isEmpty ? null : parts.join(' | ');
  }

  List<String> _tideDetail(LocationStatus s) {
    final ts = s.timestamp;
    final day = DateTime(ts.year, ts.month, ts.day);
    final out = <String>[];

    // 음력·물때·월령
    final lunar = Solar.fromYmd(ts.year, ts.month, ts.day).getLunar();
    final phase = moonPhase(day);
    final summary = StringBuffer('음력 ${lunar.getMonth()}.${lunar.getDay()}');
    if (s.tideName != null) summary.write(' · ${s.tideName}');
    summary.write(' · ${phase.name} ${(phase.illumination * 100).round()}%');
    out.add(summary.toString());

    // 일출몰·월출몰(위경도 있을 때만)
    if (s.latitude != null && s.longitude != null) {
      final sun = sunRiseSet(day, s.latitude!, s.longitude!);
      final moon = moonRiseSet(day, s.latitude!, s.longitude!);
      out.add('🌅 ${_hm(sun.rise)}   🌇 ${_hm(sun.set)}');
      out.add('🌙 출 ${_hm(moon.rise)}   몰 ${_hm(moon.set)}');
    }

    // 조차·날씨
    final range = tidalRange(s.tides);
    final flowWx = [
      if (range != null) '🌊 조차 ${range.rangeCm}cm (약 ${range.percent}%)',
      if (s.weatherCode != null) '⛅ ${weatherCodeToDesc(s.weatherCode!)}',
    ].join('   ');
    if (flowWx.isNotEmpty) out.add(flowWx);

    // 만조/간조 표
    final tides = s.tides;
    for (var i = 0; i < tides.length; i++) {
      final t = tides[i];
      final arrow = t.type == '만조' ? '▲' : '▼';
      final buf = StringBuffer('$arrow ${t.type} ${t.time}');
      if (t.level != null) buf.write('  ${t.level}cm');
      if (i > 0 && t.level != null && tides[i - 1].level != null) {
        final diff = t.level! - tides[i - 1].level!;
        buf.write('  ${diff >= 0 ? '+' : ''}$diff');
      }
      out.add(buf.toString());
    }
    return out;
  }

  String _hm(DateTime? dt) => dt == null
      ? '-'
      : '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

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
