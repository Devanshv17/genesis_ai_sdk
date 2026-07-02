/// Token-bucket rate limiter for agent requests.
///
/// Prevents runaway loops or abusive callers from hammering your API
/// quota or a local model. Works entirely in-memory — no persistence.
library;

/// Thrown when the rate limit is exceeded.
class RateLimitException implements Exception {
  final String reason;
  const RateLimitException(this.reason);

  @override
  String toString() => 'RateLimitException: $reason';
}

/// A simple fixed-window rate limiter keyed by an arbitrary string
/// (e.g. `sessionId`, user ID, or `"global"`).
///
/// Each key gets its own independent window counter.
///
/// ## Example — limit a chat agent to 20 msgs/min
/// ```dart
/// final limiter = RateLimiter(
///   maxRequests: 20,
///   windowDuration: Duration(minutes: 1),
/// );
///
/// // In your chat handler:
/// limiter.check(sessionId);   // throws RateLimitException if over limit
/// final response = await agent.chat(userMessage);
/// ```
class RateLimiter {
  /// Maximum number of requests allowed within [windowDuration].
  final int maxRequests;

  /// Duration of each rolling window.
  final Duration windowDuration;

  final Map<String, _Bucket> _buckets = {};

  RateLimiter({
    this.maxRequests = 60,
    this.windowDuration = const Duration(minutes: 1),
  });

  /// Check whether [key] is within the rate limit.
  ///
  /// Records the attempt and throws [RateLimitException] if the limit is
  /// exceeded. Otherwise returns normally.
  void check(String key) {
    final now = DateTime.now();
    final bucket = _buckets.putIfAbsent(key, () => _Bucket());

    // Reset window if it has expired.
    if (now.difference(bucket.windowStart) >= windowDuration) {
      bucket.windowStart = now;
      bucket.count = 0;
    }

    bucket.count++;
    if (bucket.count > maxRequests) {
      final resetIn = windowDuration - now.difference(bucket.windowStart);
      throw RateLimitException(
        'Rate limit exceeded for "$key": $maxRequests requests per '
        '${_formatDuration(windowDuration)}. '
        'Resets in ${_formatDuration(resetIn)}.',
      );
    }
  }

  /// Returns how many requests [key] has made in the current window.
  /// Returns 0 if the key has no history or the window has expired.
  int usage(String key) {
    final bucket = _buckets[key];
    if (bucket == null) return 0;
    final now = DateTime.now();
    if (now.difference(bucket.windowStart) >= windowDuration) return 0;
    return bucket.count;
  }

  /// Clears all rate-limit state. Useful in tests.
  void reset() => _buckets.clear();

  static String _formatDuration(Duration d) {
    if (d.inHours >= 1) return '${d.inHours}h';
    if (d.inMinutes >= 1) return '${d.inMinutes}m';
    return '${d.inSeconds}s';
  }
}

class _Bucket {
  DateTime windowStart = DateTime.now();
  int count = 0;
}

// ── ConcurrencyLimiter ───────────────────────────────────────────────────────

/// Limits how many concurrent [AgenticAgent.chat] calls can run at once
/// per key.  Useful when running agents inside a server or background
/// isolate and you want to prevent unbounded parallelism.
///
/// ```dart
/// final concurrency = ConcurrencyLimiter(maxConcurrent: 3);
///
/// await concurrency.run('user_42', () => agent.chat(message));
/// ```
class ConcurrencyLimiter {
  final int maxConcurrent;
  final Map<String, int> _active = {};

  ConcurrencyLimiter({this.maxConcurrent = 5});

  /// Runs [fn] if the concurrent count for [key] is below [maxConcurrent].
  /// Throws [RateLimitException] immediately (no queuing) if the limit is
  /// reached.
  Future<T> run<T>(String key, Future<T> Function() fn) async {
    final current = _active[key] ?? 0;
    if (current >= maxConcurrent) {
      throw RateLimitException(
        'Concurrency limit reached for "$key": max $maxConcurrent '
        'simultaneous requests.',
      );
    }
    _active[key] = current + 1;
    try {
      return await fn();
    } finally {
      final updated = (_active[key] ?? 1) - 1;
      if (updated <= 0) {
        _active.remove(key);
      } else {
        _active[key] = updated;
      }
    }
  }
}
