/// High-resolution monotonic clock for session synchronization.
///
/// Uses [Stopwatch] which is based on a monotonic clock on Dart VMs.
class MonotonicClock {
  MonotonicClock._();

  static final Stopwatch _watch = Stopwatch()..start();

  /// Elapsed milliseconds since process start (monotonic).
  static int nowMs() => _watch.elapsedMilliseconds;

  /// Elapsed microseconds since process start (monotonic).
  static int nowUs() => _watch.elapsedMicroseconds;
}
