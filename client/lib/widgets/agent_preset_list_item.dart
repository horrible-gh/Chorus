import 'package:flutter/material.dart';

import '../models/agent_preset.dart';

class AgentPresetListItem extends StatelessWidget {
  const AgentPresetListItem({
    super.key,
    required this.preset,
    required this.selected,
    required this.onTap,
    required this.onArchive,
  });

  final AgentPreset preset;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onArchive;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: selected ? colorScheme.secondaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: CircleAvatar(
          backgroundColor: selected
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest,
          foregroundColor:
              selected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
          child: Icon(
            preset.isArchived
                ? Icons.archive_outlined
                : Icons.smart_toy_outlined,
            size: 20,
          ),
        ),
        title: Text(
          preset.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${preset.roleName} · ${preset.defaultRunner} · ${preset.defaultModel}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: preset.isArchived
            ? _StatusChip(status: preset.status)
            : IconButton(
                tooltip: 'Archive',
                icon: const Icon(Icons.archive_outlined),
                onPressed: onArchive,
              ),
        onTap: onTap,
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}
