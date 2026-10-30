import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../domain/models/tide_station.dart';
import '../data/tide_station_data.dart';

/// 조석 관측소 선택기. 현장 좌표([lat],[lng]) 기준 가까운 순으로 정렬해 보여주고,
/// 이름 검색으로 좁힐 수 있다. 선택하면 그 [TideStation]을 돌려준다(취소 시 null).
class StationPicker {
  static Future<TideStation?> show(
    BuildContext context, {
    required double lat,
    required double lng,
    String? currentName,
  }) {
    return showModalBottomSheet<TideStation>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxWidth: math.min(MediaQuery.of(context).size.width, 600),
      ),
      builder: (_) =>
          _StationPickerSheet(lat: lat, lng: lng, currentName: currentName),
    );
  }
}

class _StationPickerSheet extends StatefulWidget {
  final double lat;
  final double lng;
  final String? currentName;

  const _StationPickerSheet({
    required this.lat,
    required this.lng,
    this.currentName,
  });

  @override
  State<_StationPickerSheet> createState() => _StationPickerSheetState();
}

class _StationPickerSheetState extends State<_StationPickerSheet> {
  late final List<_StationDist> _sorted;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _sorted = kTideStations
        .map((s) => _StationDist(
            s, _haversine(widget.lat, widget.lng, s.latitude, s.longitude)))
        .toList()
      ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final cs = Theme.of(context).colorScheme;
    final q = _query.trim();
    final list =
        q.isEmpty ? _sorted : _sorted.where((e) => e.station.name.contains(q)).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom + mq.padding.bottom),
      child: Container(
        constraints:
            BoxConstraints(maxHeight: math.min(mq.size.height * 0.8, 620)),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('관측소 선택', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('가까운 순 · 조석/조위를 선택한 관측소 기준으로 다시 불러옵니다',
                style: TextStyle(
                    fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6))),
            const SizedBox(height: 10),
            TextField(
              autofocus: false,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '관측소 이름 검색',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text('검색 결과가 없습니다',
                          style: TextStyle(
                              color: cs.onSurface.withValues(alpha: 0.6))),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final e = list[i];
                        final isCurrent = widget.currentName != null &&
                            e.station.name == widget.currentName;
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            isCurrent
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: isCurrent ? cs.primary : cs.onSurfaceVariant,
                            size: 20,
                          ),
                          title: Text(e.station.name),
                          trailing: Text('${e.distanceKm.toStringAsFixed(1)}km',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: cs.onSurface.withValues(alpha: 0.6))),
                          onTap: () => Navigator.of(context).pop(e.station),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}

class _StationDist {
  final TideStation station;
  final double distanceKm;
  const _StationDist(this.station, this.distanceKm);
}
