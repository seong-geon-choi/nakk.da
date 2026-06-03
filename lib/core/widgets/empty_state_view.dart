import 'package:flutter/material.dart';

class EmptyStateView extends StatelessWidget {
  final String message;
  final String? subMessage;
  final IconData? icon;

  const EmptyStateView({
    super.key,
    required this.message,
    this.subMessage,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 48,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
              const SizedBox(height: 16),
            ],
            Text(
              message,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (subMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                subMessage!,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
