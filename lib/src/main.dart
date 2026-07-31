import 'dart:async';
import 'dart:io';
import 'package:nocterm/nocterm.dart';
import 'models/account.dart';
import 'models/version.dart';
import 'services/log_store.dart';
import 'services/updater.dart';
import 'services/cost_sync.dart';
import 'services/pricing_db.dart';
import 'server/server_controller.dart';
import 'tui/app.dart';

const _usage = '''CommandCode Bridge  v$bridgeVersion

Usage:
  commandcode-bridge run
  commandcode-bridge run --server
  commandcode-bridge update
  commandcode-bridge cost-sync
  commandcode-bridge help

Commands:
  run           Start the bridge in TUI mode
  run --server  Start the bridge in headless server mode
  update        Download and install latest stable release
  cost-sync     Sync model pricing to CLI agent configs
  help          Show this help screen
  -v, --version Print version string
''';

void _printUsage() => stdout.write(_usage);
void _printUsageErr() => stderr.write(_usage);

Future<void> main(List<String> args) async {
  final noArgs = args.isEmpty;
  final showHelp = noArgs || args.contains('help') || args.contains('--help') || args.contains('-h');
  final isRun = !noArgs && args.first == 'run';
  final isUpdate = !noArgs && args.first == 'update';
  final isCostSync = !noArgs && args.first == 'cost-sync';

  if (args.contains('--version') || args.contains('-v')) {
    stdout.writeln('CommandCode Bridge v$bridgeVersion');
    return;
  }

  if (showHelp) {
    _printUsage();
    return;
  }

  if (isUpdate) {
    await _runUpdate();
    return;
  }

  if (isCostSync) {
    await _runCostSync();
    return;
  }

  if (!isRun) {
    _printUsageErr();
    exit(1);
  }

  LogStore.init();
  LogStore.info('CommandCode Bridge starting...');

  final accountStore = AccountStore();
  accountStore.load();

  final configStore = ConfigStore();
  configStore.load();

  if (!accountStore.isLoaded) {
    LogStore.warning('Not authenticated. Run cmd login first.');
  } else {
    LogStore.info('Authenticated as ${accountStore.account?.userName}');
  }

  final isServerMode = args.length > 1 && args[1] == '--server';
  final server = ServerController(accountStore: accountStore, configStore: configStore);

  try {
    await server.start();
  } catch (e) {
    stderr.writeln('Failed to start bridge: $e');
    LogStore.error('Failed to start bridge: $e');
    exit(1);
  }

  if (isServerMode) {
    LogStore.info('Server mode: running headless on port ${configStore.config.serverPort}');
    print('CommandCode Bridge running on http://127.0.0.1:${configStore.config.serverPort}');
    print('Press Ctrl+C to stop.');
    await _waitForSignal();
    server.stop();
    return;
  }

  LogStore.info('TUI mode starting...');

  final app = CmdBridgeApp(
    accountStore: accountStore,
    configStore: configStore,
    proxyServer: server,
  );

  await runApp(app);
  server.stop();
}

Future<void> _runUpdate() async {
  stdout.writeln('CommandCode Bridge v$bridgeVersion');
  stdout.writeln('Checking for stable update...');
  final updater = Updater();
  try {
    final result = await updater.update();
    if (result.success) {
      stdout.writeln(result.message);
      stdout.writeln('Restart the bridge to apply.');
    } else {
      stderr.writeln('Update failed: ${result.message}');
      exit(1);
    }
  } finally {
    updater.dispose();
  }
}

