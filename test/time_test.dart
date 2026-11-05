import 'package:english/util/time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('day key and day start use local calendar date', () {
    final now = DateTime(2026, 11, 5, 0, 3);
    expect(getDayKey(now), '2026-11-05');
    expect(
      getDayStartTime(now),
      DateTime(2026, 11, 5).millisecondsSinceEpoch,
    );
  });

  test('today timestamp excludes yesterday and invalid values', () {
    final now = DateTime(2026, 11, 5, 23, 59);
    expect(
      isTimestampToday(DateTime(2026, 11, 5, 0, 0).millisecondsSinceEpoch, now),
      isTrue,
    );
    expect(
      isTimestampToday(
          DateTime(2026, 11, 4, 23, 59).millisecondsSinceEpoch, now),
      isFalse,
    );
    expect(isTimestampToday(null, now), isFalse);
    expect(isTimestampToday(0, now), isFalse);
  });
}
