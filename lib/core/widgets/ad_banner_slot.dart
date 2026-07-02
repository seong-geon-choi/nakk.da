import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/settings/presentation/settings_provider.dart';

/// 광고 배너가 들어갈 예약 공간(placeholder).
///
/// 설정의 `adsEnabled`가 켜진 경우에만 노출하며(기본 off), 꺼져 있으면 공간을
/// 차지하지 않는다(개발자 메뉴의 '광고 노출' 토글로 제어).
///
/// 아직 광고 SDK(AppLovin MAX / AdMob)는 연동하지 않은 준비 단계로, 표준 배너
/// 높이(50)를 예약해 레이아웃을 미리 잡아둔다. 추후 child를 실제 배너
/// (`MaxAdView` 등)로 교체하면 된다 — docs/ad-mediation-plan.md §5·§7.
class AdBannerSlot extends ConsumerWidget {
  const AdBannerSlot({super.key});

  /// 표준 배너 높이(320x50)
  static const double height = 50;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adsEnabled = ref.watch(
      settingsProvider.select((s) => s.valueOrNull?.adsEnabled ?? false),
    );
    // 하단 내비게이션 바(제스처/버튼)에 가려지지 않도록 시스템 인셋만큼 띄운다.
    final bottomInset = MediaQuery.of(context).padding.bottom;
    // 광고가 꺼져 있어도 하단 시스템 바 영역은 예약해 본문이 가려지지 않게 한다.
    if (!adsEnabled) return SizedBox(height: bottomInset);

    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          border: Border.symmetric(
            horizontal: BorderSide(color: cs.outline.withValues(alpha: 0.6)),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.ads_click_outlined,
                size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              '광고 영역',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
