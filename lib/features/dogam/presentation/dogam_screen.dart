import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../../core/widgets/saf_image.dart';
import '../../search/presentation/search_provider.dart';
import '../../settings/presentation/settings_provider.dart';
import '../domain/fish_assets.dart';
import '../domain/models/dogam_entry.dart';
import 'dogam_provider.dart';

class DogamScreen extends ConsumerWidget {
  const DogamScreen({super.key});

  /// 메모 전체를 다시 스캔해 도감 집계를 갱신한다.
  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(searchHitsProvider);
    await ref.read(searchHitsProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dogamProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('어류 도감')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyStateView(
          icon: Icons.error_outline,
          message: '도감을 불러오지 못했습니다',
          subMessage: e.toString(),
        ),
        data: (entries) {
          if (entries.isEmpty) {
            return const EmptyStateView(
              icon: Icons.menu_book_outlined,
              message: '도감에 표시할 어종이 없습니다',
              subMessage: '설정에서 어종을 추가해 보세요',
            );
          }
          final caughtCount = entries.where((e) => e.caught).length;
          // 시스템 내비게이션 바(홈 버튼바)에 마지막 행이 가리지 않도록 하단 인셋 확보
          final bottomInset = MediaQuery.of(context).padding.bottom;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '수집 $caughtCount / ${entries.length} 종',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => _refresh(ref),
                  child: GridView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottomInset),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.82,
                    ),
                    itemCount: entries.length,
                    itemBuilder: (_, i) => _DogamTile(entry: entries[i]),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DogamTile extends ConsumerWidget {
  final DogamEntry entry;
  const _DogamTile({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final savePath = ref
        .watch(settingsProvider.select((s) => s.valueOrNull?.savePath ?? ''));
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        if (entry.caught) {
          _showRecords(context, ref);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${entry.species} — 아직 기록이 없어요'),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      },
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _imageArea(cs, savePath),
                  if (entry.caught && entry.maxLength != null)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${entry.maxLength!.toStringAsFixed(1)}cm',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            entry.species,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: entry.caught ? FontWeight.w600 : FontWeight.normal,
              color: entry.caught
                  ? cs.onSurface
                  : cs.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  /// 타일 이미지 영역.
  /// - 잡았고 사진이 있으면 → 실제 최대기록 사진으로 타일을 채움(cover)
  /// - 그 외 → 실루엣(못잡음)/컬러 일러스트(잡았으나 사진 없음)/기본 아이콘
  Widget _imageArea(ColorScheme cs, String savePath) {
    if (entry.caught) {
      final photo = entry.heroPhotoPath;
      if (photo != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SafImage(
            photoPath: photo,
            savePath: savePath,
            fit: BoxFit.cover,
            fullScreen: true, // 자체 탭/뷰어 비활성화 → 타일 탭은 상세 시트로
          ),
        );
      }
    }
    final assetPath = entry.caught
        ? fishColorAsset(entry.species)
        : fishSilhouetteAsset(entry.species);
    final fallback = Icon(
      Icons.set_meal,
      size: 40,
      color: entry.caught
          ? cs.primary.withValues(alpha: 0.8)
          : cs.onSurface.withValues(alpha: 0.25),
    );
    final art = assetPath == null
        ? fallback
        : Image.asset(
            assetPath,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => fallback,
          );
    return Center(child: Padding(padding: const EdgeInsets.all(6), child: art));
  }

  void _showRecords(BuildContext context, WidgetRef ref) {
    final savePath = ref.read(settingsProvider).valueOrNull?.savePath ?? '';
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Text(entry.species,
                        style: Theme.of(ctx).textTheme.titleMedium),
                    const SizedBox(width: 8),
                    Text('${entry.records.length}마리',
                        style: TextStyle(color: cs.primary)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: entry.records.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final h = entry.records[i];
                    final e = h.entry;
                    return ListTile(
                      leading: SizedBox(
                        width: 48,
                        height: 48,
                        child: e.photoPath != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: SafImage(
                                  photoPath: e.photoPath!,
                                  savePath: savePath,
                                  height: 48,
                                ),
                              )
                            : Icon(Icons.notes,
                                color: cs.onSurface.withValues(alpha: 0.4)),
                      ),
                      title: Text(e.fishLength != null
                          ? '${e.fishLength!.toStringAsFixed(1)}cm'
                          : (e.text?.trim().isNotEmpty == true
                              ? e.text!.trim()
                              : '기록')),
                      subtitle: Text(
                        h.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        context.push(
                          '${AppRoutes.fileList}/${Uri.encodeComponent(h.filePath)}'
                          '?name=${Uri.encodeComponent(h.displayName)}',
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
