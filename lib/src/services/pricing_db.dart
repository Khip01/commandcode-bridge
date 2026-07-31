class ModelPricing {
  final String modelId;
  final String displayName;
  final double inputPer1M;
  final double outputPer1M;
  final double cacheReadPer1M;
  final double cacheWritePer1M;

  const ModelPricing({
    required this.modelId,
    required this.displayName,
    required this.inputPer1M,
    required this.outputPer1M,
    this.cacheReadPer1M = 0,
    this.cacheWritePer1M = 0,
  });

  double costFor(int inputTokens, int outputTokens, [int cacheReadTokens = 0]) {
    return (inputTokens * inputPer1M / 1000000) +
        (outputTokens * outputPer1M / 1000000) +
        (cacheReadTokens * cacheReadPer1M / 1000000);
  }
}

class PricingDb {
  // Models whose ID does NOT appear in the Command Code /provider/v1/models
  // response are listed here. They are deliberately excluded from `all`
  // because we cannot guarantee they can actually be called by the bridge.
  // If you have manually verified a model exists but it is not yet in the
  // /v1/models list, add it to `all` with a clearly-marked entry.
  static const List<String> knownMissingFromApi = [
    'laguna-s-2.1-free',
    'ling-3.0-flash-free',
    'inkling/Inkling',
    'inkling/Inkling-Small',
    'claude-opus-4-6',
    'claude-sonnet-4-5',
    'google/gemini-3.5-flash-lite',
  ];

