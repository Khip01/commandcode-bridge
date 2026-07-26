import 'package:test/test.dart';
import 'package:commandcode_bridge/src/models/account.dart';

void main() {
  group('AppAccount', () {
    test('fromJson and toJson roundtrip', () {
      final json = {
        'apiKey': 'user_test123',
        'userId': 'abc-123',
        'userName': 'testuser',
        'keyName': 'my-key',
        'authenticatedAt': '2026-07-26T02:59:22.291Z',
      };
      final account = AppAccount.fromJson(json);
      expect(account.apiKey, 'user_test123');
      expect(account.userId, 'abc-123');
      expect(account.userName, 'testuser');
      expect(account.keyName, 'my-key');

      final out = account.toJson();
      expect(out['apiKey'], 'user_test123');
      expect(out['userId'], 'abc-123');
    });
  });

  group('AppConfig', () {
    test('default config', () {
      final cfg = AppConfig();
      expect(cfg.serverPort, 17077);
      expect(cfg.apiBaseUrl, 'https://api.commandcode.ai');
      expect(cfg.cliVersion, '1.4.1');
    });

    test('fromJson and toJson roundtrip', () {
      final json = {
        'server_port': 9090,
        'api_base_url': 'https://staging-api.commandcode.ai',
        'cli_version': '1.5.0',
      };
      final cfg = AppConfig.fromJson(json);
      expect(cfg.serverPort, 9090);
      expect(cfg.apiBaseUrl, 'https://staging-api.commandcode.ai');
      expect(cfg.cliVersion, '1.5.0');

      final out = cfg.toJson();
      expect(out['server_port'], 9090);
    });
  });
}
