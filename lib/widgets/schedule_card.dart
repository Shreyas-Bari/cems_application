import 'package:flutter/material.dart';

class ScheduleCard extends StatelessWidget {
  const ScheduleCard({
    super.key,
    required this.title,
    required this.time,
    required this.subtitle,
    required this.isLab,
    this.trailing,
  });

  final String title;
  final String time;
  final String subtitle;
  final bool isLab;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = isLab ? theme.colorScheme.tertiary : theme.colorScheme.primary;
    final accentContainer =
        isLab ? theme.colorScheme.tertiaryContainer : theme.colorScheme.primaryContainer;
    final onAccentContainer =
        isLab ? theme.colorScheme.onTertiaryContainer : theme.colorScheme.onPrimaryContainer;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 78,
            color: accent,
          ),
          const SizedBox(width: 12),
          Container(
            width: 86,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
            decoration: BoxDecoration(
              color: accentContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              time,
              style: theme.textTheme.labelLarge?.copyWith(
                color: onAccentContainer,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
            const SizedBox(width: 4),
          ] else
            const SizedBox(width: 12),
        ],
      ),
    );
  }
}

