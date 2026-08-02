import 'dart:async';
import 'dart:io';
import 'package:nocterm/nocterm.dart' hide LogEntry;
import '../models/account.dart';
import '../models/models_db.dart';
import '../services/api_client.dart';
import '../services/log_store.dart';
import '../services/cost_sync.dart';
import '../services/pricing_db.dart';
import '../server/server_controller.dart';

class CmdBridgeApp extends StatefulComponent {
  final AccountStore accountStore;
  final ConfigStore configStore;
  final ServerController proxyServer;

  CmdBridgeApp({
    required this.accountStore,
    required this.configStore,
    required this.proxyServer,
  });

  @override
  State<CmdBridgeApp> createState() => AppState();
}

enum _Panel { main, help, quit, login, importKey, portConfig }

enum _InfoPage { account, plan, usage, limits, models, proxy, cost }

class AppState extends State<CmdBridgeApp> {
  late final _account = component.accountStore;
  late final _config = component.configStore;
  late final _proxy = component.proxyServer;

  _Panel _panel = _Panel.main;
  _InfoPage _infoPage = _InfoPage.account;
  int _selectedModelIndex = 0;
  List<ModelInfo> _orderedModels = [];
  bool _modelsInitialized = false;
  bool _showLog = false;
  bool _logFullscreen = false;
  String _status = '';
  Timer? _statusTimer;
  Timer? _pageRefreshTimer;
  DateTime _startTime = DateTime.now();

  AllApiData? _apiData;
  bool _loadingData = false;
  bool _foregroundRefresh = true;
  DateTime? _lastAutoRefreshAt;
  int _lastLogVersion = -1;
  int _lastModelVersion = 0;

  final _portCtrl = TextEditingController();
  bool _portScanDone = false;
  final Map<int, bool> _portStatus = {};
  bool _confirmClearLog = false;

  // Cost sync state
  List<CliAgentInfo> _costAgents = [];
  int _costSelectedAgent = 0;
  bool _costSyncing = false;
  Set<String> _costLiveModelIds = {};
  bool _costLiveFetched = false;

  final _infoScrollCtrl = ScrollController();
  final _logScrollCtrl = ScrollController();

  static const _pageKeys = ['1', '2', '3', '4', '5', '6', '7'];
  static const _pageNames = ['Account', 'Plan', 'Usage', 'Limits', 'Models', 'Proxy', 'Cost'];

  @override
  void initState() {
    super.initState();
    _refreshData();
    _startActivePageRefresh();
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _pageRefreshTimer?.cancel();
    _portCtrl.dispose();
    _infoScrollCtrl.dispose();
    _logScrollCtrl.dispose();
    super.dispose();
  }

  Duration _refreshIntervalForPage(_InfoPage page) {
    switch (page) {
      case _InfoPage.account:
        return const Duration(seconds: 20);
      case _InfoPage.plan:
        return const Duration(seconds: 15);
      case _InfoPage.usage:
        return const Duration(seconds: 8);
      case _InfoPage.limits:
        return const Duration(seconds: 8);
      case _InfoPage.models:
        return const Duration(seconds: 30);
      case _InfoPage.proxy:
        return const Duration(seconds: 1);
      case _InfoPage.cost:
        return const Duration(seconds: 30);
    }
  }

