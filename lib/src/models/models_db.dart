class ModelInfo {
  final String id;
  final String displayName;
  final String category; // premium, opensource
  final bool goAccessible;
  final int contextWindow;
  final List<String> reasoningEfforts;

  const ModelInfo({
    required this.id,
    required this.displayName,
    required this.category,
    required this.contextWindow,
    this.reasoningEfforts = const [],
    bool? goAccessible,
  }) : goAccessible = goAccessible ?? (category == 'opensource');

  static const goOnly = true;
  static const proAccessible = false;
}

/// Current availability of a model, computed dynamically (never hardcoded).
enum ModelStatus {
  /// Offered by the current Command Code catalog.
  active,

  /// Present in the live API but absent from the bundled registry: newly
  /// released (or renamed) and not yet bundled locally.
  isNew,

  /// No longer provided (free promotion ended or dropped from the catalog),
  /// kept for history and grouped at the bottom of the models page.
  expired,
}

class ModelsDb {
  static final List<ModelInfo> all = [
    // === Premium - Anthropic ===
    ModelInfo(
        id: 'claude-sonnet-5',
        displayName: 'Claude Sonnet 5',
        category: 'premium',
        contextWindow: 1000000,
        reasoningEfforts: ['low', 'medium', 'high', 'xhigh', 'max']),
    ModelInfo(
        id: 'claude-sonnet-4-6',
        displayName: 'Claude Sonnet 4.6',
        category: 'premium',
        contextWindow: 1000000,
        reasoningEfforts: ['low', 'medium', 'high', 'xhigh', 'max']),
    ModelInfo(
        id: 'claude-fable-5',
        displayName: 'Claude Fable 5',
        category: 'premium',
        contextWindow: 1000000,
        reasoningEfforts: ['low', 'medium', 'high', 'xhigh', 'max']),
    ModelInfo(
        id: 'claude-opus-5',
        displayName: 'Claude Opus 5',
        category: 'premium',
        contextWindow: 1000000,
        reasoningEfforts: ['low', 'medium', 'high', 'xhigh', 'max']),
    ModelInfo(
        id: 'claude-opus-4-8',
        displayName: 'Claude Opus 4.8',
        category: 'premium',
        contextWindow: 1000000,
        reasoningEfforts: ['low', 'medium', 'high', 'xhigh', 'max']),
    ModelInfo(
        id: 'claude-opus-4-7',
        displayName: 'Claude Opus 4.7',
        category: 'premium',
        contextWindow: 1000000,
        reasoningEfforts: ['low', 'medium', 'high', 'xhigh', 'max']),
    ModelInfo(
        id: 'claude-haiku-4-5-20251001',
        displayName: 'Claude Haiku 4.5',
        category: 'premium',
        contextWindow: 200000),

    // === Premium - OpenAI ===
    ModelInfo(
        id: 'gpt-5.6-sol',
        displayName: 'GPT 5.6 Sol',
        category: 'premium',
        contextWindow: 1050000,
        reasoningEfforts: ['low', 'medium', 'high', 'xhigh', 'max']),
    ModelInfo(
        id: 'gpt-5.6-terra',
        displayName: 'GPT 5.6 Terra',
        category: 'premium',
        contextWindow: 1050000,
        reasoningEfforts: ['low', 'medium', 'high', 'xhigh', 'max']),
    ModelInfo(
        id: 'gpt-5.6-luna',
        displayName: 'GPT 5.6 Luna',
        category: 'premium',
        contextWindow: 1050000,
        goAccessible: true,
        reasoningEfforts: ['low', 'medium', 'high', 'xhigh', 'max']),
    ModelInfo(
        id: 'gpt-5.5',
        displayName: 'GPT 5.5',
        category: 'premium',
        contextWindow: 400000,
        reasoningEfforts: ['low', 'medium', 'high', 'xhigh']),
    ModelInfo(
        id: 'gpt-5.4',
        displayName: 'GPT 5.4',
        category: 'premium',
        contextWindow: 400000,
        reasoningEfforts: ['low', 'medium', 'high', 'xhigh']),
    ModelInfo(
        id: 'gpt-5.3-codex',
        displayName: 'GPT 5.3 Codex',
        category: 'premium',
        contextWindow: 400000,
        reasoningEfforts: ['low', 'medium', 'high', 'xhigh']),
    ModelInfo(
        id: 'gpt-5.4-mini',
        displayName: 'GPT 5.4 Mini',
        category: 'premium',
        contextWindow: 400000,
        reasoningEfforts: ['low', 'medium', 'high']),

    // === Premium - Google / Other ===
    ModelInfo(
        id: 'google/gemini-3.6-flash',
        displayName: 'Gemini 3.6 Flash',
        category: 'premium',
        contextWindow: 1000000,
        reasoningEfforts: ['low', 'medium', 'high']),
    ModelInfo(
        id: 'google/gemini-3.5-flash',
        displayName: 'Gemini 3.5 Flash',
        category: 'premium',
        contextWindow: 1000000,
        reasoningEfforts: ['low', 'medium', 'high']),
    ModelInfo(
        id: 'google/gemini-3.5-flash-lite',
        displayName: 'Gemini 3.5 Flash Lite',
        category: 'premium',
        contextWindow: 1000000,
        reasoningEfforts: ['low', 'medium', 'high']),
    ModelInfo(
        id: 'google/gemini-3.1-flash-lite',
        displayName: 'Gemini 3.1 Flash Lite',
        category: 'premium',
        contextWindow: 1000000,
        reasoningEfforts: ['low', 'medium', 'high']),
    ModelInfo(
        id: 'sakana/fugu-ultra',
        displayName: 'Sakana Fugu Ultra',
        category: 'premium',
        contextWindow: 1000000,
        reasoningEfforts: ['high', 'xhigh']),
    ModelInfo(
        id: 'meta/muse-spark-1.1',
        displayName: 'Meta Muse Spark 1.1',
        category: 'premium',
        contextWindow: 1048576),
    ModelInfo(
        id: 'xai/grok-4.5',
        displayName: 'xAI Grok 4.5',
        category: 'premium',
        contextWindow: 500000,
        goAccessible: true),

    // === Open Source - DeepSeek ===
    ModelInfo(
        id: 'deepseek/deepseek-v4-pro',
        displayName: 'DeepSeek V4 Pro',
        category: 'opensource',
        contextWindow: 1000000,
        reasoningEfforts: ['high', 'max']),
    ModelInfo(
        id: 'deepseek/deepseek-v4-flash',
        displayName: 'DeepSeek V4 Flash',
        category: 'opensource',
        contextWindow: 1000000,
        reasoningEfforts: ['high', 'max']),

    // === Open Source - MiniMax ===
    ModelInfo(
        id: 'MiniMaxAI/MiniMax-M3-Free',
        displayName: 'MiniMax M3 Free',
        category: 'opensource',
        contextWindow: 1000000),
    ModelInfo(
        id: 'MiniMaxAI/MiniMax-M3',
        displayName: 'MiniMax M3',
        category: 'opensource',
        contextWindow: 1000000),
    ModelInfo(
        id: 'MiniMaxAI/MiniMax-M2.7',
        displayName: 'MiniMax M2.7',
        category: 'opensource',
        contextWindow: 1000000),
    ModelInfo(
        id: 'MiniMaxAI/MiniMax-M2.5',
        displayName: 'MiniMax M2.5',
        category: 'opensource',
        contextWindow: 200000),

    // === Open Source - Moonshot (Kimi) ===
    ModelInfo(
        id: 'moonshotai/Kimi-K2.7-Code',
        displayName: 'Kimi K2.7 Code',
        category: 'opensource',
        contextWindow: 256000),
    ModelInfo(
        id: 'moonshotai/Kimi-K2.7-Code-Highspeed',
        displayName: 'Kimi K2.7 Code Highspeed',
        category: 'opensource',
        contextWindow: 262000),
    ModelInfo(
        id: 'moonshotai/Kimi-K2.6',
        displayName: 'Kimi K2.6',
        category: 'opensource',
        contextWindow: 256000),
    ModelInfo(
        id: 'moonshotai/Kimi-K2.5',
        displayName: 'Kimi K2.5',
        category: 'opensource',
        contextWindow: 256000),
    ModelInfo(
        id: 'moonshotai/Kimi-K3',
        displayName: 'Kimi K3',
        category: 'opensource',
        contextWindow: 1000000),

    // === Open Source - Qwen ===
    ModelInfo(
        id: 'Qwen/Qwen3.7-Max',
        displayName: 'Qwen 3.7 Max',
        category: 'opensource',
        contextWindow: 1000000),
    ModelInfo(
        id: 'Qwen/Qwen3.7-Plus',
        displayName: 'Qwen 3.7 Plus',
        category: 'opensource',
        contextWindow: 1000000),
    ModelInfo(
        id: 'Qwen/Qwen3.6-Max-Preview',
        displayName: 'Qwen 3.6 Max Preview',
        category: 'opensource',
        contextWindow: 1000000),
    ModelInfo(
        id: 'Qwen/Qwen3.6-Plus',
        displayName: 'Qwen 3.6 Plus',
        category: 'opensource',
        contextWindow: 1000000),
    ModelInfo(
        id: 'Qwen/Qwen3.7-Flash',
        displayName: 'Qwen 3.7 Flash',
        category: 'opensource',
        contextWindow: 1000000),

    // === Open Source - ZAI (GLM) ===
    ModelInfo(
        id: 'zai-org/GLM-5.2',
        displayName: 'GLM 5.2',
        category: 'opensource',
        contextWindow: 1000000,
        reasoningEfforts: ['high', 'max']),
    ModelInfo(
        id: 'zai-org/GLM-5.2-Fast',
        displayName: 'GLM 5.2 Fast',
        category: 'opensource',
        contextWindow: 1000000,
        reasoningEfforts: ['high', 'max']),
    ModelInfo(
        id: 'zai-org/GLM-5.1',
        displayName: 'GLM 5.1',
        category: 'opensource',
        contextWindow: 1000000),
    ModelInfo(
        id: 'zai-org/GLM-5',
        displayName: 'GLM 5',
        category: 'opensource',
        contextWindow: 200000),

    // === Open Source - Xiaomi ===
    ModelInfo(
        id: 'xiaomi/mimo-v2.5-pro',
        displayName: 'MiMo V2.5 Pro',
        category: 'opensource',
        contextWindow: 1000000),
    ModelInfo(
        id: 'xiaomi/mimo-v2.5',
        displayName: 'MiMo V2.5',
        category: 'opensource',
        contextWindow: 1000000),

    // === Open Source - Stepfun ===
    ModelInfo(
        id: 'stepfun/Step-3.7-Flash',
        displayName: 'Step 3.7 Flash',
        category: 'opensource',
        contextWindow: 256000),
    ModelInfo(
        id: 'stepfun/Step-3.5-Flash',
        displayName: 'Step 3.5 Flash',
        category: 'opensource',
        contextWindow: 1000000),

    // === Open Source - Tencent ===
    ModelInfo(
        id: 'tencent/hy3-paid',
        displayName: 'Tencent HY3 Paid',
        category: 'opensource',
        contextWindow: 262144),
    ModelInfo(
        id: 'tencent/Hy3',
        displayName: 'Tencent HY3',
        category: 'opensource',
        contextWindow: 262144),

    // === Other ===
    ModelInfo(
        id: 'thinkingmachines/inkling',
        displayName: 'Thinking Machines Inkling',
        category: 'opensource',
        contextWindow: 256000),
    ModelInfo(
        id: 'thinkingmachines/inkling-small',
        displayName: 'Thinking Machines Inkling Small',
        category: 'opensource',
        contextWindow: 1000000),
    ModelInfo(
        id: 'poolside/laguna-s-2.1-free',
        displayName: 'Poolside Laguna S 2.1 Free',
        category: 'opensource',
        contextWindow: 256000),
    ModelInfo(
        id: 'inclusionai/ling-3.0-flash-free',
        displayName: 'InclusionAI Ling 3.0 Flash Free',
        category: 'opensource',
        contextWindow: 256000),
    ModelInfo(
        id: 'nvidia/nemotron-3-ultra-550b-a55b',
        displayName: 'Nvidia Nemotron 3 Ultra',
        category: 'opensource',
        contextWindow: 1000000),
  ];

