import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'file_list_provider.dart';
import '../domain/models/file_summary.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/router/app_router.dart';

class FileListScreen extends ConsumerWidget {
  const FileListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(fileListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('메모 목록'),
      ),
      body: listAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyStateView(
          icon: Icons.error_outline,
          message: '목록을 불러오지 못했습니다',
          subMessage: e.toString(),
        ),
        data: (files) {
          if (files.isEmpty) {
            return const EmptyStateView(
              icon: Icons.folder_open,
              message: '저장된 메모가 없습니다',
              subMessage: '음성 또는 텍스트로 첫 메모를 남겨보세요',
            );
          }
          return ListView.separated(
            itemCount: files.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) =>
                _FileItem(file: files[index]),
          );
        },
      ),
    );
  }
}

class _FileItem extends ConsumerStatefulWidget {
  final FileSummary file;
  const _FileItem({required this.file});

  @override
  ConsumerState<_FileItem> createState() => _FileItemState();
}

class _FileItemState extends ConsumerState<_FileItem> {
  FileSummary get file => widget.file;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _openViewer(context),
      onLongPress: () => _showContextMenu(context),
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.displayName,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormatter.toRelativeDate(file.date),
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${file.entryCount}개',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }

  void _openViewer(BuildContext context) {
    final encoded = Uri.encodeComponent(file.filePath);
    context.push(
      '${AppRoutes.fileList}/$encoded?name=${Uri.encodeComponent(file.displayName)}',
    );
  }

  Future<void> _showContextMenu(BuildContext context) async {
    final action = await showModalBottomSheet<_FileAction>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('이름 변경'),
              onTap: () => Navigator.of(sheetCtx).pop(_FileAction.rename),
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('복사'),
              onTap: () => Navigator.of(sheetCtx).pop(_FileAction.copy),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('삭제', style: TextStyle(color: Colors.red)),
              onTap: () => Navigator.of(sheetCtx).pop(_FileAction.delete),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == _FileAction.rename) {
      await _showRenameDialog(context);
    } else if (action == _FileAction.copy) {
      await _showCopyDialog(context);
    } else if (action == _FileAction.delete) {
      await _showDeleteDialog(context);
    }
  }

  Future<void> _showRenameDialog(BuildContext context) async {
    final controller = TextEditingController(text: file.displayName);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('이름 변경'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '파일 이름',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    final newName = controller.text.trim();
    // 다이얼로그 닫힘 애니메이션 완료 후 dispose (즉시 dispose 시 InheritedElement assertion 오류 방지)
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (confirmed == true && mounted) {
      if (newName.isNotEmpty && newName != file.displayName) {
        await ref.read(fileListProvider.notifier).rename(file.filePath, newName);
      }
    }
  }

  Future<void> _showCopyDialog(BuildContext context) async {
    final controller = TextEditingController(text: '${file.displayName}_복사');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('복사'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '복사본 이름',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('복사'),
          ),
        ],
      ),
    );
    final newName = controller.text.trim();
    // 다이얼로그 닫힘 애니메이션 완료 후 dispose
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (confirmed == true && mounted) {
      if (newName.isNotEmpty) {
        await ref.read(fileListProvider.notifier).copy(file.filePath, newName);
      }
    }
  }

  Future<void> _showDeleteDialog(BuildContext context) async {
    bool deletePhotos = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('메모 삭제'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${file.displayName} 을(를) 삭제할까요?'),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('연결된 사진도 함께 삭제',
                    style: TextStyle(fontSize: 14)),
                value: deletePhotos,
                onChanged: (v) => setState(() => deletePhotos = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('취소'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('삭제'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && mounted) {
      await ref
          .read(fileListProvider.notifier)
          .delete(file.filePath, deletePhotos: deletePhotos);
    }
  }
}

enum _FileAction { rename, copy, delete }