  void _startActivePageRefresh() {
    _pageRefreshTimer?.cancel();
    _pageRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _refreshVisiblePage();
    });
  }

  String _refreshLabel() {
    if (_loadingData && !_foregroundRefresh) return 'Refreshing in background';
    if (_lastAutoRefreshAt == null) return 'Idle';
    final secs = DateTime.now().difference(_lastAutoRefreshAt!).inSeconds;
    return 'Updated ${secs}s ago';
  }

  void _refreshVisiblePage() {
    if (!mounted || _panel != _Panel.main) return;

    final now = DateTime.now();
    final interval = _refreshIntervalForPage(_infoPage);

    if (_showLog && _lastLogVersion != LogStore.version) {
      _lastLogVersion = LogStore.version;
      setState(() {});
      return;
    }

    if (_lastModelVersion != _proxy.modelVersion) {
      _lastModelVersion = _proxy.modelVersion;
      setState(() {});
      return;
    }

    if (_infoPage == _InfoPage.proxy) {
      setState(() {});
      return;
    }

    if (_loadingData) return;
    if (_lastAutoRefreshAt != null && now.difference(_lastAutoRefreshAt!) < interval) {
      return;
    }

    _lastAutoRefreshAt = now;
    _refreshData(silent: true, foreground: false);
  }

  void _setInfoPage(_InfoPage page) {
    _infoPage = page;
    _selectedModelIndex = 0;
    _infoScrollCtrl.jumpTo(0);
    _lastAutoRefreshAt = null;
    _refreshVisiblePage();
    setState(() {});
  }

  Color _notifColor() {
    final msg = _status;
    if (msg.startsWith('Data refreshed') || msg.contains('Copied')) return Colors.green;
    if (msg.startsWith('Cost sync') && msg.contains('failed')) return Colors.red;
    if (msg.startsWith('Cost sync')) return Colors.green;
    if (msg.startsWith('Fetching') || msg.startsWith('Opening') || msg.startsWith('Copying')) return Colors.cyan;
    if (msg.startsWith('Use [q] to quit')) return Colors.red;
    if (msg.startsWith('No API') || msg.startsWith('Refresh failed') || msg.contains('failed') || msg.contains('Invalid') || msg.contains('in use') || msg.contains('Cannot')) return Colors.red;
    if (msg.contains('Clear') || msg.contains('Warning') || msg.contains('Restart') || msg.contains('Already') || msg.contains('confirm') || msg.startsWith('No entries')) return Colors.yellow;
    return Colors.cyan;
  }

  void _setStatus(String msg, {int? duration}) {
    _statusTimer?.cancel();
    _status = msg;
    setState(() {});
    if (duration != null && duration > 0) {
      _statusTimer = Timer(Duration(seconds: duration), () {
        _status = '';
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Component build(BuildContext context) {
    return Focusable(
      focused: true,
      onKeyEvent: _onKey,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(child: _buildBody()),
          _buildStatusBar(),
          _buildFooter(),
        ],
      ),
    );
  }

  bool _onKey(KeyboardEvent e) {
    if (_panel == _Panel.help) {
      if (e.logicalKey == LogicalKey.escape ||
          e.logicalKey == LogicalKey.keyH ||
          e.logicalKey == LogicalKey.enter ||
          e.logicalKey == LogicalKey.space) {
        _panel = _Panel.main;
        _startActivePageRefresh();
        setState(() {});
        return true;
      }
      return false;
    }

    if (_panel == _Panel.quit) {
      if (e.logicalKey == LogicalKey.keyY ||
          e.logicalKey == LogicalKey.enter ||
          (e.logicalKey == LogicalKey.keyC && e.isControlPressed)) {
        _doQuit();
        return true;
      }
      if (e.logicalKey == LogicalKey.keyN ||
          e.logicalKey == LogicalKey.escape) {
        _panel = _Panel.main;
        _startActivePageRefresh();
        setState(() {});
        return true;
      }
      return false;
    }

    if (_panel == _Panel.login || _panel == _Panel.importKey) {
      if (e.logicalKey == LogicalKey.escape) {
        _panel = _Panel.main;
        _startActivePageRefresh();
        setState(() {});
        return true;
      }
      if (_panel == _Panel.login && e.logicalKey == LogicalKey.keyI) {
        _panel = _Panel.importKey;
        setState(() {});
        return true;
      }
      return false;
    }

    if (_panel == _Panel.portConfig) {
      if (e.logicalKey == LogicalKey.escape) {
        _panel = _Panel.main;
        _startActivePageRefresh();
        setState(() {});
        return true;
      }
      if (e.logicalKey == LogicalKey.enter) {
        _doSetPort();
        return true;
      }
      return false;
    }

    if (_panel == _Panel.main) {
      if (e.logicalKey == LogicalKey.keyC && e.isControlPressed) {
        _setStatus('Use [q] to quit', duration: 3);
        return true;
      }

      if (e.logicalKey == LogicalKey.keyL && e.isControlPressed) {
        _showLog = !_showLog;
        if (_showLog) _logFullscreen = false;
        _lastLogVersion = LogStore.version;
        setState(() {});
        return true;
      }

      if (_showLog) {
        if (_confirmClearLog) {
          if (e.logicalKey == LogicalKey.keyY || e.logicalKey == LogicalKey.enter) {
            _doConfirmClear();
            return true;
          }
          if (e.logicalKey == LogicalKey.keyN || e.logicalKey == LogicalKey.escape) {
            _cancelConfirmClear();
            return true;
          }
          return false;
        }

        if (e.logicalKey == LogicalKey.keyF) {
          _logFullscreen = !_logFullscreen;
          setState(() {});
          return true;
        }
        if (e.logicalKey == LogicalKey.keyC && e.isShiftPressed) {
          if (LogStore.entries.isEmpty) return false;
          _confirmClearLog = true;
          _setStatus('Clear all logs? [Y]es [N]o', duration: 0);
          setState(() {});
          return true;
        }
        if (e.logicalKey == LogicalKey.keyO && e.isShiftPressed) {
          final n = LogStore.countBeforeToday();
          if (n == 0) {
            _setStatus('No entries before today', duration: 3);
            return true;
          }
          _confirmClearLog = true;
          _setStatus('Clear $n entries before today? [Y]es [N]o', duration: 0);
          setState(() {});
          return true;
        }
        if (e.logicalKey == LogicalKey.keyL && e.isControlPressed) {
          _showLog = false;
          _logFullscreen = false;
          _lastLogVersion = LogStore.version;
          setState(() {});
          return true;
        }
      }

      switch (e.logicalKey) {
        case LogicalKey.digit1:
        case LogicalKey.digit2:
        case LogicalKey.digit3:
        case LogicalKey.digit4:
        case LogicalKey.digit5:
        case LogicalKey.digit6:
        case LogicalKey.digit7:
          final idx = e.logicalKey == LogicalKey.digit1 ? 0
              : e.logicalKey == LogicalKey.digit2 ? 1
              : e.logicalKey == LogicalKey.digit3 ? 2
              : e.logicalKey == LogicalKey.digit4 ? 3
              : e.logicalKey == LogicalKey.digit5 ? 4
              : e.logicalKey == LogicalKey.digit6 ? 5
              : 6;
          _setInfoPage(_InfoPage.values[idx]);
          return true;

        case LogicalKey.keyR:
          _refreshData(foreground: true);
          return true;

        case LogicalKey.keyO:
          _copyEndpointUrl();
          return true;

        case LogicalKey.keyA:
          _copyAnthropicUrl();
          return true;

        case LogicalKey.keyC:
          if (_infoPage == _InfoPage.cost && !_costSyncing) {
            _doCostSync();
            return true;
          }
          return false;

        case LogicalKey.keyP:
          _showPortConfig();
          return true;

        case LogicalKey.keyL:
          if (!_account.isLoaded) {
            _startLogin();
          }
          return true;

        case LogicalKey.keyH:
          _panel = _Panel.help;
          setState(() {});
          return true;

        case LogicalKey.keyQ:
          _panel = _Panel.quit;
          setState(() {});
          return true;

        case LogicalKey.arrowUp:
          if (_infoPage == _InfoPage.models && _selectedModelIndex > 0) {
            _selectedModelIndex--;
            _scrollToModel();
            setState(() {});
          } else if (_infoPage == _InfoPage.cost && _costSelectedAgent > 0) {
            _costSelectedAgent--;
            setState(() {});
          } else {
            _scrollUp(1);
          }
          return true;

        case LogicalKey.arrowDown:
          if (_infoPage == _InfoPage.models) {
            _initOrderedModels();
            if (_selectedModelIndex < _orderedModels.length - 1) {
              _selectedModelIndex++;
              _scrollToModel();
              setState(() {});
            }
          } else if (_infoPage == _InfoPage.cost) {
            _initCostAgents();
            if (_costSelectedAgent < _costAgents.length - 1) {
              _costSelectedAgent++;
              setState(() {});
            }
          } else {
            _scrollDown(1);
          }
          return true;

        case LogicalKey.enter:
          if (_infoPage == _InfoPage.models) {
            _copyModelId();
            return true;
          }
          return false;

        case LogicalKey.pageUp:
          _scrollUp(10);
          return true;

        case LogicalKey.pageDown:
          _scrollDown(10);
          return true;

        default:
          return false;
      }
    }
    return false;
  }

  void _scrollUp(int lines) {
    final newOffset = (_infoScrollCtrl.offset - lines * 1).clamp(0.0, double.infinity);
    _infoScrollCtrl.jumpTo(newOffset);
  }

  void _scrollDown(int lines) {
    _infoScrollCtrl.jumpTo(_infoScrollCtrl.offset + lines);
  }

  void _scrollToModel() {
    // Approximate scroll: each model row is ~1 line, offset by header
    final offset = (_selectedModelIndex * 1.0).clamp(0.0, double.infinity);
    _infoScrollCtrl.jumpTo(offset);
  }

  void _refreshData({bool silent = false, bool foreground = true}) async {
    if (_loadingData) return;
    final acc = _account.account;
    if (acc == null) {
      if (!silent) {
        _setStatus('No API key. Run cmd login first.', duration: 5);
      }
      return;
    }
    _loadingData = true;
    _foregroundRefresh = foreground;
    if (!silent) {
      _setStatus('Fetching data...');
    }
    if (foreground) {
      setState(() {});
    }

    final client = ApiClient(apiKey: acc.apiKey, config: _config.config);
    try {
      _apiData = await client.fetchAll(logSummary: !silent, logErrors: !silent);
      final live = _apiData?.models ?? const <LiveModelInfo>[];
      if (live.isNotEmpty) {
        _proxy.setLiveModelIds(live.map((m) => m.id).toList());
        if (!silent) {
          LogStore.info('Live model list: ${live.length} models from API');
        }
      }
      if (!silent) {
        LogStore.info('Data refresh completed');
        _setStatus('Data refreshed', duration: 3);
      }
    } catch (e) {
      LogStore.error('Data refresh failed: $e');
      if (!silent) {
        _setStatus('Refresh failed', duration: 5);
      }
    } finally {
      client.dispose();
      _loadingData = false;
      _foregroundRefresh = true;
      _lastLogVersion = LogStore.version;
      if (mounted) setState(() {});
    }
  }

  void _doQuit() {
    _statusTimer?.cancel();
    _pageRefreshTimer?.cancel();
    _proxy.stop();
    LogStore.info('Bridge stopped');
    shutdownApp();
  }

  void _initOrderedModels() {
    final s = _apiData?.subscription;
    final planId = s?.planId;
    final credits = _apiData?.credits;
    final purchased = credits?.purchasedCredits ?? 0;
    final free = credits?.freeCredits ?? 0;

    final live = _apiData?.models ?? const <LiveModelInfo>[];
    final bundledIds = ModelsDb.all.map((m) => m.id).toSet();

    // Live-only models (released after this bridge version) default to
    // go-accessible, matching the CLI's behavior for unknown-category models.
    final liveOnly = live
        .where((m) => !bundledIds.contains(m.id))
        .map((m) => ModelInfo(
              id: m.id,
              displayName: m.name.isNotEmpty ? m.name : m.id,
              category: 'opensource',
              contextWindow: m.contextLength,
            ))
        .toList();

    final all = [...ModelsDb.all, ...liveOnly];

    // Sort so that models accessible on the user's plan come first, then free
    // usage before billing, then by provider, then by id. This keeps all
    // "available on Go" models grouped at the top regardless of category.
    all.sort((a, b) {
      final accA = PlanAccess.isAccessible(
        model: a,
        planId: planId,
        purchasedCredits: purchased,
        freeCredits: free,
      );
      final accB = PlanAccess.isAccessible(
        model: b,
        planId: planId,
        purchasedCredits: purchased,
        freeCredits: free,
      );
      if (accA != accB) return accA ? -1 : 1;

      final freeA = ModelsDb.isFree(a.id);
      final freeB = ModelsDb.isFree(b.id);
      if (freeA != freeB) return freeA ? -1 : 1;

      final rA = ModelsDb.providerRank(a.id);
      final rB = ModelsDb.providerRank(b.id);
      if (rA != rB) return rA - rB;

      return a.id.compareTo(b.id);
    });

    _orderedModels = all;
    _modelsInitialized = true;
  }

  void _copyEndpointUrl() {
    final port = _config.config.serverPort;
    final url = 'http://127.0.0.1:$port/v1';
    _setStatus('Copying OpenAI endpoint...');
    _copyNative(url).then((ok) {
      if (ok) {
        _setStatus('Copied OpenAI: $url', duration: 4);
        LogStore.info('Copied OpenAI endpoint URL');
      } else {
        _setStatus('Clipboard copy failed', duration: 4);
      }
    });
  }

  void _copyAnthropicUrl() {
    final port = _config.config.serverPort;
    final url = 'http://127.0.0.1:$port';
    _setStatus('Copying Anthropic endpoint...');
    _copyNative(url).then((ok) {
      if (ok) {
        _setStatus('Copied Anthropic: $url', duration: 4);
        LogStore.info('Copied Anthropic endpoint URL');
      } else {
        _setStatus('Clipboard copy failed', duration: 4);
      }
    });
  }

  void _copyModelId() {
    if (!_modelsInitialized) _initOrderedModels();
    if (_selectedModelIndex < 0 || _selectedModelIndex >= _orderedModels.length) return;
    final model = _orderedModels[_selectedModelIndex];
    _setStatus('Copying "${model.id}" to clipboard...');
    _copyNative(model.id).then((ok) {
      if (ok) {
        _setStatus('Copied: ${model.id}', duration: 3);
        LogStore.info('Copied model ID: ${model.id}');
      } else {
        _setStatus('Clipboard copy failed', duration: 4);
      }
    });
  }

  Future<bool> _copyNative(String text) async {
    if (Platform.isLinux) {
      try {
        final p = await _spawnAndPipe('wl-copy', [], text);
        if (p) return true;
      } catch (_) {}
      try {
        final p = await _spawnAndPipe('xclip', ['-selection', 'clipboard'], text);
        if (p) return true;
      } catch (_) {}
    }
    if (Platform.isWindows) {
      try {
        final p = await _spawnAndPipe('clip', [], text);
        if (p) return true;
      } catch (_) {}
    }
    if (Platform.isMacOS) {
      try {
        final p = await _spawnAndPipe('pbcopy', [], text);
        if (p) return true;
      } catch (_) {}
    }
    try {
      return ClipboardManager.copy(text);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _spawnAndPipe(String cmd, List<String> args, String input) async {
    try {
      final proc = await Process.start(cmd, args);
      proc.stdin.write(input);
      await proc.stdin.close();
      await proc.exitCode;
      return true;
    } catch (_) {
      return false;
    }
  }

  void _doConfirmClear() {
    final hasOld = LogStore.countBeforeToday() > 0 && _status.contains('before today');
    if (hasOld) {
      LogStore.clearBeforeToday();
      _setStatus('Old log entries cleared', duration: 3);
    } else {
      LogStore.clear();
      _setStatus('All logs cleared', duration: 3);
    }
    _confirmClearLog = false;
    LogStore.info('Log cleared by user');
    setState(() {});
  }

  void _cancelConfirmClear() {
    _confirmClearLog = false;
    _setStatus('');
    setState(() {});
  }

  void _showPortConfig() {
    _portCtrl.text = '${_config.config.serverPort}';
    _portScanDone = false;
    _portStatus.clear();
    _panel = _Panel.portConfig;
    _pageRefreshTimer?.cancel();
    _scanPorts();
    _setStatus('Enter port or select available. Empty = reset to default.');
    setState(() {});
  }

  Future<void> _scanPorts() async {
    _portScanDone = false;
    _portStatus.clear();
    const candidates = [17077, 17078, 17076, 19099, 19100, 18080, 16000, 15000];
    for (final port in candidates) {
      if (port == _config.config.serverPort) {
        _portStatus[port] = true;
        continue;
      }
      try {
        final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
        await s.close();
        _portStatus[port] = true;
      } catch (_) {
        _portStatus[port] = false;
      }
    }
    _portScanDone = true;
    if (mounted) setState(() {});
  }

  void _doSetPort() {
    final raw = _portCtrl.text.trim();
    if (raw.isEmpty) {
      _config.config.serverPort = AppConfig.defaultPort;
      _config.save();
      _setStatus('Port reset to default ${AppConfig.defaultPort}. Restart required.', duration: 5);
      _panel = _Panel.main;
      setState(() {});
      return;
    }
    final n = int.tryParse(raw);
    if (n == null || n < 1024 || n > 65535) {
      _setStatus('Invalid: enter port (1024-65535) or empty for default', duration: 4);
      return;
    }
    if (n == _config.config.serverPort) {
      _setStatus('Already using port $n', duration: 3);
      _panel = _Panel.main;
      setState(() {});
      return;
    }
    try {
      final s = ServerSocket.bind(InternetAddress.loopbackIPv4, n);
      s.then((server) {
        server.close();
        _config.config.serverPort = n;
        _config.save();
        _setStatus('Port set to $n. Restart required.', duration: 5);
        _panel = _Panel.main;
        _startActivePageRefresh();
        LogStore.info('Port changed to $n (restart required)');
        if (mounted) setState(() {});
      }).catchError((_) {
        _setStatus('Port $n is already in use. Try another.', duration: 4);
      });
    } catch (_) {
      _setStatus('Cannot bind port $n.', duration: 4);
    }
  }

  Component _buildHeader() {
    final whoami = _apiData?.whoami;
    final sub = _apiData?.subscription;
    final displayName = whoami?.name ?? _account.account?.userName ?? 'Not logged in';
    final email = whoami?.email ?? '';
    final planName = sub != null ? _planDisplayName(sub.planId) : '';
    final isRunning = _proxy.isRunning;
    final port = _proxy.isRunning ? _proxy.currentPort : _config.config.serverPort;

    return Container(
      padding: const EdgeInsets.all(1),
      decoration: const BoxDecoration(
        border: BoxBorder(bottom: BorderSide(color: Colors.grey)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('CommandCode Bridge',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('  OpenAI + Anthropic',
                  style: TextStyle(color: Colors.green)),
              Text(' | ', style: TextStyle(color: Colors.grey)),
              Text(displayName, style: const TextStyle(color: Colors.cyan)),
              if (email.isNotEmpty)
                Text(' ($email)', style: TextStyle(color: Colors.grey)),
              const Spacer(),
              if (planName.isNotEmpty)
                Text('  ${planName} Plan',
                    style: TextStyle(
                        color: planName.contains('Go') ? Colors.yellow : Colors.cyan,
                        fontWeight: FontWeight.bold)),
              Text(isRunning ? ' RUNNING' : ' STOPPED',
                  style: TextStyle(
                    color: isRunning ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                  )),
            ],
          ),
          Row(
            children: [
              Text('\u25b8 OpenAI:  ',
                  style: TextStyle(color: Colors.grey)),
              Text('http://127.0.0.1:$port/v1',
                  style: const TextStyle(color: Colors.green)),
              Text(' [o] copy', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
            ],
          ),
          Row(
            children: [
              Text('\u25b8 Anthropic: ',
                  style: TextStyle(color: Colors.grey)),
              Text('http://127.0.0.1:$port',
                  style: const TextStyle(color: Colors.cyan)),
              Text(' [a] copy', style: TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('Last used: ${_proxy.currentModel}',
                  style: TextStyle(color: Colors.grey)),
              Text(' | ${_refreshLabel()}', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }

  Component _buildBody() {
    if (_panel == _Panel.help) return _helpPanel();
    if (_panel == _Panel.quit) return _quitPanel();
    if (_panel == _Panel.login) return _loginPanel();
    if (_panel == _Panel.importKey) return _importKeyPanel();
    if (_panel == _Panel.portConfig) return _portConfigPanel();

    final content = _buildContent();

    if (_logFullscreen && _showLog) {
      return Padding(
        padding: const EdgeInsets.all(1),
        child: _logPanel(fullscreen: true),
      );
    }
    if (!_showLog) {
      return Padding(
        padding: const EdgeInsets.all(1),
        child: content,
      );
    }

    return Row(
      children: [
        Expanded(flex: 1, child: Padding(
          padding: const EdgeInsets.all(1),
          child: content,
        )),
        const SizedBox(width: 1),
        Expanded(
          flex: 1,
          child: Container(
            padding: const EdgeInsets.all(1),
            decoration: const BoxDecoration(
              border: BoxBorder(left: BorderSide(color: Colors.grey)),
            ),
            child: _logPanel(fullscreen: false),
          ),
        ),
      ],
    );
  }

  Component _buildContent() {
    if (_loadingData && _foregroundRefresh) {
      return Center(
        child: Text('Loading...', style: TextStyle(color: Colors.cyan)),
      );
    }

    final rows = <Component>[];
    if (_apiData == null) {
      rows.add(Padding(
        padding: const EdgeInsets.all(2),
        child: Text('Press [r] to load data', style: TextStyle(color: Colors.grey)),
      ));
    } else {
      rows.addAll(_buildInfoRows());

      if (_infoPage == _InfoPage.models) {
        rows.addAll(_buildModelRows());
      }
    }

    final total = rows.length;
    const maxVisible = 20;
    if (total <= maxVisible) {
      return ListView(controller: _infoScrollCtrl, children: rows);
    }
    return Scrollbar(
      controller: _infoScrollCtrl,
      thumbVisibility: true,
      thickness: 1,
      thumbColor: Colors.grey,
      child: ListView(controller: _infoScrollCtrl, children: rows),
    );
  }

  List<Component> _buildInfoRows() {
    final w = _apiData!.whoami;
    final s = _apiData!.subscription;
    final c = _apiData!.credits;
    final u = _apiData!.usage;

    final rows = <Component>[];
    void add(String text, [Color? color]) {
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 0),
        child: Text(text, style: color != null ? TextStyle(color: color) : null),
      ));
    }

    Component _bar(double value, Color color, {double height = 1, String? label}) {
      return Row(children: [
        SizedBox(
          width: 40,
          height: height,
          child: ProgressBar(
            value: value,
            valueColor: color,
            backgroundColor: Colors.grey,
            fillCharacter: '█',
            emptyCharacter: '░',
          ),
        ),
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(left: 1),
            child: Text(label, style: TextStyle(color: color)),
          ),
        const SizedBox(width: 1),
      ]);
    }

    switch (_infoPage) {
      case _InfoPage.account:
        add('Account Information', Colors.cyan);
        add('');
        add('Name:     ${w?.name ?? 'N/A'}');
        add('Email:    ${w?.email ?? 'N/A'}');
        add('Username: ${w?.userName ?? 'N/A'}');
        add('User ID:  ${w?.id ?? 'N/A'}');
        add('Key Name: ${_account.account?.keyName ?? 'N/A'}');
        add('Auth at:  ${_fmtDate(_account.account?.authenticatedAt)}');
        add('');
        add('Auth File: ~/.commandcode/auth.json');
        break;

      case _InfoPage.plan:
        add('Plan & Billing', Colors.cyan);
        add('');
        if (s != null) {
          rows.add(Row(children: [
            Text('Plan:  ', style: TextStyle(color: Colors.grey)),
            Text('${_planDisplayName(s.planId)}  ', style: TextStyle(color: s.planId.contains('go') ? Colors.yellow : Colors.cyan, fontWeight: FontWeight.bold)),
            Text('(${s.planId})', style: TextStyle(color: Colors.grey)),
            SizedBox(width: 1),
            Text(s.status == 'active' ? '\u25cf Active' : '\u25cf ${s.status}',
                style: TextStyle(color: s.status == 'active' ? Colors.green : Colors.red)),
          ]));
          add('');

          // Period progress bar
          final periodStart = DateTime.tryParse(s.currentPeriodStart);
          final periodEnd = DateTime.tryParse(s.currentPeriodEnd);
          if (periodStart != null && periodEnd != null) {
            final totalDays = periodEnd.difference(periodStart).inDays;
            final elapsedDays = DateTime.now().difference(periodStart).inDays;
            final periodPct = (elapsedDays / totalDays).clamp(0.0, 1.0);
            add('Billing Period:', Colors.cyan);
            rows.add(Padding(
              padding: EdgeInsets.symmetric(vertical: 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('  ${_fmtDate(periodStart)}  to  ${_fmtDate(periodEnd)}  ($totalDays days)', style: TextStyle(color: Colors.grey)),
                SizedBox(height: 1),
                _bar(periodPct, Colors.blue, label: '${elapsedDays}d / ${totalDays}d elapsed'),
                SizedBox(height: 1),
                Text('  Renewal: ${s.cancelAtPeriodEnd ? "Cancels at period end" : "Auto-renews"}',
                    style: TextStyle(color: s.cancelAtPeriodEnd ? Colors.yellow : Colors.green)),
              ]),
            ));
            add('');
          }
        } else {
          add('No subscription data');
        }

        add('Credits', Colors.cyan);
        add('');
        if (c != null) {
          final total = c.monthlyCredits + c.purchasedCredits + c.freeCredits;
          final totalUsed = c.fiveHour.used; // approximate
          final usagePct = total > 0 ? (totalUsed / total).clamp(0.0, 1.0) : 0.0;
          final creditColor = usagePct > 0.8 ? Colors.red : (usagePct > 0.5 ? Colors.yellow : Colors.green);

          // Overall credit usage bar
          rows.add(Padding(
            padding: EdgeInsets.symmetric(vertical: 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('  Total: \$${total.toStringAsFixed(2)}  (Used: \$${totalUsed.toStringAsFixed(4)})',
                  style: TextStyle(color: Colors.grey)),
              SizedBox(height: 1),
              _bar(usagePct, creditColor, label: '${(usagePct * 100).toInt()}% used'),
            ]),
          ));
          add('');

          // Individual credit types
          rows.add(Row(children: [
            Text('  Monthly ', style: TextStyle(color: Colors.grey)),
            Text('\$${c.monthlyCredits.toStringAsFixed(2)}', style: TextStyle(color: Colors.cyan)),
          ]));
          rows.add(Row(children: [
            Text('  Purchased ', style: TextStyle(color: Colors.grey)),
            Text('\$${c.purchasedCredits.toStringAsFixed(2)}', style: TextStyle(color: Colors.green)),
          ]));
          rows.add(Row(children: [
            Text('  Free ', style: TextStyle(color: Colors.grey)),
            Text('\$${c.freeCredits.toStringAsFixed(2)}', style: TextStyle(color: Colors.cyan)),
          ]));
          add('');
          rows.add(Row(children: [
            Text('  Threshold: \$${c.creditThreshold.toStringAsFixed(2)}', style: TextStyle(color: Colors.grey)),
            SizedBox(width: 1),
            Text(c.belowThreshold ? '  BELOW THRESHOLD!' : '',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ]));
        } else {
          add('No credits data');
        }
        break;

      case _InfoPage.usage:
        if (u == null) { add('No usage data'); break; }
        add('Usage Summary', Colors.cyan);
        add('');

        // Request counts
        rows.add(Row(children: [
          Text('  Requests: ', style: TextStyle(color: Colors.grey)),
          Text('${u.completedCount} completed', style: TextStyle(color: Colors.green)),
          Text(' / ${u.failedCount} failed', style: TextStyle(color: u.failedCount > 0 ? Colors.red : Colors.grey)),
          Text(' (${u.totalCount} total)', style: TextStyle(color: Colors.grey)),
        ]));
        add('');

        // Success rate bar
        final successRate = u.successRate / 100.0;
        final rateColor = successRate > 0.99 ? Colors.green : (successRate > 0.9 ? Colors.yellow : Colors.red);
        rows.add(Padding(
          padding: EdgeInsets.symmetric(vertical: 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('  Success Rate', style: TextStyle(color: Colors.cyan)),
            SizedBox(height: 1),
            _bar(successRate, rateColor, label: '${u.successRate.toStringAsFixed(1)}%'),
          ]),
        ));
        add('');

        // Token usage bars
        add('Token Usage', Colors.cyan);
        add('');
        final totalTokens = u.totalTokensIn + u.totalTokensOut;
        if (totalTokens > 0) {
          final inRatio = u.totalTokensIn / totalTokens;
          final outRatio = u.totalTokensOut / totalTokens;
          rows.add(Padding(
            padding: EdgeInsets.symmetric(vertical: 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('  Input:  ${_fmtNum(u.totalTokensIn)}', style: TextStyle(color: Colors.blue)),
              SizedBox(height: 1),
              _bar(inRatio, Colors.blue, height: 1),
              SizedBox(height: 1),
              Text('  Output: ${_fmtNum(u.totalTokensOut)}', style: TextStyle(color: Colors.green)),
              SizedBox(height: 1),
              _bar(outRatio, Colors.green, height: 1),
              Text('  Total:  ${_fmtNum(u.totalTokens)}', style: TextStyle(color: Colors.grey)),
            ]),
          ));
        }
        add('');

        // Cost section
        add('Cost', Colors.cyan);
        add('');
        rows.add(Row(children: [
          Text('  Total: \$${u.totalCost.toStringAsFixed(4)}', style: TextStyle(color: Colors.yellow)),
          SizedBox(width: 2),
          Text('Avg: \$${u.averageCost.toStringAsFixed(6)}/req', style: TextStyle(color: Colors.grey)),
        ]));
        add('');

        // Credits breakdown bars
        add('Credits Breakdown', Colors.cyan);
        add('');
        final totalCred = u.totalMonthlyCredits + u.totalFreeCredits + u.totalPurchasedCredits;
        if (totalCred > 0) {
          final monthlyPct = u.totalMonthlyCredits / totalCred;
          final freePct = u.totalFreeCredits / totalCred;
          rows.add(Padding(
            padding: EdgeInsets.symmetric(vertical: 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('  Monthly: \$${u.totalMonthlyCredits.toStringAsFixed(4)}', style: TextStyle(color: Colors.cyan)),
              SizedBox(height: 1),
              _bar(monthlyPct, Colors.cyan, height: 1),
              SizedBox(height: 1),
              Text('  Free:    \$${u.totalFreeCredits.toStringAsFixed(4)}', style: TextStyle(color: Colors.green)),
              SizedBox(height: 1),
              _bar(freePct, Colors.green, height: 1),
              SizedBox(height: 1),
              Text('  Purchased: \$${u.totalPurchasedCredits.toStringAsFixed(4)}', style: TextStyle(color: Colors.yellow)),
            ]),
          ));
        }
        break;

      case _InfoPage.limits:
        if (c == null) { add('No rate limit data'); break; }
        add('Rate Limits', Colors.cyan);
        add('');

        // 5-Hour Window
        add('5-Hour Window', Colors.cyan);
        add('');
        final fiveCap = c.fiveHour.cap;
        if (fiveCap > 0) {
          final fivePct = c.fiveHour.used / fiveCap;
          final fiveColor = c.fiveHour.exceeded ? Colors.red : (fivePct > 0.8 ? Colors.yellow : Colors.green);
          rows.add(Padding(
            padding: EdgeInsets.symmetric(vertical: 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _bar(fivePct.clamp(0.0, 1.0), fiveColor,
                  label: '\$${c.fiveHour.used.toStringAsFixed(4)} / \$${fiveCap.toStringAsFixed(2)}'),
              SizedBox(height: 1),
              Row(children: [
                Text('  Remaining: \$${c.fiveHour.remaining.toStringAsFixed(4)}',
                    style: TextStyle(color: c.fiveHour.remaining < 0.01 ? Colors.red : Colors.green)),
                SizedBox(width: 2),
                if (c.fiveHour.exceeded)
                  Text('EXCEEDED', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ]),
              SizedBox(height: 1),
              Text('  Resets at: ${_fmtDate(c.fiveHour.resetTime)}  ${_relativeTime(c.fiveHour.resetTime)}',
                  style: TextStyle(color: Colors.grey)),
            ]),
          ));
        } else {
          add('  No 5-hour limit', Colors.grey);
        }
        add('');

        // Weekly Window
        add('Weekly Window', Colors.cyan);
        add('');
        final weekCap = c.weekly.cap;
        if (weekCap > 0) {
          final weekPct = c.weekly.used / weekCap;
          final weekColor = c.weekly.exceeded ? Colors.red : (weekPct > 0.8 ? Colors.yellow : Colors.green);
          rows.add(Padding(
            padding: EdgeInsets.symmetric(vertical: 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _bar(weekPct.clamp(0.0, 1.0), weekColor,
                  label: '\$${c.weekly.used.toStringAsFixed(4)} / \$${weekCap.toStringAsFixed(2)}'),
              SizedBox(height: 1),
              Row(children: [
                Text('  Remaining: \$${c.weekly.remaining.toStringAsFixed(4)}',
                    style: TextStyle(color: c.weekly.remaining < 0.01 ? Colors.red : Colors.green)),
                SizedBox(width: 2),
                if (c.weekly.exceeded)
                  Text('EXCEEDED', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ]),
              SizedBox(height: 1),
              Text('  Resets at: ${_fmtDate(c.weekly.resetTime)}  ${_relativeTime(c.weekly.resetTime)}',
                  style: TextStyle(color: Colors.grey)),
            ]),
          ));
        } else {
          add('  No weekly limit', Colors.grey);
        }
        add('');

        // Limited status
        rows.add(Row(children: [
          Text('  Limited: ', style: TextStyle(color: Colors.grey)),
          Text(c.fiveHour.cap > 0 || c.weekly.cap > 0 ? 'Yes' : 'No',
              style: TextStyle(color: c.fiveHour.cap > 0 ? Colors.yellow : Colors.green)),
        ]));
        break;

      case _InfoPage.models:
        add('Models Reference', Colors.cyan);
        if (s != null) {
          final isGo = ModelsDb.isGoPlan(s.planId);
          if (isGo) {
            add('Your Go plan: Open Source models first (highlighted), Premium models dimmed (not accessible)', Colors.yellow);
          } else {
            add('Your ${_planDisplayName(s.planId)} plan: all models accessible', Colors.green);
          }
        }
        add('Use [up/down] to scroll, [Enter] to copy model ID. ${ModelsDb.all.length} models total.');
        add('');
        break;

      case _InfoPage.proxy:
        final uptime = DateTime.now().difference(_startTime);
        add('Proxy Configuration', Colors.cyan);
        add('');
        add('Status:      ${_proxy.isRunning ? "Running" : "Stopped"}');
        add('Last Model:  ${_proxy.currentModel}');
        add('Port:        ${_config.config.serverPort}');
        add('Listen:      http://127.0.0.1:${_config.config.serverPort}');
        add('API URL:     ${_config.config.apiBaseUrl}');
        add('CLI Version: ${_config.config.cliVersion}');
        add('Uptime:      ${uptime.inHours}h ${uptime.inMinutes.remainder(60)}m ${uptime.inSeconds.remainder(60)}s');
        add('Log Path:    ~/.config/commandcode-bridge/');
        add('');
        add('Endpoints', Colors.cyan);
        add('');
        add('OpenAI:');
        add('  http://127.0.0.1:${_config.config.serverPort}/v1');
        add('  POST /v1/chat/completions   Chat completions');
        add('  GET  /v1/models             List models');
        add('  GET  /v1/health             Health check');
        add('  GET  /v1/token              Access token');
        add('  GET  /v1/info               Bridge info');
        add('');
        add('Anthropic:');
        add('  http://127.0.0.1:${_config.config.serverPort}');
        add('  POST /v1/messages           Messages API');
        add('  POST /messages              Messages API (alt)');
        add('');
        add('API Key: any value works (bridge uses your saved auth)');
        break;

      case _InfoPage.cost:
        _initCostAgents();
        add('Cost Sync - Command Code model pricing', Colors.cyan);
        add('');
        add('Sync pricing to your CLI agent. White = will be synced. Grey = not in your config.');
        add('');
        add('[c] Sync costs to selected agent', Colors.green);
        add('');

        add('Detected CLI Agents:', Colors.cyan);
        add('');
        if (_costAgents.isEmpty) {
          add('  No CLI agents detected.', Colors.yellow);
        }
        for (var i = 0; i < _costAgents.length; i++) {
          final agent = _costAgents[i];
          final prefix = i == _costSelectedAgent ? '\u25b8 ' : '  ';
          final status = agent.detected ? 'found' : 'not found';
          final statusColor = agent.detected ? Colors.green : Colors.grey;
          rows.add(Row(children: [
            Text('$prefix${agent.displayName.padRight(10)} ', style: TextStyle(
              color: i == _costSelectedAgent ? Colors.cyan : null,
              fontWeight: i == _costSelectedAgent ? FontWeight.bold : null,
            )),
            Text(status, style: TextStyle(color: statusColor)),
          ]));
          if (agent.detected) {
            rows.add(Text('    ${agent.configPath}', style: TextStyle(color: Colors.grey)));
          }
        }
        add('');

        // Fetch live model IDs from bridge /v1/models once per page visit
        _ensureLiveModelIds();

        // Get user's bridge models for the selected agent
        Set<String> userBridgeModels = {};
        List<BridgeProviderInfo> bridgeProviders = const [];
        final selectedAgent = _costSelectedAgent < _costAgents.length
            ? _costAgents[_costSelectedAgent]
            : null;
        if (selectedAgent != null && selectedAgent.detected) {
          if (selectedAgent.type == CliAgentType.opencode) {
            final info = CostSyncService.getOpenCodeBridgeModels();
            userBridgeModels = info.models.toSet();
            bridgeProviders = info.providers;
          } else {
            userBridgeModels = CostSyncService.getUserModels(selectedAgent.type).toSet();
          }
        }

        if (bridgeProviders.isNotEmpty) {
          add('Provider:', Colors.grey);
          for (final prov in bridgeProviders) {
            add('  - ${prov.name} [${prov.host}:${prov.port}]', Colors.grey);
          }
          add('');
        }

        if (!_costLiveFetched) {
          add('Fetching live model list from bridge...', Colors.yellow);
          add('');
        }

        // Filter PricingDb against live API: never display a price for a
        // model that the bridge cannot actually call.
        final liveIds = _costLiveModelIds;
        final visibleModels = liveIds.isEmpty
            ? <ModelPricing>[] // API not reachable yet; show nothing
            : PricingDb.all.where((p) => liveIds.contains(p.modelId)).toList();

        final unknownIds = userBridgeModels
            .where((id) => PricingDb.byId(id) == null)
            .toList();
        if (unknownIds.isNotEmpty) {
          add('In your config but no pricing data: ${unknownIds.join(", ")}', Colors.yellow);
          add('');
        }

        if (visibleModels.isEmpty && _costLiveFetched) {
          add('No priced models available. Bridge /v1/models did not return any known models.', Colors.red);
          add('');
        } else {
          // Show ALL valid pricing models
          add('Command Code Models & Pricing (per 1M tokens):', Colors.cyan);
          add('');

          // Group by plan access first: what the user's plan can use vs not.
          final sub = _apiData?.subscription;
          final planId = sub?.planId;
          final credits = _apiData?.credits;
          final purchased = credits?.purchasedCredits ?? 0;
          final free = credits?.freeCredits ?? 0;

          final goModels = <ModelPricing>[];
          final proModels = <ModelPricing>[];
          for (final p in visibleModels) {
            final info = ModelsDb.byId(p.modelId);
            final acc = info == null
                ? true
                : PlanAccess.isAccessible(
                    model: info,
                    planId: planId,
                    purchasedCredits: purchased,
                    freeCredits: free,
                  );
            (acc ? goModels : proModels).add(p);
          }
          // Live models known to the API but with no local pricing data yet.
          final unpriced = liveIds
              .where((id) => PricingDb.byId(id) == null)
              .where((id) => !PricingDb.knownMissingFromApi.contains(id))
              .toList();

          void _addPricingSection(String label, List<ModelPricing> models) {
            if (models.isEmpty) return;
            add(label, Colors.cyan);
            add('');
            for (final p in models) {
              final inConfig = userBridgeModels.contains(p.modelId);
              final willSync = inConfig && selectedAgent != null && selectedAgent.detected;
              final color = willSync ? null : Colors.grey;
              final suffix = willSync ? ' (will be implemented)' : '';
              final price = p.inputPer1M == 0 && p.outputPer1M == 0
                  ? 'FREE'
                  : '\$${p.inputPer1M}/\$${p.outputPer1M}';
              add('  ${p.modelId.padRight(40)} ${price.padRight(16)}$suffix', color);
            }
            add('');
          }

          final isGo = planId != null && ModelsDb.isGoPlan(planId);
          if (isGo) {
            _addPricingSection('Available on Go', goModels);
            _addPricingSection('Requires Pro / Max', proModels);
          } else {
            _addPricingSection('Available on your plan', goModels);
            _addPricingSection('Blocked on your plan', proModels);
          }

          if (unpriced.isNotEmpty) {
            add('Available but no pricing data (not yet priced):', Colors.yellow);
            add('');
            for (final id in unpriced) {
              add('  ${id.padRight(40)} no pricing data', Colors.yellow);
            }
            add('');
          }
        }

        add('');
        add('[c] Sync costs  [up/down] Select agent', Colors.grey);
        break;
    }

    return rows;
  }

  List<Component> _buildModelRows() {
    final rows = <Component>[];
    _initOrderedModels();
    final s = _apiData?.subscription;
    final planId = s?.planId;
    final isGo = s != null && ModelsDb.isGoPlan(planId);
    final credits = _apiData?.credits;
    final purchased = credits?.purchasedCredits ?? 0;
    final free = credits?.freeCredits ?? 0;

    String? section; // 'accessible' | 'blocked'
    String? usage; // 'free' | 'billing'
    String? provider;

    for (var i = 0; i < _orderedModels.length; i++) {
      final m = _orderedModels[i];
      final accessible = PlanAccess.isAccessible(
        model: m,
        planId: planId,
        purchasedCredits: purchased,
        freeCredits: free,
      );
      final curSection = accessible ? 'accessible' : 'blocked';
      final isFreeModel = ModelsDb.isFree(m.id);
      final curUsage = isFreeModel ? 'free' : 'billing';
      final curProvider = ModelsDb.providerOf(m.id);

      if (curSection != section) {
        section = curSection;
        usage = null;
        provider = null;
        rows.add(const SizedBox(height: 1));
        if (curSection == 'accessible') {
          rows.add(_modelHeader(
            isGo ? 'Models available on Go' : 'Models available on ${_planDisplayName(planId ?? '')}',
            Colors.green,
          ));
        } else {
          rows.add(_modelHeader(
            isGo
                ? 'Premium Models (Go cannot access)'
                : 'Premium Models (blocked on ${_planDisplayName(planId ?? '')})',
            Colors.grey,
          ));
        }
      }

      if (curUsage != usage) {
        usage = curUsage;
        provider = null;
        rows.add(const SizedBox(height: 1));
        if (curUsage == 'free') {
          rows.add(Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text('Free usage', style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold)),
          ));
        } else {
          rows.add(Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text('Billing', style: TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold)),
          ));
        }
      }

      if (curProvider != provider) {
        provider = curProvider;
        rows.add(Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(curProvider, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
        ));
      }

      final prefix = i == _selectedModelIndex ? '\u25b8 ' : '  ';
      final ctx = _fmtCtx(m.contextWindow);
      final reas = m.reasoningEfforts.isNotEmpty
          ? ' [reasoning: ${m.reasoningEfforts.join(",")}]'
          : '';
      final label = accessible ? '' : ' [Not on Go]';
      rows.add(Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Text('$prefix${m.id}  (${ctx}ctx$reas)$label',
            style: TextStyle(
              color: i == _selectedModelIndex
                  ? Colors.cyan
                  : accessible
                      ? null
                      : Colors.grey,
            )),
      ));
    }
    return rows;
  }

  Padding _modelHeader(String label, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 0),
        child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      );

  String _planDisplayName(String planId) {
    if (planId.startsWith('individual-')) {
      return planId.replaceFirst('individual-', '')
          .split('-')
          .map((e) => e[0].toUpperCase() + e.substring(1))
          .join(' ');
    }
    return planId;
  }

  Component _logPanel({required bool fullscreen}) {
    final entries = LogStore.latestFirst.take(200).toList();
    _lastLogVersion = LogStore.version;
    final listChildren = <Component>[];
    String? lastDate;
    final dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

    for (final entry in entries) {
      final ds = '${entry.timestamp.year}-${entry.timestamp.month.toString().padLeft(2, '0')}-${entry.timestamp.day.toString().padLeft(2, '0')}';
      if (ds != lastDate) {
        lastDate = ds;
        final dn = dayNames[entry.timestamp.weekday - 1];
        listChildren.add(Text('${'─' * 15} $dn ${'─' * 15}',
            style: TextStyle(color: Colors.grey)));
      }
      final t = '${entry.timestamp.hour.toString().padLeft(2, '0')}:${entry.timestamp.minute.toString().padLeft(2, '0')}:${entry.timestamp.second.toString().padLeft(2, '0')}';
      listChildren.add(Row(
        children: [
          Text('[$t]', style: TextStyle(color: Colors.grey)),
          Text(' [${_logLevel(entry.level)}] ',
              style: TextStyle(color: _logColor(entry.level))),
          Expanded(child: Text(entry.message)),
        ],
      ));
    }

    return Column(
      children: [
            Row(
              children: [
                Text(fullscreen ? ' LOG (fullscreen)' : ' LOG',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.cyan)),
                const Spacer(),
                if (!fullscreen)
                  Text('[f]ull ', style: TextStyle(color: Colors.grey)),
              ],
            ),
        Container(height: 1, color: Colors.grey),
        Expanded(
          child: Scrollbar(
            controller: _logScrollCtrl,
            thumbVisibility: true,
            thickness: 1,
            thumbColor: Colors.grey,
            child: ListView(controller: _logScrollCtrl, children: listChildren),
          ),
        ),
      ],
    );
  }

  String _logLevel(LogLevel l) {
    switch (l) {
      case LogLevel.error: return 'ERR';
      case LogLevel.warning: return 'WRN';
      case LogLevel.success: return 'OK';
      case LogLevel.info: return 'INF';
      case LogLevel.debug: return 'DBG';
    }
  }

  Color _logColor(LogLevel l) {
    switch (l) {
      case LogLevel.error: return Colors.red;
      case LogLevel.warning: return Colors.yellow;
      case LogLevel.success: return Colors.green;
      case LogLevel.info: return Colors.cyan;
      case LogLevel.debug: return Colors.grey;
    }
  }

  Component _helpPanel() {
    final lines = <Component>[];
    void add(String text, [Color? color]) {
      lines.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 0),
        child: Text(text, style: color != null ? TextStyle(color: color) : null),
      ));
    }

    add('Help', Colors.cyan);
    add('');
    add('Pages:', Colors.cyan);
    add('');
    add('  [1] Account        - User info and auth details');
    add('  [2] Plan & Billing - Subscription and credits');
    add('  [3] Usage          - API usage statistics');
    add('  [4] Rate Limits    - 5-hour and weekly caps');
    add('  [5] Models         - Available models with codenames');
    add('  [6] Proxy Config   - Bridge configuration');
    add('  [7] Cost Sync      - Sync model pricing to CLI agents');
    add('');
    add('Actions:', Colors.cyan);
    add('');
    add('  [r]       Refresh all API data from endpoints');
    add('  [up/down] Scroll content / navigate models');
    add('  [Enter]   Copy selected model ID to clipboard');
    add('  [PgUp/PgDn] Scroll faster');
    add('  [c]       Sync costs (on Cost Sync page)');
    add('');
    add('Log Controls:', Colors.cyan);
    add('');
    add('  [Ctrl+L]  Toggle log sidebar');
    add('  [f]       Toggle log fullscreen / sidebar');
    add('  [C]       Clear all log entries');
    add('  [Shift+O] Clear entries before today');
    add('');
    add('Other:', Colors.cyan);
    add('');
    add('  [o]       Copy OpenAI endpoint URL (http://.../v1) to clipboard');
    add('  [a]       Copy Anthropic endpoint URL (http://... base) to clipboard');
    add('  [p]       Configure proxy port');
    add('  [l]       Login panel (if not authenticated)');
    add('  [h]       Show this help');
    add('  [q]       Quit');
    add('');
    add('Endpoints:', Colors.cyan);
    add('');
    add('  OpenAI:   http://127.0.0.1:${_config.config.serverPort}/v1');
    add('  Anthropic: http://127.0.0.1:${_config.config.serverPort}');
    add('');
    add('Links:', Colors.cyan);
    add('');
    add('  Docs:  https://commandcode.ai/docs');
    add('  Config: ~/.config/commandcode-bridge/');

    final total = lines.length;
    const maxVisible = 18;
    if (total <= maxVisible) {
      return Padding(
        padding: const EdgeInsets.all(2),
        child: ListView(controller: _infoScrollCtrl, children: lines),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Scrollbar(
        controller: _infoScrollCtrl,
        thumbVisibility: true,
        thickness: 1,
        thumbColor: Colors.grey,
        child: ListView(controller: _infoScrollCtrl, children: lines),
      ),
    );
  }

  Component _quitPanel() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          border: BoxBorder.all(color: Colors.yellow),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Quit CommandCode Bridge?',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.yellow)),
            const SizedBox(height: 1),
            Text(
                'Proxy will stop at http://127.0.0.1:${_config.config.serverPort}'),
            const SizedBox(height: 1),
            const Text('[y] Yes  [n] No'),
          ],
        ),
      ),
    );
  }

  void _startLogin() {
    _panel = _Panel.login;
    _pageRefreshTimer?.cancel();
    _setStatus('Opening auth URL...');
    setState(() {});
    // In a real implementation, this would start the OAuth callback server
    // For now, guide user to run cmd login or paste API key
  }

  Component _loginPanel() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          border: BoxBorder.all(color: Colors.cyan),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Login to Command Code',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.cyan)),
            const SizedBox(height: 1),
            Text('Option 1: Run in terminal:', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 1),
            const Text('  cmd login', style: TextStyle(color: Colors.green)),
            const SizedBox(height: 1),
            Text('Option 2: Enter API key manually',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 1),
            const Text('  Visit https://commandcode.ai/studio/auth/cli'),
            const SizedBox(height: 1),
            const Text('  Copy the API key and press [i] to import'),
            const SizedBox(height: 1),
            Text('Option 3: Login via browser (auto-detect)',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 1),
            const Text('  The bridge will detect ~/.commandcode/auth.json'),
            const SizedBox(height: 1),
            Text('After login, press [r] to refresh data',
                style: TextStyle(color: Colors.cyan)),
            const SizedBox(height: 2),
            const Text('[i] Import API key  [Esc] back'),
          ],
        ),
      ),
    );
  }

  Component _importKeyPanel() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          border: BoxBorder.all(color: Colors.yellow),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Import API Key',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.yellow)),
            const SizedBox(height: 1),
            const Text('Paste your Command Code API key below:'),
            const SizedBox(height: 1),
            const Text('  Format: user_xxxxxxxxxxxxxxxxxxxxxx'),
            const SizedBox(height: 1),
            const Text('(This feature requires interactive text input)'),
            const SizedBox(height: 2),
            const Text('[Esc] cancel'),
          ],
        ),
      ),
    );
  }

  Component _portConfigPanel() {
    final availCount = _portStatus.values.where((v) => v).length;
    return Center(
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          border: BoxBorder.all(color: Colors.cyan),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Server Port',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.cyan)),
            const SizedBox(height: 1),
            const Text('Port for the OpenAI-compatible proxy endpoint.',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 1),
            Row(
              children: [
                Text('Port:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 1),
                SizedBox(
                  width: 7,
                  child: TextField(
                    controller: _portCtrl,
                    focused: true,
                    placeholder: '${AppConfig.defaultPort}',
                    onSubmitted: (_) => _doSetPort(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 1),
            Text('Available ports (scanned):',
                style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            Text(
              _portScanDone
                  ? _portStatus.entries
                      .where((e) => e.value)
                      .map((e) => '${e.key}')
                      .take(5)
                      .join(', ')
                  : 'scanning...',
              style: TextStyle(color: Colors.green),
            ),
            if (!_portScanDone)
              const Text('Scanning ports...',
                  style: TextStyle(color: Colors.yellow)),
            if (_portScanDone && availCount == 0)
              const Text('No recommended ports available',
                  style: TextStyle(color: Colors.red)),
            const SizedBox(height: 1),
            Text('Empty = reset to default (${AppConfig.defaultPort}).',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 1),
            const Text('Restart required for port change.',
                style: TextStyle(color: Colors.yellow)),
            const SizedBox(height: 1),
            const Text('[Enter] confirm  [Esc] cancel'),
          ],
        ),
      ),
    );
  }

  void _initCostAgents() {
    if (_costAgents.isNotEmpty) return;
    _costAgents = CostSyncService.detectAgents();
    // Select first detected agent by default
    final firstDetected = _costAgents.indexWhere((a) => a.detected);
    if (firstDetected >= 0) _costSelectedAgent = firstDetected;
  }

  void _ensureLiveModelIds() {
    if (_costLiveFetched) return;
    _costLiveFetched = true;
    final port = _proxy.isRunning ? _proxy.currentPort : _config.config.serverPort;
    Future.microtask(() async {
      final ids = await CostSyncService.fetchLiveModelIds(port: port);
      if (ids == null) {
        LogStore.warning('Cost sync: could not fetch /v1/models from bridge on port $port');
        return;
      }
      _costLiveModelIds = ids;
      LogStore.info('Cost sync: fetched ${ids.length} live model IDs from bridge');
      if (mounted) setState(() {});
    });
  }

  void _doCostSync() {
    _initCostAgents();
    if (_costAgents.isEmpty || _costSelectedAgent >= _costAgents.length) return;
    final agent = _costAgents[_costSelectedAgent];
    if (!agent.detected) {
      _setStatus('${agent.displayName} not found', duration: 3);
      return;
    }

    _costSyncing = true;
    _setStatus('Syncing costs to ${agent.displayName}...', duration: 0);
    setState(() {});

    Future.microtask(() {
      List<String> models;
      if (agent.type == CliAgentType.opencode) {
        final info = CostSyncService.getOpenCodeBridgeModels();
        models = info.models;
      } else {
        models = CostSyncService.getUserModels(agent.type);
      }

      if (models.isEmpty) {
        _costSyncing = false;
        _setStatus('Cost sync ${agent.displayName}: no bridge models found', duration: 5);
        if (mounted) setState(() {});
        return;
      }

      final result = CostSyncService.syncCosts(agent.type, models);
      _costSyncing = false;
      LogStore.info('Cost sync ${agent.displayName}: ${result.updated} updated, ${result.skipped} skipped');
      final summary = 'Cost sync ${agent.displayName}: '
          '${result.updated} updated, ${result.skipped} already configured'
          '${result.failed > 0 ? ', ${result.failed} failed' : ''}';
      _setStatus(summary, duration: 6);
      if (mounted) setState(() {});
    });
  }

  Component _buildStatusBar() {
    if (_status.isEmpty) {
      return Container(
        height: 1,
        decoration: const BoxDecoration(
          border: BoxBorder(top: BorderSide(color: Colors.grey)),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 0),
      decoration: const BoxDecoration(
        border: BoxBorder(top: BorderSide(color: Colors.grey)),
      ),
      child: Row(
        children: [
          Text(_status, style: TextStyle(
            color: _notifColor(),
            fontWeight: _status.startsWith('Use [q] to quit') ? FontWeight.bold : null,
          )),
        ],
      ),
    );
  }

  Component _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(1),
      decoration: const BoxDecoration(
        border: BoxBorder(top: BorderSide(color: Colors.grey)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Pages:', style: TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold)),
              for (var i = 0; i < _pageNames.length; i++)
                Padding(
                  padding: const EdgeInsets.only(left: 1),
                  child: Text(
                    i == _infoPage.index
                        ? '[${_pageKeys[i]}]${_pageNames[i]}'
                        : ' ${_pageKeys[i]}:${_pageNames[i].substring(0, 3)} ',
                    style: i == _infoPage.index
                        ? TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold)
                        : TextStyle(color: Colors.grey),
                  ),
                ),
            ],
          ),
          Row(
            children: [
              Text('Actions:', style: TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold)),
              if (_account.isLoaded) ...[
                Text(' [o]', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                Text('penai url ', style: TextStyle(color: Colors.grey)),
                Text('[a]', style: TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold)),
                Text('nthropic url ', style: TextStyle(color: Colors.grey)),
                Text('[r]', style: TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold)),
                Text('efresh ', style: TextStyle(color: Colors.grey)),
                Text('[p]', style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold)),
                Text('ort ', style: TextStyle(color: Colors.grey)),
                Text('[h]', style: TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold)),
                Text('elp ', style: TextStyle(color: Colors.grey)),
                Text('[q]', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                Text('uit ', style: TextStyle(color: Colors.grey)),
                Text('[\u2191][\u2193]', style: TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold)),
                Text('scroll', style: TextStyle(color: Colors.grey)),
              ] else ...[
                Text(' [l]', style: TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold)),
                Text('ogin ', style: TextStyle(color: Colors.grey)),
                Text('[h]', style: TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold)),
                Text('elp ', style: TextStyle(color: Colors.grey)),
                Text('[q]', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                Text('uit', style: TextStyle(color: Colors.grey)),
              ],
              const Spacer(),
              if (_confirmClearLog) ...[
                Text('Clear log? ', style: TextStyle(color: Colors.yellow)),
                Text('[Y]', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                Text('es ', style: TextStyle(color: Colors.grey)),
                Text('[N]', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                Text('o', style: TextStyle(color: Colors.grey)),
              ] else ...[
                Text('Log:', style: TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold)),
                Text(' [Ctrl+L]', style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold)),
                Text(_showLog ? 'hide ' : 'show ', style: TextStyle(color: Colors.grey)),
                if (_showLog) ...[
                  Text('[f]', style: TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold)),
                  Text(_logFullscreen ? 'side ' : 'ull ', style: TextStyle(color: Colors.grey)),
                  Text('[Shift+C]', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  Text('lear all ', style: TextStyle(color: Colors.grey)),
                  Text('[Shift+O]', style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold)),
                  Text('ld only clear', style: TextStyle(color: Colors.grey)),
                ],
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime? dt) {
    if (dt == null) return 'N/A';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _relativeTime(DateTime target) {
    final diff = target.difference(DateTime.now());
    if (diff.isNegative) return '(overdue)';
    if (diff.inDays >= 1) {
      final hours = diff.inHours.remainder(24);
      return '(in ${diff.inDays}d ${hours}h)';
    }
    if (diff.inHours >= 1) {
      final mins = diff.inMinutes.remainder(60);
      return '(in ${diff.inHours}h ${mins}m)';
    }
    if (diff.inMinutes >= 1) {
      return '(in ${diff.inMinutes}m)';
    }
    return '(now)';
  }

  String _fmtNum(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(2)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  String _fmtCtx(int ctx) {
    if (ctx >= 1000000) return '${(ctx / 1000000).toStringAsFixed(0)}M';
    if (ctx >= 1000) return '${(ctx / 1000).toStringAsFixed(0)}K';
    return ctx.toString();
  }
}