  static bool isGoPlan(String? planId) =>
      planId != null && planId == 'individual-go';

  static bool isProPlan(String? planId) =>
      planId != null &&
      (planId == 'individual-pro' || planId == 'individual-provider' ||
          planId == 'individual-max' || planId == 'individual-ultra' ||
          planId == 'teams-pro');

  static List<ModelInfo> byCategory(String category) =>
      all.where((m) => m.category == category).toList();

  static List<ModelInfo> get premium => byCategory('premium');
  static List<ModelInfo> get opensource => byCategory('opensource');

  static ModelInfo? byId(String id) {
    for (final m in all) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Display label of the model's provider (used for TUI sub-grouping).
  static String providerOf(String id) {
    if (id.startsWith('deepseek/')) return 'DeepSeek';
    if (id.startsWith('moonshotai/')) return 'Moonshot (Kimi)';
    if (id.startsWith('zai-org/')) return 'ZAI (GLM)';
    if (id.startsWith('MiniMaxAI/')) return 'MiniMax';
    if (id.startsWith('xiaomi/')) return 'Xiaomi (MiMo)';
    if (id.startsWith('Qwen/')) return 'Qwen';
    if (id.startsWith('stepfun/')) return 'StepFun';
    if (id.startsWith('tencent/')) return 'Tencent';
    if (id.startsWith('nvidia/')) return 'Nvidia';
    if (id.startsWith('thinkingmachines/')) return 'Thinking Machines';
    if (id.startsWith('poolside/')) return 'Poolside';
    if (id.startsWith('inclusionai/')) return 'InclusionAI';
    if (id.startsWith('claude')) return 'Anthropic';
    if (id.startsWith('gpt-')) return 'OpenAI';
    if (id.startsWith('google/gemini')) return 'Google';
    if (id.startsWith('sakana/')) return 'Sakana';
    if (id.startsWith('meta/')) return 'Meta';
    if (id.startsWith('xai/')) return 'xAI';
    return 'Other';
  }

  /// Display order for provider sub-groups (open source first, then premium).
  static const List<String> providerOrder = [
    'DeepSeek',
    'Moonshot (Kimi)',
    'ZAI (GLM)',
    'MiniMax',
    'Xiaomi (MiMo)',
    'Qwen',
    'StepFun',
    'Tencent',
    'Nvidia',
    'Thinking Machines',
    'Poolside',
    'InclusionAI',
    'Anthropic',
    'OpenAI',
    'Google',
    'Sakana',
    'Meta',
    'xAI',
    'Other',
  ];

  static int providerRank(String id) {
    final p = providerOf(id);
    final i = providerOrder.indexOf(p);
    return i < 0 ? providerOrder.length - 1 : i;
  }

  /// Models whose usage is free (no credits deducted), per the official site.
  static const Set<String> freeModels = {
    'poolside/laguna-s-2.1-free',
    'inclusionai/ling-3.0-flash-free',
  };

  static bool isFree(String id) => freeModels.contains(id);

  /// Normalize a model ID for comparison: lowercase and strip a trailing
  /// `-YYYYMMDD` date suffix. This mirrors the official CLI, which treats
  /// `claude-haiku-4-5-20251001` and `claude-haiku-4-5` as the same model.
  static String normalizeModelId(String id) {
    final lower = id.trim().toLowerCase();
    return lower.replaceFirst(RegExp(r'-?\d{8}$'), '');
  }

  /// Normalize an iterable of model IDs for comparison.
  static Set<String> normalizeAll(Iterable<String> ids) =>
      ids.map(normalizeModelId).toSet();

  /// UTC timestamps after which a model is no longer provided by Command Code.
  ///
  /// This mirrors the official CLI's date-based expiry checks (for example the
  /// bundled `isLingFlashFreeEnded()`, which hides a model once the current
  /// date passes `2026-08-03T13:00:00Z`). The bridge evaluates the same
  /// schedule dynamically against the current time instead of maintaining a
  /// hardcoded "removed" list. Keys are normalized model IDs.
  static const Map<String, String> modelExpiryUtc = {
    'inclusionai/ling-3.0-flash-free': '2026-08-03T13:00:00Z',
  };

  /// Whether the model's free promotion has ended (now >= expiry), mirroring
  /// the CLI's `isLingFlashFreeEnded()`-style checks.
  static bool isExpiredByTime(String id, {DateTime? now}) {
    final expiry = modelExpiryUtc[normalizeModelId(id)];
    if (expiry == null) return false;
    final parsed = DateTime.tryParse(expiry)?.toUtc();
    if (parsed == null) return false;
    final current = (now ?? DateTime.now()).toUtc();
    return !current.isBefore(parsed);
  }

  /// Classify a model dynamically.
  ///
  /// - `expired` when the model's promo has ended by timestamp, OR (when the
  ///   live API catalog is known) it is bundled but absent from the current
  ///   Command Code catalog.
  /// - `isNew` when (with a known live catalog) the model appears in the API
  ///   but is not in the bundled registry: newly released or renamed.
  /// - otherwise `active`.
  ///
  /// With an unknown live catalog the bridge still honors the timestamp-based
  /// expiry so expired promos are never advertised as active.
  static ModelStatus classify(
    String id, {
    Set<String>? liveApiIds,
    DateTime? now,
  }) {
    if (isExpiredByTime(id, now: now)) return ModelStatus.expired;

    if (liveApiIds != null) {
      final normalized = normalizeModelId(id);
      if (!liveApiIds.contains(normalized)) {
        // Bundled but dropped from the current Command Code catalog.
        if (ModelsDb.byId(id) != null) return ModelStatus.expired;
        return ModelStatus.active;
      }
      // Present in the API but absent from the bundled registry.
      if (ModelsDb.byId(id) == null) return ModelStatus.isNew;
    }
    return ModelStatus.active;
  }
}

/// Plan-access rules mirroring the official Command Code CLI (`evaluateModelAccess`
/// in `cli.mjs`, command-code@1.7.0). The bridge advertises every known model, but
/// plan gating decides which models are actually usable per plan.
class PlanAccess {
  /// Premium models blocked on `individual-pro` (full `provider:id` form, per CLI).
  static const List<String> proBlockedModels = [
    'anthropic:claude-fable-5',
    'anthropic:claude-opus-5',
    'anthropic:claude-opus-4-8',
    'anthropic:claude-opus-4-7',
    'anthropic:claude-opus-4-6',
    'anthropic:claude-opus-4-5-20251101',
    'vercel-ai-gateway:sakana/fugu-ultra',
  ];

  /// Provider prefix used by the CLI for each category.
  static String _providerOf(String modelId, String category) {
    if (category == 'opensource') return 'cai';
    if (modelId.startsWith('claude')) return 'anthropic';
    if (modelId.startsWith('gpt')) return 'openai';
    if (modelId.startsWith('google/gemini')) return 'vercel-ai-gateway';
    return 'vercel-ai-gateway';
  }

  static bool _isBlockedOnPro(String modelId, String category) {
    final full = '${_providerOf(modelId, category)}:$modelId';
    return proBlockedModels.contains(full);
  }

  /// Whether a model is usable on a given plan, honoring the credits override
  /// (purchased or free credits grant access to every model, per the CLI).
  static bool isAccessible({
    required ModelInfo model,
    String? planId,
    double purchasedCredits = 0,
    double freeCredits = 0,
  }) {
    if (purchasedCredits > 0 || freeCredits > 0) return true;
    if (planId == null) return true;
    if (ModelsDb.isGoPlan(planId)) return model.goAccessible;
    if (planId == 'individual-pro') {
      return !_isBlockedOnPro(model.id, model.category);
    }
    // individual-provider / max / ultra / teams-pro and any unknown plan.
    return true;
  }
}
