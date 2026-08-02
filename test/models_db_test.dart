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

    test('gpt-5.6-luna is go accessible despite premium category', () {
      final m = ModelsDb.byId('gpt-5.6-luna')!;
      expect(m.category, 'premium');
      expect(m.goAccessible, isTrue);
    });

    test('xai/grok-4.5 is go accessible despite premium category', () {
      final m = ModelsDb.byId('xai/grok-4.5')!;
      expect(m.category, 'premium');
      expect(m.goAccessible, isTrue);
    });

    test('meta/muse-spark-1.1 is premium and not go accessible', () {
      final m = ModelsDb.byId('meta/muse-spark-1.1')!;
      expect(m.category, 'premium');
      expect(m.goAccessible, isFalse);
    });

    test('live-only models (ling, laguna, inkling) exist in db', () {
      for (final id in [
        'inclusionai/ling-3.0-flash-free',
        'poolside/laguna-s-2.1-free',
        'thinkingmachines/inkling',
        'thinkingmachines/inkling-small',
        'moonshotai/Kimi-K3',
        'Qwen/Qwen3.7-Flash',
        'google/gemini-3.6-flash',
        'google/gemini-3.5-flash-lite',
      ]) {
        expect(ModelsDb.byId(id), isNotNull, reason: '$id should be in ModelsDb');
      }
    });

    group('PlanAccess', () {
      test('go plan blocks claude-opus-5', () {
        final m = ModelsDb.byId('claude-opus-5')!;
        expect(
          PlanAccess.isAccessible(model: m, planId: 'individual-go'),
          isFalse,
        );
      });

      test('go plan allows gpt-5.6-luna', () {
        final m = ModelsDb.byId('gpt-5.6-luna')!;
        expect(
          PlanAccess.isAccessible(model: m, planId: 'individual-go'),
          isTrue,
        );
      });

      test('credits override grants access on go', () {
        final m = ModelsDb.byId('claude-opus-5')!;
        expect(
          PlanAccess.isAccessible(
            model: m,
            planId: 'individual-go',
            purchasedCredits: 10,
          ),
          isTrue,
        );
        expect(
          PlanAccess.isAccessible(
            model: m,
            planId: 'individual-go',
            freeCredits: 5,
          ),
          isTrue,
        );
      });

      test('pro plan blocks claude-fable-5 and claude-opus-5 but allows sonnet', () {
        final fable = ModelsDb.byId('claude-fable-5')!;
        final opus = ModelsDb.byId('claude-opus-5')!;
        final sonnet = ModelsDb.byId('claude-sonnet-5')!;
        expect(
          PlanAccess.isAccessible(model: fable, planId: 'individual-pro'),
          isFalse,
        );
        expect(
          PlanAccess.isAccessible(model: opus, planId: 'individual-pro'),
          isFalse,
        );
        expect(
          PlanAccess.isAccessible(model: sonnet, planId: 'individual-pro'),
          isTrue,
        );
      });

      test('max plan allows everything', () {
        final m = ModelsDb.byId('claude-fable-5')!;
        expect(
          PlanAccess.isAccessible(model: m, planId: 'individual-max'),
          isTrue,
        );
      });
    });

    group('ModelsDb providers & free', () {
      test('providerOf classifies models', () {
        expect(ModelsDb.providerOf('deepseek/deepseek-v4-pro'), 'DeepSeek');
        expect(ModelsDb.providerOf('moonshotai/Kimi-K3'), 'Moonshot (Kimi)');
        expect(ModelsDb.providerOf('claude-sonnet-5'), 'Anthropic');
        expect(ModelsDb.providerOf('gpt-5.6-luna'), 'OpenAI');
        expect(ModelsDb.providerOf('xai/grok-4.5'), 'xAI');
        expect(ModelsDb.providerOf('google/gemini-3.6-flash'), 'Google');
      });

      test('isFree marks free models', () {
        expect(ModelsDb.isFree('poolside/laguna-s-2.1-free'), isTrue);
        expect(ModelsDb.isFree('inclusionai/ling-3.0-flash-free'), isTrue);
        expect(ModelsDb.isFree('gpt-5.6-luna'), isFalse);
        expect(ModelsDb.isFree('deepseek/deepseek-v4-pro'), isFalse);
      });

      test('providerRank orders open source before premium', () {
        expect(
          ModelsDb.providerRank('deepseek/deepseek-v4-pro'),
          lessThan(ModelsDb.providerRank('anthropic')),
        );
        expect(
          ModelsDb.providerRank('deepseek/deepseek-v4-pro'),
          lessThan(ModelsDb.providerRank('openai')),
        );
      });
    });
  });
}
