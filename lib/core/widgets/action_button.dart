import 'package:flutter/material.dart';

class ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool enabled;
  final Color? color;

  const ActionButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.enabled = true,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = enabled
        ? (color ?? Theme.of(context).colorScheme.primary)
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38);

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: SizedBox(
        width: 72,
        height: 72,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: effectiveColor),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: effectiveColor),
            ),
          ],
        ),
      ),
    );
  }
}
