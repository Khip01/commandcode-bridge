import 'dart:convert';
import 'dart:io';

import 'log_store.dart';
import 'pricing_db.dart';

enum CliAgentType { opencode, aider, goose }

class CliAgentInfo {
  final CliAgentType type;
  final String displayName;
  final String configPath;
  final bool detected;

  const CliAgentInfo({
    required this.type,
    required this.displayName,
    required this.configPath,
    required this.detected,
  });
}

class SyncResult {
  final int updated;
  final int skipped;
  final int failed;
  final List<String> messages;

  SyncResult({
    required this.updated,
    required this.skipped,
    required this.failed,
    required this.messages,
  });

  bool get success => failed == 0;
  int get total => updated + skipped + failed;
}

class BridgeProviderInfo {
  final String name;
  final String host;
  final int port;

  BridgeProviderInfo({
    required this.name,
    required this.host,
    required this.port,
  });

  @override
  String toString() => '$name [$host:$port]';
}

class OpenCodeBridgeInfo {
  final List<String> models;
  final List<BridgeProviderInfo> providers;

  OpenCodeBridgeInfo({
    required this.models,
    this.providers = const [],
  });
}

class ApiValidationReport {
  /// Models in PricingDb that are NOT in the live /v1/models response.
  /// These should NOT be displayed in the "will be implemented" list.
  final List<ModelPricing> missingFromApi;

  /// Live model IDs that have no entry in PricingDb.
  /// The user should be told their config references models we cannot price.
  final List<String> pricingForUnknown;

  ApiValidationReport({
    required this.missingFromApi,
    required this.pricingForUnknown,
  });

  bool get isClean => missingFromApi.isEmpty && pricingForUnknown.isEmpty;
}

class CostSyncService {
  static String _homeDir() {
    if (Platform.isWindows) {
      return Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Default';
    }
    return Platform.environment['HOME'] ?? '/root';
  }

  static List<CliAgentInfo> detectAgents() {
    final home = _homeDir();
    final sep = Platform.pathSeparator;

    final openCodePath = '$home${sep}.config${sep}opencode${sep}opencode.jsonc';
    final aiderPath = '$home${sep}.aider.model.metadata.json';
    final goosePath = '$home${sep}.config${sep}goose${sep}custom_providers';

    return [
      CliAgentInfo(
        type: CliAgentType.opencode,
        displayName: 'OpenCode',
        configPath: openCodePath,
        detected: File(openCodePath).existsSync(),
      ),
      CliAgentInfo(
        type: CliAgentType.aider,
        displayName: 'Aider',
        configPath: aiderPath,
        detected: File(aiderPath).existsSync(),
      ),
      CliAgentInfo(
        type: CliAgentType.goose,
        displayName: 'Goose',
        configPath: goosePath,
        detected: Directory(goosePath).existsSync(),
      ),
    ];
  }

  static List<String> getUserModels(CliAgentType agent) {
    switch (agent) {
      case CliAgentType.opencode:
        return _getOpenCodeModels().models;
      case CliAgentType.aider:
        return _getAiderModels();
      case CliAgentType.goose:
        return _getGooseModels();
    }
  }

  static OpenCodeBridgeInfo getOpenCodeBridgeModels() => _getOpenCodeModels();

