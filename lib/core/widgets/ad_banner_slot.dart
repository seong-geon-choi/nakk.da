import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../ads/ad_config.dart';
import '../../features/settings/presentation/settings_provider.dart';

/// 하단 배너 광고 슬롯.
///
/// 설정의 `adsEnabled`가 켜진 경우에만 노출하며(기본 off), 꺼져 있으면 공간을
/// 차지하지 않는다(개발자 메뉴의 '광고 노출' 토글로 제어).
///
/// AdMob 배너(`google_mobile_ads`)를 직접 로드한다. 로드 전/실패 시에는 표준
/// 배너 높이(50)를 예약해 레이아웃 흔들림을 막는다 — docs/ad-mediation-plan.md 부록.
class AdBannerSlot extends ConsumerStatefulWidget {
  const AdBannerSlot({super.key});

  /// 표준 배너 높이(320x50)
  static const double height = 50;

  @override
  ConsumerState<AdBannerSlot> createState() => _AdBannerSlotState();
}

class _AdBannerSlotState extends ConsumerState<AdBannerSlot> {
  BannerAd? _ad;
  bool _loaded = false;

  /// 광고가 켜졌을 때 1회만 배너를 로드한다.
  void _loadAd() {
    if (_ad != null) return;
    final ad = BannerAd(
      adUnitId: bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _ad = null; // 실패 시 자리(높이)만 유지
        },
      ),
    );
    _ad = ad;
    ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final adsEnabled = ref.watch(
      settingsProvider.select((s) => s.valueOrNull?.adsEnabled ?? false),
    );
    // 하단 내비게이션 바(제스처/버튼)에 가려지지 않도록 시스템 인셋만큼 띄운다.
    final bottomInset = MediaQuery.of(context).padding.bottom;
    // 광고가 꺼져 있어도 하단 시스템 바 영역은 예약해 본문이 가려지지 않게 한다.
    if (!adsEnabled) return SizedBox(height: bottomInset);

    _loadAd();

    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: AdBannerSlot.height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          border: Border.symmetric(
            horizontal: BorderSide(color: cs.outline.withValues(alpha: 0.6)),
          ),
        ),
        child: (_loaded && _ad != null)
            ? SizedBox(
                width: _ad!.size.width.toDouble(),
                height: _ad!.size.height.toDouble(),
                child: AdWidget(ad: _ad!),
              )
            : const SizedBox(height: AdBannerSlot.height),
      ),
    );
  }
}
