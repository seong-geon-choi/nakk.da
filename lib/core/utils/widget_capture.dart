import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 위젯을 화면에 띄우지 않고(off-screen 렌더 트리) PNG 바이트로 캡처한다.
/// 별도 RenderView/PipelineOwner를 만들어 직접 layout·paint하므로
/// 화면 표시·프레임 타이밍에 의존하지 않는다. 실패 시 null.
Future<Uint8List?> captureWidgetToPng(
  BuildContext context,
  Widget widget, {
  double pixelRatio = 3.0,
}) async {
  try {
    final flutterView = View.of(context);
    final logicalSize =
        flutterView.physicalSize / flutterView.devicePixelRatio;

    // 앱 테마/방향을 유지한 채 캡처(카페 게시 시에도 동일한 모양)
    final wrapped = MediaQuery(
      data: MediaQueryData.fromView(flutterView),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Theme(
          data: Theme.of(context),
          child: Material(type: MaterialType.transparency, child: widget),
        ),
      ),
    );

    final boundary = RenderRepaintBoundary();
    final renderView = RenderView(
      view: flutterView,
      configuration: ViewConfiguration(
        logicalConstraints: BoxConstraints.loose(logicalSize),
        physicalConstraints: BoxConstraints.loose(logicalSize),
        devicePixelRatio: 1.0,
      ),
      child: RenderPositionedBox(
        alignment: Alignment.topLeft,
        child: boundary,
      ),
    );

    final pipelineOwner = PipelineOwner();
    final buildOwner = BuildOwner(focusManager: FocusManager());
    pipelineOwner.rootNode = renderView;
    renderView.prepareInitialFrame();

    final rootElement = RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
      child: wrapped,
    ).attachToRenderTree(buildOwner);
    buildOwner.buildScope(rootElement);
    buildOwner.finalizeTree();

    pipelineOwner.flushLayout();
    pipelineOwner.flushCompositingBits();
    pipelineOwner.flushPaint();

    final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    pipelineOwner.rootNode = null; // 오프스크린 트리 정리
    return data?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}