  static const List<ModelPricing> all = [
    // === Open Source - DeepSeek ===
    ModelPricing(
      modelId: 'deepseek/deepseek-v4-pro',
      displayName: 'DeepSeek V4 Pro',
      inputPer1M: 0.435,
      outputPer1M: 0.87,
      cacheReadPer1M: 0.003625,
    ),
    ModelPricing(
      modelId: 'deepseek/deepseek-v4-flash',
      displayName: 'DeepSeek V4 Flash',
      inputPer1M: 0.14,
      outputPer1M: 0.28,
      cacheReadPer1M: 0.0028,
    ),

    // === Open Source - Xiaomi ===
    ModelPricing(
      modelId: 'xiaomi/mimo-v2.5-pro',
      displayName: 'MiMo V2.5 Pro',
      inputPer1M: 0.435,
      outputPer1M: 0.87,
      cacheReadPer1M: 0.0036,
    ),
    ModelPricing(
      modelId: 'xiaomi/mimo-v2.5',
      displayName: 'MiMo V2.5',
      inputPer1M: 0.14,
      outputPer1M: 0.28,
      cacheReadPer1M: 0.0028,
    ),

    // === Open Source - MiniMax ===
    ModelPricing(
      modelId: 'MiniMaxAI/MiniMax-M3',
      displayName: 'MiniMax M3',
      inputPer1M: 0.30,
      outputPer1M: 1.20,
      cacheReadPer1M: 0.06,
    ),
    ModelPricing(
      modelId: 'MiniMaxAI/MiniMax-M3-Free',
      displayName: 'MiniMax M3 Free',
      inputPer1M: 0.30,
      outputPer1M: 1.20,
      cacheReadPer1M: 0.06,
    ),
    ModelPricing(
      modelId: 'MiniMaxAI/MiniMax-M2.7',
      displayName: 'MiniMax M2.7',
      inputPer1M: 0.30,
      outputPer1M: 1.20,
      cacheReadPer1M: 0.06,
    ),
    ModelPricing(
      modelId: 'MiniMaxAI/MiniMax-M2.5',
      displayName: 'MiniMax M2.5',
      inputPer1M: 0.30,
      outputPer1M: 1.20,
      cacheReadPer1M: 0.03,
    ),

    // === Open Source - Moonshot (Kimi) ===
    ModelPricing(
      modelId: 'moonshotai/Kimi-K2.7-Code',
      displayName: 'Kimi K2.7 Code',
      inputPer1M: 0.95,
      outputPer1M: 4.00,
      cacheReadPer1M: 0.19,
    ),
    ModelPricing(
      modelId: 'moonshotai/Kimi-K2.7-Code-Highspeed',
      displayName: 'Kimi K2.7 Code HighSpeed',
      inputPer1M: 1.90,
      outputPer1M: 8.00,
      cacheReadPer1M: 0.38,
    ),
    ModelPricing(
      modelId: 'moonshotai/Kimi-K2.6',
      displayName: 'Kimi K2.6',
      inputPer1M: 0.95,
      outputPer1M: 4.00,
      cacheReadPer1M: 0.16,
    ),
    ModelPricing(
      modelId: 'moonshotai/Kimi-K2.5',
      displayName: 'Kimi K2.5',
      inputPer1M: 0.60,
      outputPer1M: 3.00,
      cacheReadPer1M: 0.10,
    ),

    // === Open Source - Qwen ===
    ModelPricing(
      modelId: 'Qwen/Qwen3.7-Max',
      displayName: 'Qwen 3.7 Max',
      inputPer1M: 2.50,
      outputPer1M: 7.50,
      cacheReadPer1M: 0.50,
      cacheWritePer1M: 3.13,
    ),
    ModelPricing(
      modelId: 'Qwen/Qwen3.7-Plus',
      displayName: 'Qwen 3.7 Plus',
      inputPer1M: 0.40,
      outputPer1M: 1.60,
      cacheReadPer1M: 0.08,
      cacheWritePer1M: 0.50,
    ),
    ModelPricing(
      modelId: 'Qwen/Qwen3.6-Max-Preview',
      displayName: 'Qwen 3.6 Max Preview',
      inputPer1M: 1.30,
      outputPer1M: 7.80,
      cacheReadPer1M: 0.26,
      cacheWritePer1M: 1.63,
    ),
    ModelPricing(
      modelId: 'Qwen/Qwen3.6-Plus',
      displayName: 'Qwen 3.6 Plus',
      inputPer1M: 0.50,
      outputPer1M: 3.00,
      cacheReadPer1M: 0.10,
    ),

    // === Open Source - Stepfun ===
    ModelPricing(
      modelId: 'stepfun/Step-3.7-Flash',
      displayName: 'Step 3.7 Flash',
      inputPer1M: 0.20,
      outputPer1M: 1.15,
      cacheReadPer1M: 0.04,
    ),
    ModelPricing(
      modelId: 'stepfun/Step-3.5-Flash',
      displayName: 'Step 3.5 Flash',
      inputPer1M: 0.10,
      outputPer1M: 0.30,
      cacheReadPer1M: 0.02,
    ),

    // === Open Source - ZAI (GLM) ===
    ModelPricing(
      modelId: 'zai-org/GLM-5.2',
      displayName: 'GLM 5.2',
      inputPer1M: 1.40,
      outputPer1M: 4.40,
      cacheReadPer1M: 0.26,
    ),
    ModelPricing(
      modelId: 'zai-org/GLM-5.2-Fast',
      displayName: 'GLM 5.2 Fast',
      inputPer1M: 3.00,
      outputPer1M: 10.25,
      cacheReadPer1M: 0.50,
    ),
    ModelPricing(
      modelId: 'zai-org/GLM-5.1',
      displayName: 'GLM 5.1',
      inputPer1M: 1.40,
      outputPer1M: 4.40,
      cacheReadPer1M: 0.26,
    ),
    ModelPricing(
      modelId: 'zai-org/GLM-5',
      displayName: 'GLM 5',
      inputPer1M: 1.00,
      outputPer1M: 3.20,
      cacheReadPer1M: 0.20,
    ),

    // === Open Source - Tencent ===
    ModelPricing(
      modelId: 'tencent/hy3-paid',
      displayName: 'Tencent HY3 Paid',
      inputPer1M: 0.14,
      outputPer1M: 0.58,
      cacheReadPer1M: 0.035,
    ),
    ModelPricing(
      modelId: 'tencent/Hy3',
      displayName: 'Tencent HY3',
      inputPer1M: 0.14,
      outputPer1M: 0.58,
      cacheReadPer1M: 0.035,
    ),

    // === Open Source - Nvidia ===
    ModelPricing(
      modelId: 'nvidia/nemotron-3-ultra-550b-a55b',
      displayName: 'Nvidia Nemotron 3 Ultra',
      inputPer1M: 0.60,
      outputPer1M: 2.40,
      cacheReadPer1M: 0.12,
    ),

    // === Premium - Anthropic ===
    ModelPricing(
      modelId: 'claude-fable-5',
      displayName: 'Claude Fable 5',
      inputPer1M: 10.00,
      outputPer1M: 50.00,
      cacheReadPer1M: 1.00,
      cacheWritePer1M: 12.50,
    ),
    ModelPricing(
      modelId: 'claude-opus-5',
      displayName: 'Claude Opus 5',
      inputPer1M: 5.00,
      outputPer1M: 25.00,
      cacheReadPer1M: 0.50,
      cacheWritePer1M: 6.25,
    ),
    ModelPricing(
      modelId: 'claude-opus-4-8',
      displayName: 'Claude Opus 4.8',
      inputPer1M: 5.00,
      outputPer1M: 25.00,
      cacheReadPer1M: 0.50,
      cacheWritePer1M: 6.25,
    ),
    ModelPricing(
      modelId: 'claude-opus-4-7',
      displayName: 'Claude Opus 4.7',
      inputPer1M: 5.00,
      outputPer1M: 25.00,
      cacheReadPer1M: 0.50,
      cacheWritePer1M: 6.25,
    ),
    ModelPricing(
      modelId: 'claude-sonnet-5',
      displayName: 'Claude Sonnet 5',
      inputPer1M: 2.00,
      outputPer1M: 10.00,
      cacheReadPer1M: 0.20,
      cacheWritePer1M: 2.50,
    ),
    ModelPricing(
      modelId: 'claude-sonnet-4-6',
      displayName: 'Claude Sonnet 4.6',
      inputPer1M: 3.00,
      outputPer1M: 15.00,
      cacheReadPer1M: 0.30,
      cacheWritePer1M: 3.75,
    ),
    ModelPricing(
      modelId: 'claude-haiku-4-5-20251001',
      displayName: 'Claude Haiku 4.5',
      inputPer1M: 1.00,
      outputPer1M: 5.00,
      cacheReadPer1M: 0.10,
      cacheWritePer1M: 1.25,
    ),

    // === Premium - OpenAI ===
    ModelPricing(
      modelId: 'gpt-5.6-sol',
      displayName: 'GPT 5.6 Sol',
      inputPer1M: 5.00,
      outputPer1M: 30.00,
      cacheReadPer1M: 0.50,
      cacheWritePer1M: 6.25,
    ),
    ModelPricing(
      modelId: 'gpt-5.6-terra',
      displayName: 'GPT 5.6 Terra',
      inputPer1M: 2.50,
      outputPer1M: 15.00,
      cacheReadPer1M: 0.25,
      cacheWritePer1M: 3.125,
    ),
    ModelPricing(
      modelId: 'gpt-5.6-luna',
      displayName: 'GPT 5.6 Luna',
      inputPer1M: 1.00,
      outputPer1M: 6.00,
      cacheReadPer1M: 0.10,
      cacheWritePer1M: 1.25,
    ),
    ModelPricing(
      modelId: 'gpt-5.5',
      displayName: 'GPT 5.5',
      inputPer1M: 5.00,
      outputPer1M: 30.00,
      cacheReadPer1M: 0.50,
    ),
    ModelPricing(
      modelId: 'gpt-5.4',
      displayName: 'GPT 5.4',
      inputPer1M: 2.50,
      outputPer1M: 15.00,
      cacheReadPer1M: 0.25,
    ),
    ModelPricing(
      modelId: 'gpt-5.4-mini',
      displayName: 'GPT 5.4 Mini',
      inputPer1M: 0.75,
      outputPer1M: 4.50,
      cacheReadPer1M: 0.075,
    ),
    ModelPricing(
      modelId: 'gpt-5.3-codex',
      displayName: 'GPT 5.3 Codex',
      inputPer1M: 2.00,
      outputPer1M: 8.00,
      cacheReadPer1M: 0.50,
    ),

    // === Premium - Google ===
    ModelPricing(
      modelId: 'google/gemini-3.5-flash',
      displayName: 'Gemini 3.5 Flash',
      inputPer1M: 1.50,
      outputPer1M: 9.00,
      cacheReadPer1M: 0.15,
    ),
    ModelPricing(
      modelId: 'google/gemini-3.1-flash-lite',
      displayName: 'Gemini 3.1 Flash Lite',
      inputPer1M: 0.25,
      outputPer1M: 1.50,
      cacheReadPer1M: 0.03,
    ),

    // === Premium - Other ===
    ModelPricing(
      modelId: 'sakana/fugu-ultra',
      displayName: 'Sakana Fugu Ultra',
      inputPer1M: 5.00,
      outputPer1M: 30.00,
      cacheReadPer1M: 0.50,
    ),
    ModelPricing(
      modelId: 'meta/muse-spark-1.1',
      displayName: 'Meta Muse Spark 1.1',
      inputPer1M: 1.25,
      outputPer1M: 4.25,
      cacheReadPer1M: 0.15,
    ),
    ModelPricing(
      modelId: 'xai/grok-4.5',
      displayName: 'xAI Grok 4.5',
      inputPer1M: 2.00,
      outputPer1M: 6.00,
      cacheReadPer1M: 0.50,
    ),
  ];

  static ModelPricing? byId(String id) {
    for (final p in all) {
      if (p.modelId == id) return p;
    }
    return null;
  }

  static List<ModelPricing> allAvailable() => all;

  static List<ModelPricing> byCategory(String category) {
    return all.where((p) {
      if (category == 'opensource') {
        return !p.modelId.startsWith('claude-') &&
            !p.modelId.startsWith('gpt-') &&
            !p.modelId.startsWith('google/gemini-') &&
            p.modelId != 'sakana/fugu-ultra' &&
            p.modelId != 'xai/grok-4.5';
      }
      if (category == 'premium') {
        return p.modelId.startsWith('claude-') ||
            p.modelId.startsWith('gpt-') ||
            p.modelId.startsWith('google/gemini-') ||
            p.modelId == 'sakana/fugu-ultra' ||
            p.modelId == 'xai/grok-4.5';
      }
      return true;
    }).toList();
  }
}
