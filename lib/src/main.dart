import 'dart:async';
import 'dart:io';
import 'package:nocterm/nocterm.dart';
import 'models/account.dart';
import 'services/log_store.dart';
import 'server/server_controller.dart';
import 'tui/app.dart';

const _usage = '''CommandCode Bridge

Usage:
  commandcode-bridge run
  commandcode-bridge run --server
  commandcode-bridge help

Commands:
  run           Start the bridge in TUI mode
  run --server  Start the bridge in headless server mode
  help          Show this help screen
''';

void _printUsage() => stdout.write(_usage);
void _printUsageErr() => stderr.write(_usage);

Future<void> main(List<String> args) async {
  final noArgs = args.isEmpty;
  final showHelp = noArgs || args.contains('help') || args.contains('--help') || args.contains('-h');
  final isRun = !noArgs && args.first == 'run';

  if (showHelp) {
    if (noArgs) {
      _printUsage();
    } else {
      _printUsage();
    }
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
