/// The capture screen's app bar: note count, and the four actions.
///
/// Split out of `capture_screen.dart` for file size. Callback-only — the
/// screen still owns every action; this just lays the row out.
library;

import 'package:flutter/material.dart';

import 'package:todo/data/note_repository.dart';
import 'package:todo/frame_stats.dart';

/// App bar for the capture screen.
class CaptureAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// Creates the capture screen's app bar.
  const CaptureAppBar({
    required this.repository,
    required this.advanced,
    required this.syncing,
    required this.onNewNote,
    required this.onSync,
    required this.onOpenList,
    required this.onOpenSettings,
    super.key,
  });

  /// Store whose note count is shown live.
  final NoteRepository repository;

  /// Whether advanced mode is on; hides the manual Sync action when off.
  final bool advanced;

  /// Whether a sync is in flight, which disables and spins the Sync action.
  final bool syncing;

  /// Saves the current draft and clears the box for a new one.
  final VoidCallback onNewNote;

  /// Runs a manual sync.
  final VoidCallback onSync;

  /// Opens the notes list.
  final VoidCallback onOpenList;

  /// Opens the settings screen.
  final VoidCallback onOpenSettings;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      actions: [
        // TEMPORARY: forces continuous frame production so raster cost
        // can be sampled at each window size. Armed by
        // TODO_FRAME_STATS=1, which is never set under the test
        // runner, so the branch is unreachable.
        // coverage:ignore-start
        if (frameStatsEnabled)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        // coverage:ignore-end
        // Live count of stored notes, proving local persistence.
        StreamBuilder<int>(
          stream: repository.watchCount(),
          builder: (context, snapshot) {
            final count = snapshot.data ?? 0;
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.list_alt_outlined, size: 18),
                    const SizedBox(width: 4),
                    Text('$count'),
                  ],
                ),
              ),
            );
          },
        ),
        IconButton(
          tooltip: 'New note',
          onPressed: onNewNote,
          icon: const Icon(Icons.add),
        ),
        if (advanced)
          IconButton(
            tooltip: 'Sync',
            onPressed: syncing ? null : onSync,
            icon: syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
          ),
        IconButton(
          tooltip: 'Notes',
          onPressed: onOpenList,
          icon: const Icon(Icons.list),
        ),
        IconButton(
          tooltip: 'Settings',
          onPressed: onOpenSettings,
          icon: const Icon(Icons.settings),
        ),
      ],
    );
  }
}
