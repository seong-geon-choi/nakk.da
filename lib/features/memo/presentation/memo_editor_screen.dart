import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'memo_provider.dart';
import '../../settings/presentation/settings_provider.dart';

class MemoEditorScreen extends ConsumerStatefulWidget {
  final String filePath;
  final String displayName;

  const MemoEditorScreen({
    super.key,
    required this.filePath,
    required this.displayName,
  });

  @override
  ConsumerState<MemoEditorScreen> createState() => _MemoEditorScreenState();
}

class _MemoEditorScreenState extends ConsumerState<MemoEditorScreen> {
  final _controller = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _modified = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final content = await File(widget.filePath).readAsString();
      _controller.text = content;
    } catch (_) {}
    setState(() => _loading = false);
    _controller.addListener(() {
      if (!_modified) setState(() => _modified = true);
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await File(widget.filePath).writeAsString(_controller.text);
      _invalidateTodayIfNeeded();
      if (mounted) {
        setState(() {
          _saving = false;
          _modified = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('저장됐습니다'), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 실패: $e')),
        );
      }
    }
  }

  void _invalidateTodayIfNeeded() {
    final settings = ref.read(settingsProvider).valueOrNull;
    if (settings == null) return;
    final today = DateTime.now();
    final m = today.month.toString().padLeft(2, '0');
    final d = today.day.toString().padLeft(2, '0');
    final todayPath = '${settings.savePath}/${today.year}-$m-$d.md';
    if (widget.filePath == todayPath) ref.invalidate(todayFileProvider);
  }

  Future<bool> _confirmDiscard() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('변경 사항 버리기'),
        content: const Text('저장하지 않은 변경 사항이 있습니다. 닫으시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _onBack() async {
    if (!_modified) {
      Navigator.of(context).pop();
      return;
    }
    final confirmed = await _confirmDiscard();
    if (confirmed && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_modified,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final confirmed = await _confirmDiscard();
        if (confirmed && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _onBack,
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.displayName,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              if (_modified)
                Text('수정 중',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.primary,
                    )),
            ],
          ),
          actions: [
            if (_saving)
              const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                icon: Icon(
                  Icons.save_outlined,
                  color: _modified
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                ),
                tooltip: '저장',
                onPressed: _modified ? _save : null,
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                child: TextField(
                  controller: _controller,
                  maxLines: null,
                  expands: true,
                  keyboardType: TextInputType.multiline,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.6,
                  ),
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.all(16),
                    border: InputBorder.none,
                  ),
                ),
              ),
      ),
    );
  }
}
