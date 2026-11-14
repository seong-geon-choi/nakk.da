import 'package:flutter/material.dart';

import '../../../core/services/watch_settings_service.dart';

/// 워치 카운터 팔레트(워치 WearMainActivity.PALETTE와 순서·색 동일해야 함).
const _kWatchPalette = <Color>[
  Color(0xFF1565C0), // 0 파랑
  Color(0xFF1E88E5), // 1 하늘
  Color(0xFF00838F), // 2 청록
  Color(0xFF00897B), // 3 틸
  Color(0xFF2E7D32), // 4 초록
  Color(0xFF7CB342), // 5 연두
  Color(0xFFF9A825), // 6 노랑
  Color(0xFFEF6C00), // 7 주황
  Color(0xFFD84315), // 8 진주황
  Color(0xFFC62828), // 9 빨강
  Color(0xFFAD1457), // 10 분홍
  Color(0xFF6A1B9A), // 11 보라
  Color(0xFF4527A0), // 12 진보라
  Color(0xFF455A64), // 13 청회색
  Color(0xFF37474F), // 14 진회색
  Color(0xFF263238), // 15 먹색
];

const _kDimIdleOptions = <int, String>{
  5: '5초',
  10: '10초',
  15: '15초',
  30: '30초',
  60: '1분',
  0: '어둡게 안 함',
};

/// 폰에서 워치 낚.다 앱의 화면·카운터 설정을 관리한다.
/// 워치 시스템 설정(전체 밝기 등)이 아니라, 워치 앱이 떠 있는 동안의 동작만 바꾼다.
class WatchSettingsScreen extends StatefulWidget {
  const WatchSettingsScreen({super.key});

  @override
  State<WatchSettingsScreen> createState() => _WatchSettingsScreenState();
}

