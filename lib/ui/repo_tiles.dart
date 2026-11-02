/// The single row a repo's notes collapse into, as a grid tile (phone) and a
/// list tile (desktop).
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'package:todo/ui/repo_group.dart';

String _label(RepoEntry entry) => '${entry.name} · ${entry.notes.length}';

/// Grid cell for a repo group.
class RepoGridTile extends StatelessWidget {
  /// Creates a tile for [entry]; [onTap] opens the repo screen.
  const RepoGridTile({required this.entry, required this.onTap, super.key});

  /// The group this tile stands for.
  final RepoEntry entry;

  /// Open the repo screen.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              Icon(Icons.folder_outlined, color: scheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  _label(entry),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// List row for a repo group.
class RepoListTile extends StatelessWidget {
  /// Creates a row for [entry]; [onTap] opens the repo screen.
  const RepoListTile({required this.entry, required this.onTap, super.key});

  /// The group this row stands for.
  final RepoEntry entry;

  /// Open the repo screen.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.folder_outlined),
      title: Text(_label(entry)),
      onTap: onTap,
    );
  }
}
