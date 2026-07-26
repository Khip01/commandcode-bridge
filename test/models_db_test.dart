import 'package:test/test.dart';
import 'package:commandcode_bridge/src/models/models_db.dart';

void main() {
  group('ModelsDb', () {
    test('has models', () {
      expect(ModelsDb.all.length, greaterThan(0));
    });

    test('has premium models', () {
      expect(ModelsDb.premium.length, greaterThan(0));
    });

    test('has opensource models', () {
      expect(ModelsDb.opensource.length, greaterThan(0));
    });

    test('finds model by id', () {
      final m = ModelsDb.byId('deepseek/deepseek-v4-flash');
      expect(m, isNotNull);
      expect(m!.id, 'deepseek/deepseek-v4-flash');
      expect(m.category, 'opensource');
      expect(m.contextWindow, 1000000);
    });

    test('returns null for unknown model', () {
      expect(ModelsDb.byId('nonexistent'), isNull);
    });

    test('goAccessible is true for opensource', () {
      final m = ModelsDb.byId('deepseek/deepseek-v4-flash')!;
      expect(m.goAccessible, isTrue);
    });

    test('goAccessible is false for premium', () {
      final m = ModelsDb.byId('claude-sonnet-5')!;
      expect(m.goAccessible, isFalse);
    });

    test('isGoPlan returns true for individual-go', () {
      expect(ModelsDb.isGoPlan('individual-go'), isTrue);
    });

    test('isGoPlan returns false for other plans', () {
      expect(ModelsDb.isGoPlan('individual-pro'), isFalse);
      expect(ModelsDb.isGoPlan('individual-max'), isFalse);
      expect(ModelsDb.isGoPlan(null), isFalse);
    });
  });
}
