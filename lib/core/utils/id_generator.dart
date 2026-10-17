import 'package:uuid/uuid.dart';

/// Abstraction over id generation so tests can produce deterministic ids.
abstract class IdGenerator {
  String next();

  /// A prefixed id used for audit entries and transfer groups.
  String nextPrefixed(String prefix);
}

/// Production generator backed by `package:uuid` v4 (random) ids.
class UuidGenerator implements IdGenerator {
  const UuidGenerator();

  static const Uuid _uuid = Uuid();

  @override
  String next() => _uuid.v4();

  @override
  String nextPrefixed(String prefix) => '$prefix-${_uuid.v4()}';
}

/// Deterministic generator for tests: `id-1`, `id-2`, ... and `prefix-3`, ...
class SequentialIdGenerator implements IdGenerator {
  SequentialIdGenerator([this._counter = 0]);

  int _counter;

  @override
  String next() {
    _counter += 1;
    return 'id-$_counter';
  }

  @override
  String nextPrefixed(String prefix) {
    _counter += 1;
    return '$prefix-$_counter';
  }
}

/// Clock abstraction so time-dependent rules (relative dates, recurring
/// schedules, budget periods) are testable.
abstract class Clock {
  DateTime now();
}

class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}

/// Fixed, mutable clock for tests.
class FixedClock implements Clock {
  FixedClock(this._now);

  DateTime _now;

  set value(DateTime value) => _now = value;

  @override
  DateTime now() => _now;
}