class _WatchSettingsScreenState extends State<WatchSettingsScreen> {
  bool _loading = true;
  int _brightOn = 0;
  int _dimLevel = 10;
  int _dimIdleSec = 15;
  bool _keepOn = false;
  bool _ecoColors = false;
  int _color0 = 0;
  int _color1 = 4;
  bool _vibrate = false;
  int _startPage = 1;
  bool _showClock = true;
  bool _showElapsed = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m = await WatchSettingsService.get();
    if (!mounted) return;
    setState(() {
      _brightOn = (m['bright_on'] as int?) ?? 0;
      _dimLevel = (m['dim_level'] as int?) ?? 10;
      _dimIdleSec = (m['dim_idle_sec'] as int?) ?? 15;
      _keepOn = (m['keep_on'] as bool?) ?? false;
      _ecoColors = (m['eco_colors'] as bool?) ?? false;
      _color0 = (m['color_0'] as int?) ?? 0;
      _color1 = (m['color_1'] as int?) ?? 4;
      _vibrate = (m['vibrate'] as bool?) ?? false;
      _startPage = (m['start_page'] as int?) ?? 1;
      _showClock = (m['show_clock'] as bool?) ?? true;
      _showElapsed = (m['show_elapsed'] as bool?) ?? true;
      if (!_kDimIdleOptions.containsKey(_dimIdleSec)) _dimIdleSec = 15;
      _loading = false;
    });
  }

  void _save(Map<String, dynamic> values) => WatchSettingsService.set(values);

  Future<void> _pickColor(int side) async {
    final current = side == 0 ? _color0 : _color1;
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: [
              for (var i = 0; i < _kWatchPalette.length; i++)
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.of(ctx).pop(i),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _kWatchPalette[i],
                      shape: BoxShape.circle,
                      border: i == current
                          ? Border.all(
                              color: Theme.of(ctx).colorScheme.onSurface,
                              width: 3)
                          : null,
                    ),
                    child: i == current
                        ? const Icon(Icons.check, color: Colors.white)
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => side == 0 ? _color0 = picked : _color1 = picked);
    _save({'color_$side': picked});
  }

  Widget _colorDot(int idx) => Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: _kWatchPalette[idx.clamp(0, _kWatchPalette.length - 1)],
          shape: BoxShape.circle,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final dimEnabled = _keepOn && _dimIdleSec > 0;
    return Scaffold(
      appBar: AppBar(title: const Text('워치 앱 설정')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              // 하단 시스템 내비게이션 바(버튼 바)에 마지막 항목이 가리지 않게 인셋만큼 여백.
              padding: EdgeInsets.only(
                  bottom: 24 + MediaQuery.of(context).padding.bottom),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    '워치의 낚.다 앱에 적용됩니다. 워치가 연결돼 있지 않으면 다음 연결 때 반영됩니다. '
                    '워치 전체 밝기 같은 시스템 설정은 바꿀 수 없습니다.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
                const _Header('화면'),
                SwitchListTile(
                  secondary: const Icon(Icons.screen_lock_portrait_outlined),
                  title: const Text('화면 항상 켜두기'),
                  subtitle: Text(_keepOn
                      ? '화면을 계속 켜두고, 일정 시간 조작이 없으면 어두운 요약 화면으로 바뀝니다 '
                          '(배터리 소모 큼, 시간당 약 30%)'
                      : '워치 화면 시간에 따라 꺼집니다(AOD면 요약 화면). '
                          '워치페이스의 진행 중 아이콘으로 바로 돌아올 수 있습니다'),
                  value: _keepOn,
                  onChanged: (v) {
                    setState(() => _keepOn = v);
                    _save({'keep_on': v});
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.brightness_auto_outlined),
                  title: const Text('시스템 밝기 따름'),
                  subtitle: const Text('끄면 앱 화면 밝기를 직접 지정합니다'),
                  value: _brightOn == 0,
                  onChanged: (v) {
                    final next = v ? 0 : 70;
                    setState(() => _brightOn = next);
                    _save({'bright_on': next});
                  },
                ),
                if (_brightOn > 0) ...[
                  ListTile(
                    leading: const Icon(Icons.brightness_6_outlined),
                    title: Text('화면 밝기 $_brightOn%'),
                  ),
                  Slider(
                    value: _brightOn.toDouble(),
                    min: 10,
                    max: 100,
                    divisions: 9,
                    label: '$_brightOn%',
                    onChanged: (v) => setState(() => _brightOn = v.round()),
                    onChangeEnd: (v) => _save({'bright_on': v.round()}),
                  ),
                ],
                ListTile(
                  enabled: _keepOn,
                  leading: const Icon(Icons.timer_outlined),
                  title: const Text('어둡게 되기까지'),
                  subtitle: Text(_keepOn
                      ? '조작이 없으면 화면을 어둡게 해 배터리를 아낍니다'
                      : '화면 항상 켜두기를 켜야 사용할 수 있습니다'),
                  trailing: DropdownButton<int>(
                    value: _dimIdleSec,
                    onChanged: _keepOn
                        ? (v) {
                            if (v == null) return;
                            setState(() => _dimIdleSec = v);
                            _save({'dim_idle_sec': v});
                          }
                        : null,
                    items: [
                      for (final e in _kDimIdleOptions.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                  ),
                ),
                ListTile(
                  enabled: dimEnabled,
                  leading: const Icon(Icons.brightness_low_outlined),
                  title: Text('어두울 때 밝기 $_dimLevel%'),
                ),
                Slider(
                  value: _dimLevel.toDouble(),
                  min: 1,
                  max: 50,
                  divisions: 49,
                  label: '$_dimLevel%',
                  onChanged: dimEnabled
                      ? (v) => setState(() => _dimLevel = v.round())
                      : null,
                  onChangeEnd: (v) => _save({'dim_level': v.round()}),
                ),
                const _Header('요약 화면'),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(
                    '화면이 어두워지거나 꺼졌을 때 보이는 화면입니다.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.schedule),
                  title: const Text('시계 표시'),
                  subtitle: const Text('현재 시각을 위쪽에 표시합니다'),
                  value: _showClock,
                  onChanged: (v) {
                    setState(() => _showClock = v);
                    _save({'show_clock': v});
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.hourglass_bottom),
                  title: const Text('마지막 조과 경과 시간'),
                  subtitle: const Text('예: 마지막 조과 12분 전'),
                  value: _showElapsed,
                  onChanged: (v) {
                    setState(() => _showElapsed = v);
                    _save({'show_elapsed': v});
                  },
                ),
                const _Header('카운터'),
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('왼쪽 색상'),
                  subtitle: const Text('첫 번째 어종 (어종이 하나면 전체 화면)'),
                  trailing: _colorDot(_color0),
                  onTap: () => _pickColor(0),
                ),
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('오른쪽 색상'),
                  subtitle: const Text('두 번째 어종'),
                  trailing: _colorDot(_color1),
                  onTap: () => _pickColor(1),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.battery_saver_outlined),
                  title: const Text('절전 색상'),
                  subtitle: const Text('카운터 배경을 어둡게 해 화면 전력을 줄입니다'),
                  value: _ecoColors,
                  onChanged: (v) {
                    setState(() => _ecoColors = v);
                    _save({'eco_colors': v});
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.vibration),
                  title: const Text('카운트 시 진동'),
                  subtitle: const Text('워치에서 +1은 한 번, −1은 두 번 진동'),
                  value: _vibrate,
                  onChanged: (v) {
                    setState(() => _vibrate = v);
                    _save({'vibrate': v});
                  },
                ),
                const ListTile(
                  leading: Icon(Icons.start_outlined),
                  title: Text('시작 화면'),
                  subtitle: Text('워치 앱을 열었을 때 처음 보이는 화면'),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('그래프')),
                      ButtonSegment(value: 1, label: Text('카운터')),
                      ButtonSegment(value: 2, label: Text('카메라')),
                    ],
                    selected: {_startPage},
                    onSelectionChanged: (s) {
                      final v = s.first;
                      setState(() => _startPage = v);
                      _save({'start_page': v});
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _Header extends StatelessWidget {
  final String label;
  const _Header(this.label);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
}
