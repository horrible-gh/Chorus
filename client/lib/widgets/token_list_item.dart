import 'package:flutter/material.dart';

import '../models/provider_token.dart';

class TokenListItem extends StatelessWidget {
  const TokenListItem({
    super.key,
    required this.token,
    required this.selected,
    required this.onTap,
    required this.onArchive,
  });

  final ProviderToken token;
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
            token.isArchived ? Icons.archive_outlined : Icons.key_outlined,
            size: 20,
          ),
        ),
        title: Text(
          token.alias,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${token.provider} · ${token.tokenValue}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: token.isArchived
            ? _StatusChip(status: token.status)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StatusChip(status: token.status),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Archive',
                    icon: const Icon(Icons.archive_outlined),
                    onPressed: onArchive,
                  ),
                ],
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

    Color bgColor;
    Color fgColor;
    if (status == 'active') {
      bgColor = colorScheme.primaryContainer;
      fgColor = colorScheme.onPrimaryContainer;
    } else if (status == 'inactive') {
      bgColor = colorScheme.surfaceContainerHighest;
      fgColor = colorScheme.onSurfaceVariant;
    } else {
      bgColor = colorScheme.errorContainer;
      fgColor = colorScheme.onErrorContainer;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fgColor),
      ),
    );
  }
}
