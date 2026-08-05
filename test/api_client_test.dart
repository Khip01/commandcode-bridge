import 'package:test/test.dart';
import 'package:commandcode_bridge/src/services/api_client.dart';

void main() {
  group('WindowLimitData', () {
    test('resetTime is null when resetAt is 0 (no active window)', () {
      final w = WindowLimitData.fromJson({
        'used': 0,
        'cap': 3,
        'exceeded': false,
        'resetAt': 0,
      });
      expect(w.resetTime, isNull);
    });

    test('resetTime resolves positive resetAt to a real date', () {
      final w = WindowLimitData.fromJson({
        'used': 2.13,
        'cap': 6,
        'exceeded': false,
        'resetAt': 1786253751340,
      });
      final rt = w.resetTime;
      expect(rt, isNotNull);
      expect(rt!.millisecondsSinceEpoch, 1786253751340);
    });

    test('remaining is cap minus used', () {
      final w = WindowLimitData.fromJson({
        'used': 2.13,
        'cap': 6,
        'exceeded': false,
        'resetAt': 1786253751340,
      });
      expect(w.remaining, closeTo(3.87, 0.001));
    });

    test('missing fields default to safe values', () {
      final w = WindowLimitData.fromJson({});
      expect(w.used, 0);
      expect(w.cap, 0);
      expect(w.exceeded, isFalse);
      expect(w.resetAt, 0);
      expect(w.resetTime, isNull);
    });
  });
}
