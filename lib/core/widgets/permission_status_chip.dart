import 'package:flutter/material.dart';

class PermissionStatusChip extends StatelessWidget {
  final bool isGranted;

  const PermissionStatusChip({super.key, required this.isGranted});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(
        isGranted ? '허용' : '거부',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      backgroundColor: isGranted
          ? Colors.green.withValues(alpha: 0.2)
          : Colors.red.withValues(alpha: 0.2),
      side: BorderSide(
        color: isGranted ? Colors.green : Colors.red,
        width: 1,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }
}
