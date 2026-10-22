import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 인앱 리뷰(평점) 요청. 과요청을 막기 위해 긍정적 행동 누적 [_threshold]회 이후,
/// 직전 요청으로부터 [_cooldownDays]일이 지난 경우에만 시스템 리뷰 창을 띄운다.
/// (실제 노출 여부는 Google Play가 자체 쿼터로 최종 결정한다.)
class ReviewService {
  static const _countKey = 'review_positive_count';
  static const _lastMsKey = 'review_last_prompt_ms';
  static const _threshold = 3; // 긍정적 행동 N회 후
  static const _cooldownDays = 120; // 재요청 최소 간격

  final InAppReview _review = InAppReview.instance;

  /// 긍정적 행동(메모 저장 등) 발생 시 호출. 조건 충족 시 인앱 리뷰를 요청한다.
  Future<void> registerPositiveEvent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final count = (prefs.getInt(_countKey) ?? 0) + 1;
      await prefs.setInt(_countKey, count);
      if (count < _threshold) return;

      final lastMs = prefs.getInt(_lastMsKey) ?? 0;
      final sinceDays =
          (DateTime.now().millisecondsSinceEpoch - lastMs) / 86400000;
      if (lastMs != 0 && sinceDays < _cooldownDays) return;

      if (await _review.isAvailable()) {
        await _review.requestReview();
        await prefs.setInt(_lastMsKey, DateTime.now().millisecondsSinceEpoch);
        await prefs.setInt(_countKey, 0);
      }
    } catch (_) {/* 리뷰 요청 실패는 조용히 무시 */}
  }
}
