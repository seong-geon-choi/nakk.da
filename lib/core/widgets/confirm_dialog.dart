import 'package:flutter/material.dart';

class ConfirmDialog extends StatelessWidget {
  final String title;
  final String content;
  final String confirmLabel;
  final String cancelLabel;
  final bool isDestructive;
  final Widget? extra;

  const ConfirmDialog({
    super.key,
    required this.title,
    required this.content,
    this.confirmLabel = '확인',
    this.cancelLabel = '취소',
    this.isDestructive = false,
    this.extra,
  });

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String content,
    String confirmLabel = '확인',
    String cancelLabel = '취소',
    bool isDestructive = false,
    Widget? extra,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmDialog(
        title: title,
        content: content,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        isDestructive: isDestructive,
        extra: extra,
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(content),
          if (extra != null) ...[const SizedBox(height: 12), extra!],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: isDestructive
              ? TextButton.styleFrom(foregroundColor: Colors.red)
              : null,
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
