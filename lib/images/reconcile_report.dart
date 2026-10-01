/// Counts from one `ImageCacheStore.reconcile` pass.
///
/// Pure Dart: the desktop wrapper returns it as JSON to the page.
library;

/// Counts from one reconcile pass.
class ReconcileReport {
  /// Creates a report.
  const ReconcileReport({
    this.uploaded = 0,
    this.downloaded = 0,
    this.evicted = 0,
    this.pending = 0,
    this.missing = 0,
  });

  /// Queued attachments dufs accepted this pass.
  final int uploaded;

  /// Linked attachments fetched from dufs this pass.
  final int downloaded;

  /// Unlinked cached attachments deleted.
  final int evicted;

  /// Attachments still waiting to upload after the pass.
  final int pending;

  /// Linked attachments still not on this device after the pass.
  final int missing;

  /// JSON form, for the wrapper's `/images/reconcile` response.
  Map<String, int> toJson() => {
    'uploaded': uploaded,
    'downloaded': downloaded,
    'evicted': evicted,
    'pending': pending,
    'missing': missing,
  };
}
