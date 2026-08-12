/// A single, structured analytics event.
///
/// Interaction-only by construction: [params] holds enum values, counts,
/// durations and booleans — never note text or other free-form user input.
/// Callers are trusted to uphold that; see `analytics_service.dart` for the
/// full policy.
class AnalyticsEvent {
  /// Creates an [AnalyticsEvent] with the given [name], [params] and
  /// [timestamp].
  const AnalyticsEvent({
    required this.name,
    required this.timestamp,
    this.params = const {},
  });

  /// Short, stable event identifier, e.g. `'screen_view'`, `'sort_changed'`.
  final String name;

  /// When the event happened.
  final DateTime timestamp;

  /// Structured parameters. Values must be JSON-encodable primitives
  /// (String, num, bool, or null) — never note text.
  final Map<String, Object?> params;

  /// Serializes to a JSON-encodable map for local buffering and the
  /// Firebase flush.
  Map<String, Object?> toJson() => {
    'name': name,
    'timestamp': timestamp.toIso8601String(),
    'params': params,
  };

  /// Reconstructs an [AnalyticsEvent] from [toJson]'s output. Returns null
  /// for a malformed entry (e.g. a buffer corrupted by a previous crash)
  /// rather than throwing — analytics must never crash capture.
  static AnalyticsEvent? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    final timestamp = DateTime.tryParse('${json['timestamp']}');
    final params = json['params'];
    if (name is! String || timestamp == null) return null;
    return AnalyticsEvent(
      name: name,
      timestamp: timestamp,
      params: params is Map
          ? Map<String, Object?>.from(params)
          : const <String, Object?>{},
    );
  }
}
