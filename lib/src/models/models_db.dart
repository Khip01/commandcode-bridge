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
  }) : goAccessible = category == 'opensource';

  static const goOnly = true;
  static const proAccessible = false;
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
        id: 'google/gemini-3.5-flash',
        displayName: 'Gemini 3.5 Flash',
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
        id: 'xai/grok-4.5',
        displayName: 'xAI Grok 4.5',
        category: 'premium',
        contextWindow: 500000),

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
        id: 'meta/muse-spark-1.1',
        displayName: 'Meta Muse Spark 1.1',
        category: 'opensource',
        contextWindow: 1048576),
    ModelInfo(
        id: 'nvidia/nemotron-3-ultra-550b-a55b',
        displayName: 'Nvidia Nemotron 3 Ultra',
        category: 'opensource',
        contextWindow: 1000000),
  ];

  static bool isGoPlan(String? planId) =>
      planId != null && planId == 'individual-go';

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
}
