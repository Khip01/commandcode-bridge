import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/account.dart';
import 'log_store.dart';

class WhoamiData {
  final String name;
  final String email;
  final String userName;
  final String id;

  WhoamiData({required this.name, required this.email, required this.userName, required this.id});

  factory WhoamiData.fromJson(Map<String, dynamic> json) => WhoamiData(
        name: json['name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        userName: json['userName'] as String? ?? '',
        id: json['id'] as String? ?? '',
      );
}

class SubscriptionData {
  final String id;
  final String status;
  final String planId;
  final String currentPeriodStart;
  final String currentPeriodEnd;
  final bool cancelAtPeriodEnd;

  SubscriptionData({
    required this.id,
    required this.status,
    required this.planId,
    required this.currentPeriodStart,
    required this.currentPeriodEnd,
    required this.cancelAtPeriodEnd,
  });

  factory SubscriptionData.fromJson(Map<String, dynamic> json) => SubscriptionData(
        id: json['id'] as String? ?? '',
        status: json['status'] as String? ?? '',
        planId: json['planId'] as String? ?? '',
        currentPeriodStart: json['currentPeriodStart'] as String? ?? '',
        currentPeriodEnd: json['currentPeriodEnd'] as String? ?? '',
        cancelAtPeriodEnd: json['cancelAtPeriodEnd'] as bool? ?? false,
      );
}

class CreditsData {
  final double monthlyCredits;
  final double purchasedCredits;
  final double freeCredits;
  final bool belowThreshold;
  final int creditThreshold;
  final WindowLimitData fiveHour;
  final WindowLimitData weekly;

  CreditsData({
    required this.monthlyCredits,
    required this.purchasedCredits,
    required this.freeCredits,
    required this.belowThreshold,
    required this.creditThreshold,
    required this.fiveHour,
    required this.weekly,
  });

  double get totalCredits => monthlyCredits + purchasedCredits + freeCredits;
  double get usedCredits => fiveHour.used + weekly.used; // approximate

  factory CreditsData.fromJson(Map<String, dynamic> json) {
    final credits = json['credits'] as Map<String, dynamic>? ?? {};
    final windows = json['windowLimits'] as Map<String, dynamic>? ?? {};
    return CreditsData(
      monthlyCredits: (credits['monthlyCredits'] as num?)?.toDouble() ?? 0,
      purchasedCredits: (credits['purchasedCredits'] as num?)?.toDouble() ?? 0,
      freeCredits: (credits['freeCredits'] as num?)?.toDouble() ?? 0,
      belowThreshold: credits['belowThreshold'] as bool? ?? false,
      creditThreshold: (credits['creditThreshold'] as num?)?.toInt() ?? 0,
      fiveHour: WindowLimitData.fromJson(windows['fiveHour'] as Map<String, dynamic>? ?? {}),
      weekly: WindowLimitData.fromJson(windows['weekly'] as Map<String, dynamic>? ?? {}),
    );
  }
}

class WindowLimitData {
  final double used;
  final double cap;
  final bool exceeded;
  final int resetAt;

  WindowLimitData({required this.used, required this.cap, required this.exceeded, required this.resetAt});

  factory WindowLimitData.fromJson(Map<String, dynamic> json) => WindowLimitData(
        used: (json['used'] as num?)?.toDouble() ?? 0,
        cap: (json['cap'] as num?)?.toDouble() ?? 0,
        exceeded: json['exceeded'] as bool? ?? false,
        resetAt: (json['resetAt'] as num?)?.toInt() ?? 0,
      );

  DateTime get resetTime => DateTime.fromMillisecondsSinceEpoch(resetAt);
  double get remaining => cap - used;
}

class UsageSummaryData {
  final int totalCount;
  final double totalCost;
  final double averageCost;
  final double successRate;
  final int completedCount;
  final int failedCount;
  final int totalTokensIn;
  final int totalTokensOut;
  final int totalTokens;
  final double totalCredits;
  final double totalFreeCredits;
  final double totalMonthlyCredits;
  final double totalPurchasedCredits;

  UsageSummaryData({
    required this.totalCount,
    required this.totalCost,
    required this.averageCost,
    required this.successRate,
    required this.completedCount,
    required this.failedCount,
    required this.totalTokensIn,
    required this.totalTokensOut,
    required this.totalTokens,
    required this.totalCredits,
    required this.totalFreeCredits,
    required this.totalMonthlyCredits,
    required this.totalPurchasedCredits,
  });

