import 'package:flutter_test/flutter_test.dart';
import 'package:nakkda/core/utils/species_detector.dart';

void main() {
  group('detectFishSpecies', () {
    test('텍스트에 어종명이 있으면 탐지한다', () {
      expect(detectFishSpecies('오늘 감성돔 한 마리 잡음'), '감성돔');
      expect(detectFishSpecies('볼락 마릿수 좋았다'), '볼락');
    });

    test('어종명이 없으면 null', () {
      expect(detectFishSpecies('입질이 전혀 없었다'), isNull);
      expect(detectFishSpecies(''), isNull);
    });

    test('여러 어종이 있으면 가장 먼저 등장한 어종', () {
      expect(detectFishSpecies('참돔 노리다가 농어 잡음'), '참돔');
    });

    test('겹치는 이름은 더 구체적인(긴) 어종 우선 — 쥐노래미 > 노래미', () {
      expect(detectFishSpecies('쥐노래미 손맛'), '쥐노래미');
    });

    test('문장 중간에 있어도 탐지', () {
      expect(detectFishSpecies('드디어 무늬오징어 에깅 성공'), '무늬오징어');
    });

    test('사용자 지정 목록으로 탐지 (기본 목록에 없는 어종)', () {
      expect(detectFishSpecies('오늘 돗돔 잡음', ['돗돔', '참돔']), '돗돔');
      // 기본 목록엔 없으므로 목록 없이는 미탐지
      expect(detectFishSpecies('오늘 돗돔 잡음'), isNull);
    });
  });

  group('detectFishLength', () {
    test('cm·센치·센티·짜리 단위를 인식한다', () {
      expect(detectFishLength('감성돔 38cm'), 38.0);
      expect(detectFishLength('38센치 나옴'), 38.0);
      expect(detectFishLength('38.5센티'), 38.5);
      expect(detectFishLength('45짜리 한 마리'), 45.0);
    });

    test('대소문자·공백 허용', () {
      expect(detectFishLength('42 CM'), 42.0);
      expect(detectFishLength('30 cm'), 30.0);
    });

    test('단위 없는 숫자는 무시', () {
      expect(detectFishLength('8시 38분에 입질'), isNull);
      expect(detectFishLength('3마리 잡음'), isNull);
    });

    test('범위(1~300cm) 밖 값은 무시', () {
      expect(detectFishLength('5000짜리 미끼'), isNull);
    });

    test('어종+길이 함께 있어도 길이만 추출', () {
      expect(detectFishLength('참돔 42.5cm 대박'), 42.5);
    });

    test('빈 문자열은 null', () {
      expect(detectFishLength(''), isNull);
    });
  });
}
