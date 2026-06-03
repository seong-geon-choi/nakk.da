import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/photo_service_impl.dart';
import '../domain/photo_service.dart';

final photoServiceProvider = Provider<PhotoService>(
  (ref) => PhotoServiceImpl(),
);

final photoProvider = AsyncNotifierProvider<PhotoNotifier, void>(
  PhotoNotifier.new,
);

class PhotoNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

}
