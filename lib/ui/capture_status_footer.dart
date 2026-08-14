/// The two status lines under the capture screen's editor.
///
/// Split out of `capture_screen.dart` for file size. Both are listeners over
/// notifiers the screen owns, so this rebuilds without the screen having to.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:todo/ui/capture_status.dart';

/// A sync-failure line and a local-save line, each rebuilt independently.
class CaptureStatusFooter extends StatelessWidget {
  /// Creates the footer over the screen's two status notifiers.
  const CaptureStatusFooter({
    required this.syncStatus,
    required this.lastSavedAt,
    required this.showSavedAt,
    super.key,
  });

  /// The latest sync outcome; only failures are rendered.
  final ValueListenable<SyncStatus?> syncStatus;

  /// When the draft was last written locally, or null before the first save.
  final ValueListenable<DateTime?> lastSavedAt;

  /// Whether to show the local-save line at all (advanced mode only).
  final bool showSavedAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Sync is automatic; routine "saved"/"synced" chatter is not worth
        // showing. Only a sync failure is surfaced, since that is the one
        // state the user might need to act on.
        ValueListenableBuilder<SyncStatus?>(
          valueListenable: syncStatus,
          builder: (context, status, _) {
            if (status == null || status.ok) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Sync failed at ${formatSyncTime(status.time)} · '
                '${status.detail}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            );
          },
        ),
        if (showSavedAt)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: ValueListenableBuilder<DateTime?>(
              valueListenable: lastSavedAt,
              builder: (context, savedAt, _) => Text(
                savedAt == null
                    ? 'Autosaves as you type'
                    : 'Saved locally at ${formatSyncTime(savedAt)}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
      ],
    );
  }
}
