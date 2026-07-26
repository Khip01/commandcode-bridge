import 'dart:async';
import 'dart:io';
import 'package:nocterm/nocterm.dart';
import 'models/account.dart';
import 'services/log_store.dart';
import 'server/proxy.dart';
import 'tui/app.dart';

Future<void> main(List<String> args) async {
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

  final isServerMode = args.contains('server');
  final proxyServer = ProxyServer(accountStore: accountStore, configStore: configStore);

  try {
    await proxyServer.start();
  } catch (e) {
    stderr.writeln('Failed to start proxy: $e');
    LogStore.error('Failed to start proxy: $e');
    exit(1);
  }

  if (isServerMode) {
    LogStore.info('Server mode: running headless on port ${configStore.config.serverPort}');
    print('CommandCode Bridge running on http://127.0.0.1:${configStore.config.serverPort}');
    print('Press Ctrl+C to stop.');
    await _waitForSignal();
    proxyServer.stop();
    return;
  }

  LogStore.info('TUI mode starting...');

  final app = CmdBridgeApp(
    accountStore: accountStore,
    configStore: configStore,
    proxyServer: proxyServer,
  );

  await runApp(app);
  proxyServer.stop();
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