  /// Fetch the live list of model IDs from the bridge's /v1/models endpoint.
  /// Returns null if the bridge is not reachable or not authenticated.
  /// Used to validate that PricingDb entries actually exist on the API.
  static Future<Set<String>?> fetchLiveModelIds({
    required int port,
    String host = '127.0.0.1',
  }) async {
    try {
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse('http://$host:$port/v1/models'));
      final res = await req.close();
      if (res.statusCode != 200) {
        client.close();
        return null;
      }
      final body = await res.transform(utf8.decoder).join();
      client.close();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final list = data['data'] as List<dynamic>? ?? [];
      return list
          .whereType<Map<String, dynamic>>()
          .map((m) => m['id'] as String?)
          .whereType<String>()
          .toSet();
    } catch (e) {
      LogStore.warning('fetchLiveModelIds failed: $e');
      return null;
    }
  }

  /// Validate PricingDb against the live /v1/models response.
  /// Returns (missingFromApi, pricingForUnknown) so the UI can warn the user.
  static ApiValidationReport validateAgainstApi(Set<String> liveModelIds) {
    final knownMissing = PricingDb.knownMissingFromApi.toSet();
    final missingFromApi = <ModelPricing>[];
    final unknownPricing = <String>[];

    for (final p in PricingDb.all) {
      if (knownMissing.contains(p.modelId)) continue;
      if (!liveModelIds.contains(p.modelId)) {
        missingFromApi.add(p);
      }
    }

    for (final liveId in liveModelIds) {
      if (PricingDb.byId(liveId) == null) {
        unknownPricing.add(liveId);
      }
    }

    return ApiValidationReport(
      missingFromApi: missingFromApi,
      pricingForUnknown: unknownPricing,
    );
  }

  /// Filter a list of model IDs down to those that exist in PricingDb.
  /// Use this on whatever models come out of the user's config before
  /// displaying or syncing them, so we never show pricing for a model
  /// that is not actually priced.
  static List<String> filterKnownPriced(List<String> modelIds) {
    return modelIds.where((id) => PricingDb.byId(id) != null).toList();
  }

  static OpenCodeBridgeInfo _getOpenCodeModels() {
    final home = _homeDir();
    final sep = Platform.pathSeparator;
    final path = '$home${sep}.config${sep}opencode${sep}opencode.jsonc';
    final file = File(path);
    if (!file.existsSync()) return OpenCodeBridgeInfo(models: []);

    try {
      final raw = file.readAsStringSync();
      final jsonStr = _stripJsoncComments(raw);
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final provider = data['provider'] as Map<String, dynamic>? ?? {};

      // Find providers whose baseURL points to the bridge (127.0.0.1:<port>)
      // AND whose name identifies them as a Command Code bridge provider.
      final models = <String>[];
      final providers = <BridgeProviderInfo>[];

      for (final entry in provider.entries) {
        final prov = entry.value;
        if (prov is! Map) continue;
        final options = prov['options'] as Map<String, dynamic>? ?? {};
        final baseUrl = options['baseURL'] as String? ?? '';
        if (baseUrl.isEmpty) continue;

        final uri = Uri.tryParse(baseUrl);
        if (uri == null) continue;
        if (uri.host != '127.0.0.1' && uri.host != 'localhost') continue;

        // Match provider name containing "Command Code" to identify the bridge
        final provName = entry.key.toString().toLowerCase();
        final isCommandCodeProvider = provName.contains('command code') || provName.contains('commandcode');
        if (!isCommandCodeProvider) continue;

        providers.add(BridgeProviderInfo(
          name: entry.key,
          host: uri.host,
          port: uri.port,
        ));

        final modelsMap = prov['models'] as Map<String, dynamic>? ?? {};
        for (final modelId in modelsMap.keys) {
          if (!models.contains(modelId)) {
            models.add(modelId);
          }
        }
      }

      return OpenCodeBridgeInfo(
        models: models,
        providers: providers,
      );
    } catch (e) {
      LogStore.error('Failed to read OpenCode config: $e');
      return OpenCodeBridgeInfo(models: []);
    }
  }

  static List<String> _getAiderModels() {
    final home = _homeDir();
    final sep = Platform.pathSeparator;
    final path = '$home${sep}.aider.model.metadata.json';
    final file = File(path);
    if (!file.existsSync()) return [];

    try {
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return data.keys.whereType<String>().toList();
    } catch (e) {
      LogStore.error('Failed to read Aider config: $e');
      return [];
    }
  }

  static List<String> _getGooseModels() {
    final home = _homeDir();
    final sep = Platform.pathSeparator;
    final dirPath = '$home${sep}.config${sep}goose${sep}custom_providers';
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return [];

    try {
      final models = <String>[];
      for (final file in dir.listSync().whereType<File>()) {
        if (!file.path.endsWith('.json')) continue;
        final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final modelsList = data['models'] as List<dynamic>? ?? [];
        for (final m in modelsList) {
          if (m is Map) {
            final name = m['name'] as String?;
            if (name != null && !models.contains(name)) {
              models.add(name);
            }
          }
        }
      }
      return models;
    } catch (e) {
      LogStore.error('Failed to read Goose config: $e');
      return [];
    }
  }

  static SyncResult syncCosts(CliAgentType agent, List<String> modelIds) {
    final pricedModels = <String>[];
    final unknownModels = <String>[];

    for (final id in modelIds) {
      final pricing = PricingDb.byId(id);
      if (pricing == null) {
        unknownModels.add(id);
      } else {
        pricedModels.add(id);
      }
    }

    final messages = <String>[];
    if (unknownModels.isNotEmpty) {
      messages.add('No pricing data: ${unknownModels.join(", ")}');
    }

    switch (agent) {
      case CliAgentType.opencode:
        return _syncOpenCode(pricedModels, messages);
      case CliAgentType.aider:
        return _syncAider(pricedModels, messages);
      case CliAgentType.goose:
        return _syncGoose(pricedModels, messages);
    }
  }

  static SyncResult _syncOpenCode(List<String> modelIds, List<String> messages) {
    final home = _homeDir();
    final sep = Platform.pathSeparator;
    final path = '$home${sep}.config${sep}opencode${sep}opencode.jsonc';
    final file = File(path);
    if (!file.existsSync()) {
      messages.add('OpenCode config not found at $path');
      return SyncResult(updated: 0, skipped: 0, failed: 0, messages: messages);
    }

    try {
      final raw = file.readAsStringSync();
      final jsonStr = _stripJsoncComments(raw);
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final provider = data['provider'] as Map<String, dynamic>? ?? {};

      var updated = 0;
      var skipped = 0;

      for (final provEntry in provider.entries) {
        final prov = provEntry.value;
        if (prov is! Map) continue;
        final modelsMap = prov['models'] as Map<String, dynamic>? ?? {};

        for (final modelId in modelIds) {
          final modelEntry = modelsMap[modelId];
          if (modelEntry is! Map) continue;

          final existing = modelEntry['cost'] as Map<String, dynamic>?;
          if (existing != null) {
            skipped++;
            continue;
          }

          final pricing = PricingDb.byId(modelId);
          if (pricing == null) continue;

          modelEntry['cost'] = {
            'input': pricing.inputPer1M,
            'output': pricing.outputPer1M,
            'cache_read': pricing.cacheReadPer1M,
            if (pricing.cacheWritePer1M > 0) 'cache_write': pricing.cacheWritePer1M,
          };
          updated++;
        }
      }

      if (updated > 0) {
        _writeJsoncPreservingComments(file, raw, data);
      }

      messages.add('OpenCode: $updated updated, $skipped already configured');
      LogStore.info('Cost sync OpenCode: $updated updated, $skipped skipped');
      return SyncResult(updated: updated, skipped: skipped, failed: 0, messages: messages);
    } catch (e) {
      messages.add('OpenCode sync failed: $e');
      LogStore.error('Cost sync OpenCode failed: $e');
      return SyncResult(updated: 0, skipped: 0, failed: 1, messages: messages);
    }
  }

  static SyncResult _syncAider(List<String> modelIds, List<String> messages) {
    final home = _homeDir();
    final sep = Platform.pathSeparator;
    final path = '$home${sep}.aider.model.metadata.json';

    Map<String, dynamic> existing = {};
    final file = File(path);
    if (file.existsSync()) {
      try {
        existing = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      } catch (_) {}
    }

    var updated = 0;
    var skipped = 0;

    for (final modelId in modelIds) {
      final pricing = PricingDb.byId(modelId);
      if (pricing == null) continue;

      final key = 'commandcode/$modelId';
      final entry = existing[key] as Map<String, dynamic>?;
      if (entry != null && entry['input_cost_per_token'] != null) {
        skipped++;
        continue;
      }

      existing[key] = {
        'input_cost_per_token': pricing.inputPer1M / 1000000,
        'output_cost_per_token': pricing.outputPer1M / 1000000,
        'cache_read_cost_per_token': pricing.cacheReadPer1M / 1000000,
      };
      updated++;
    }

    if (updated > 0) {
      file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(existing));
    }

    messages.add('Aider: $updated updated, $skipped already configured');
    LogStore.info('Cost sync Aider: $updated updated, $skipped skipped');
    return SyncResult(updated: updated, skipped: skipped, failed: 0, messages: messages);
  }

  static SyncResult _syncGoose(List<String> modelIds, List<String> messages) {
    final home = _homeDir();
    final sep = Platform.pathSeparator;
    final dirPath = '$home${sep}.config${sep}goose${sep}custom_providers';
    final filePath = '$dirPath${sep}cmd-bridge.json';

    Directory(dirPath).createSync(recursive: true);

    Map<String, dynamic> existing = {};
    final file = File(filePath);
    if (file.existsSync()) {
      try {
        existing = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      } catch (_) {}
    }

    if (existing.isEmpty) {
      existing = {
        'name': 'Command Code Bridge',
        'type': 'openai',
        'base_url': 'http://127.0.0.1:17077/v1',
        'models': <Map<String, dynamic>>[],
      };
    }

    final modelsList = (existing['models'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final existingNames = modelsList.map((m) => m['name'] as String?).whereType<String>().toSet();

    var updated = 0;
    var skipped = 0;

    for (final modelId in modelIds) {
      final pricing = PricingDb.byId(modelId);
      if (pricing == null) continue;

      if (existingNames.contains(modelId)) {
        final idx = modelsList.indexWhere((m) => m['name'] == modelId);
        if (idx >= 0 && modelsList[idx]['input_token_cost'] != null) {
          skipped++;
          continue;
        }
        if (idx >= 0) {
          modelsList[idx]['input_token_cost'] = pricing.inputPer1M / 1000000;
          modelsList[idx]['output_token_cost'] = pricing.outputPer1M / 1000000;
          updated++;
          continue;
        }
      }

      modelsList.add({
        'name': modelId,
        'input_token_cost': pricing.inputPer1M / 1000000,
        'output_token_cost': pricing.outputPer1M / 1000000,
      });
      updated++;
    }

    existing['models'] = modelsList;

    if (updated > 0) {
      file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(existing));
    }

    messages.add('Goose: $updated updated, $skipped already configured');
    LogStore.info('Cost sync Goose: $updated updated, $skipped skipped');
    return SyncResult(updated: updated, skipped: skipped, failed: 0, messages: messages);
  }

  static String _stripJsoncComments(String raw) {
    final result = StringBuffer();
    var i = 0;
    final len = raw.length;
    var inString = false;
    var escapeNext = false;

    while (i < len) {
      final ch = raw[i];

      if (escapeNext) {
        result.write(ch);
        escapeNext = false;
        i++;
        continue;
      }

      if (inString) {
        result.write(ch);
        if (ch == '\\') escapeNext = true;
        if (ch == '"') inString = false;
        i++;
        continue;
      }

      if (ch == '"') {
        inString = true;
        result.write(ch);
        i++;
        continue;
      }

      if (ch == '/' && i + 1 < len && raw[i + 1] == '/') {
        while (i < len && raw[i] != '\n') {
          i++;
        }
        continue;
      }

      if (ch == '/' && i + 1 < len && raw[i + 1] == '*') {
        i += 2;
        while (i + 1 < len && !(raw[i] == '*' && raw[i + 1] == '/')) {
          i++;
        }
        i += 2;
        continue;
      }

      result.write(ch);
      i++;
    }

    // Remove trailing commas before } or ]
    var output = result.toString();
    output = output.replaceAllMapped(RegExp(r',\s*([}\]])'), (m) => m.group(1)!);
    return output;
  }

  static void _writeJsoncPreservingComments(File file, String original, Map<String, dynamic> data) {
    final encoder = JsonEncoder.withIndent('  ');
    final newJson = encoder.convert(data);
    file.writeAsStringSync(newJson);
  }
}