  factory UsageSummaryData.fromJson(Map<String, dynamic> json) => UsageSummaryData(
        totalCount: (json['totalCount'] as num?)?.toInt() ?? 0,
        totalCost: (json['totalCost'] as num?)?.toDouble() ?? 0,
        averageCost: (json['averageCost'] as num?)?.toDouble() ?? 0,
        successRate: (json['successRate'] as num?)?.toDouble() ?? 0,
        completedCount: (json['completedCount'] as num?)?.toInt() ?? 0,
        failedCount: (json['failedCount'] as num?)?.toInt() ?? 0,
        totalTokensIn: (json['totalTokensIn'] as num?)?.toInt() ?? 0,
        totalTokensOut: (json['totalTokensOut'] as num?)?.toInt() ?? 0,
        totalTokens: (json['totalTokens'] as num?)?.toInt() ?? 0,
        totalCredits: (json['totalCredits'] as num?)?.toDouble() ?? 0,
        totalFreeCredits: (json['totalFreeCredits'] as num?)?.toDouble() ?? 0,
        totalMonthlyCredits: (json['totalMonthlyCredits'] as num?)?.toDouble() ?? 0,
        totalPurchasedCredits: (json['totalPurchasedCredits'] as num?)?.toDouble() ?? 0,
      );
}

class AllApiData {
  final WhoamiData? whoami;
  final SubscriptionData? subscription;
  final CreditsData? credits;
  final UsageSummaryData? usage;
  final List<String> errors;

  AllApiData({
    this.whoami,
    this.subscription,
    this.credits,
    this.usage,
    this.errors = const [],
  });

  bool get hasErrors => errors.isNotEmpty;
}

class ApiClient {
  final http.Client _client;
  final String apiKey;
  final String baseUrl;
  final String cliVersion;

  ApiClient({
    required this.apiKey,
    required AppConfig config,
    http.Client? client,
  })  : _client = client ?? http.Client(),
        baseUrl = config.apiBaseUrl,
        cliVersion = config.cliVersion;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'User-Agent': 'cli',
        'x-command-code-version': cliVersion,
        'x-cli-environment': 'production',
      };

  Future<WhoamiData?> fetchWhoami({bool logErrors = true}) async {
    try {
      final res = await _client.get(
        Uri.parse('$baseUrl/alpha/whoami'),
        headers: _headers,
      );
      if (res.statusCode != 200) {
        if (logErrors) LogStore.error('whoami returned ${res.statusCode}');
        return null;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['success'] != true) return null;
      return WhoamiData.fromJson(data['user'] as Map<String, dynamic>);
    } catch (e) {
      if (logErrors) LogStore.error('whoami failed: $e');
      return null;
    }
  }

  Future<CreditsData?> fetchCredits({bool logErrors = true}) async {
    try {
      final res = await _client.get(
        Uri.parse('$baseUrl/alpha/billing/credits'),
        headers: _headers,
      );
      if (res.statusCode != 200) {
        if (logErrors) LogStore.error('credits returned ${res.statusCode}');
        return null;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return CreditsData.fromJson(data);
    } catch (e) {
      if (logErrors) LogStore.error('credits failed: $e');
      return null;
    }
  }

  Future<SubscriptionData?> fetchSubscription({bool logErrors = true}) async {
    try {
      final res = await _client.get(
        Uri.parse('$baseUrl/alpha/billing/subscriptions'),
        headers: _headers,
      );
      if (res.statusCode != 200) {
        if (logErrors) LogStore.error('subscription returned ${res.statusCode}');
        return null;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final subData = data['data'] as Map<String, dynamic>?;
      if (subData == null) return null;
      return SubscriptionData.fromJson(subData);
    } catch (e) {
      if (logErrors) LogStore.error('subscription failed: $e');
      return null;
    }
  }

  Future<UsageSummaryData?> fetchUsage({bool logErrors = true}) async {
    try {
      final res = await _client.get(
        Uri.parse('$baseUrl/alpha/usage/summary'),
        headers: _headers,
      );
      if (res.statusCode != 200) {
        if (logErrors) LogStore.error('usage returned ${res.statusCode}');
        return null;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return UsageSummaryData.fromJson(data);
    } catch (e) {
      if (logErrors) LogStore.error('usage failed: $e');
      return null;
    }
  }

  Future<AllApiData> fetchAll({bool logSummary = true, bool logErrors = true}) async {
    final whoamiF = fetchWhoami(logErrors: logErrors);
    final creditsF = fetchCredits(logErrors: logErrors);
    final subF = fetchSubscription(logErrors: logErrors);
    final usageF = fetchUsage(logErrors: logErrors);

    final results = await Future.wait([whoamiF, creditsF, subF, usageF]);
    final errors = <String>[];
    if (results[0] == null) errors.add('whoami');
    if (results[1] == null) errors.add('credits');
    if (results[2] == null) errors.add('subscription');
    if (results[3] == null) errors.add('usage');

    if (logSummary) {
      LogStore.info('Fetched API data (${errors.isEmpty ? "all ok" : "errors: ${errors.join(",")}"})');
    }

    return AllApiData(
      whoami: results[0] as WhoamiData?,
      credits: results[1] as CreditsData?,
      subscription: results[2] as SubscriptionData?,
      usage: results[3] as UsageSummaryData?,
      errors: errors,
    );
  }

  void dispose() {
    _client.close();
  }
}
