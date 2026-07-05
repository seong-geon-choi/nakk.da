import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'features/species_ai/data/model_update_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final firstLaunch = !(prefs.getBool('first_launch_done') ?? false);
  runApp(ProviderScope(child: App(firstLaunch: firstLaunch)));
  // 콜드 스타트 1회: 원격 모델 변경 확인 후 백그라운드 다운로드(다음 실행부터 반영)
  unawaited(ModelUpdateService().checkAndUpdate());
}
