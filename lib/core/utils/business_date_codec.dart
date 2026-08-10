/// Canonical codec for business fields whose PostgreSQL/JSON meaning is a
/// calendar DATE rather than an instant in time.
///
/// Never serialize these values through UTC: converting local midnight to UTC
/// can move the calendar day for users outside UTC. Timestamp fields should
/// continue to use `toUtc().toIso8601String()` instead.
abstract final class BusinessDateCodec {
  static String encode(DateTime value) {
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}
