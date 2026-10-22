import 'dart:async';
import 'package:flutter/services.dart';

/// 네이티브(조과 서비스)가 조과 집계를 바꿨을 때(알림 +1, 블루투스 리모컨 등)
/// Flutter로 알리는 이벤트 브리지. 지도/차트가 구독해 즉시 다시 그린다.
///
/// 네이티브는 `ACTION_COUNTS_CHANGED` 브로드캐스트를 쏘고, MainActivity가
/// 포그라운드일 때 이를 받아 이 채널로 `countsChanged`를 전달한다.
class CatchEventsService {
  CatchEventsService._();
  static final CatchEventsService instance = CatchEventsService._();

  static const _channel = MethodChannel('com.sgchoisg.nakkda/catchevents');
  final _controller = StreamController<void>.broadcast();
  bool _init = false;

  /// 조과 집계 변경 알림 스트림. 처음 구독 시 네이티브 핸들러를 건다.
  Stream<void> get onCountsChanged {
    if (!_init) {
      _init = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'countsChanged') _controller.add(null);
        return null;
      });
    }
    return _controller.stream;
  }
}