Future<void> _runCostSync() async {
  stdout.writeln('CommandCode Bridge v$bridgeVersion');
  stdout.writeln('Cost Sync - Model pricing for CLI agents');
  stdout.writeln('');

  // Load config to get the bridge port
  final configStore = ConfigStore();
  configStore.load();
  final bridgePort = configStore.config.serverPort;

  // Try to fetch live models from the bridge to validate PricingDb
  stdout.writeln('Fetching live model list from bridge /v1/models on port $bridgePort...');
  final liveIds = await CostSyncService.fetchLiveModelIds(port: bridgePort);
  if (liveIds == null) {
    stdout.writeln('  Warning: Bridge not reachable. Continuing without live validation.');
    stdout.writeln('  Start the bridge first (commandcode-bridge run) to validate pricing against the live API.');
    stdout.writeln('');
  } else {
    stdout.writeln('  Got ${liveIds.length} models from live API.');
    final report = CostSyncService.validateAgainstApi(liveIds);
    if (report.missingFromApi.isNotEmpty) {
      stdout.writeln('');
      stdout.writeln('  WARNING: ${report.missingFromApi.length} priced model(s) NOT in live /v1/models:');
      for (final p in report.missingFromApi) {
        stdout.writeln('    ${p.modelId}');
      }
      stdout.writeln('  These are kept for backwards compatibility but will not be syncable.');
    }
    if (report.pricingForUnknown.isNotEmpty) {
      stdout.writeln('');
      stdout.writeln('  NOTE: ${report.pricingForUnknown.length} live model(s) have NO pricing data:');
      for (final id in report.pricingForUnknown) {
        stdout.writeln('    $id');
      }
    }
    if (report.isClean) {
      stdout.writeln('  All PricingDb entries validated against live API.');
    }
    stdout.writeln('');
  }

  final agents = CostSyncService.detectAgents();
  final detected = agents.where((a) => a.detected).toList();
  final notDetected = agents.where((a) => !a.detected).toList();

  if (detected.isEmpty) {
    stdout.writeln('No supported CLI agents found.');
    stdout.writeln('');
    for (final agent in notDetected) {
      stderr.writeln('  ${agent.displayName.padRight(10)} not found: ${agent.configPath}');
    }
    stdout.writeln('');
    stdout.writeln('Supported agents: OpenCode, Aider, Goose');
    stdout.writeln('If your CLI agent is not listed, it does not support cost tracking.');
    return;
  }

  stdout.writeln('Detected CLI agents:');
  for (var i = 0; i < detected.length; i++) {
    stdout.writeln('  [${i + 1}] ${detected[i].displayName.padRight(10)} ${detected[i].configPath}');
  }
  for (final agent in notDetected) {
    stdout.writeln('  [-] ${agent.displayName.padRight(10)} not found');
  }
  stdout.writeln('');

  if (detected.length == 1) {
    final agent = detected.first;
    stdout.writeln('Auto-selecting: ${agent.displayName}');
    await _syncAgent(agent);
    return;
  }

  stdout.write('Select agent (1-${detected.length}): ');
  final input = stdin.readLineSync()?.trim();
  final choice = int.tryParse(input ?? '');
  if (choice == null || choice < 1 || choice > detected.length) {
    stderr.writeln('Invalid selection.');
    exit(1);
  }

  await _syncAgent(detected[choice - 1]);
}

Future<void> _syncAgent(CliAgentInfo agent) async {
  stdout.writeln('');

  List<String> models;
  if (agent.type == CliAgentType.opencode) {
    final info = CostSyncService.getOpenCodeBridgeModels();
    models = info.models;
    if (info.providers.isNotEmpty) {
      stdout.writeln('Bridge provider:');
      for (final prov in info.providers) {
        stdout.writeln('  - ${prov.name} [${prov.host}:${prov.port}]');
      }
    }
  } else {
    models = CostSyncService.getUserModels(agent.type);
  }

  stdout.writeln('Reading models from ${agent.displayName} config...');

  if (models.isEmpty) {
    stdout.writeln('No bridge models found in ${agent.displayName} config.');
    return;
  }

  stdout.writeln('Found ${models.length} bridge model(s):');
  for (final m in models) {
    final pricing = PricingDb.byId(m);
    if (pricing != null) {
      stdout.writeln('  ${m.padRight(40)} \$${pricing.inputPer1M}/\$${pricing.outputPer1M} per 1M');
    } else {
      stdout.writeln('  ${m.padRight(40)} (no pricing data)');
    }
  }
  stdout.writeln('');

  stdout.write('Sync costs to ${agent.displayName}? [Y/n]: ');
  final confirm = stdin.readLineSync()?.trim().toLowerCase() ?? '';
  if (confirm == 'n' || confirm == 'no') {
    stdout.writeln('Cancelled.');
    return;
  }

  stdout.writeln('Syncing...');
  final result = CostSyncService.syncCosts(agent.type, models);

  for (final msg in result.messages) {
    stdout.writeln('  $msg');
  }
  stdout.writeln('');

  if (result.success) {
    stdout.writeln('Done. ${result.updated} model(s) updated, ${result.skipped} already configured.');
  } else {
    stderr.writeln('Completed with errors. ${result.updated} updated, ${result.failed} failed.');
    exit(1);
  }
}

Future<void> _waitForSignal() async {
  final completer = Completer<void>();
  final sigintSub = ProcessSignal.sigint.watch().listen((_) {
    if (!completer.isCompleted) completer.complete();
  });
  final sigtermSub = ProcessSignal.sigterm.watch().listen((_) {
    if (!completer.isCompleted) completer.complete();
  });
  await completer.future;
  await sigintSub.cancel();
  await sigtermSub.cancel();
}
