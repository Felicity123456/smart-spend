import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../data/finance_repository.dart';

abstract class AlertDelivery {
  bool get supported;
  Future<bool> requestPermission();
  Future<void> show(int id, String body);
}

class DeviceAlertDelivery implements AlertDelivery {
  final plugin = FlutterLocalNotificationsPlugin();
  bool initialized = false;
  @override
  bool get supported => Platform.isAndroid || Platform.isIOS;
  Future<void> initialize() async {
    if (initialized || !supported) return;
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_smartspend'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    initialized = true;
  }

  @override
  Future<bool> requestPermission() async {
    if (!supported) return false;
    await initialize();
    if (Platform.isAndroid) {
      return await plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
    }
    return await plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, sound: true) ??
        false;
  }

  @override
  Future<void> show(int id, String body) async {
    await initialize();
    await plugin.show(
      id: id,
      title: 'SmartSpend • Nhắc nhở chi tiêu',
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'budget_reminders_v2',
          'Nhắc nhở chi tiêu',
          channelDescription: 'Cảnh báo khi chi tiêu đạt 80% và 100% ngân sách',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
    );
  }
}

class BudgetAlerts {
  BudgetAlerts({AlertDelivery? delivery})
    : delivery = delivery ?? DeviceAlertDelivery();
  final AlertDelivery delivery;
  Future<bool> enable() => delivery.requestPermission();
  Future<void> ensurePermission(FinanceRepository repo) async {
    if (!delivery.supported) return;
    final saved = await repo.query(
      "SELECT value FROM settings WHERE key='alerts'",
    );
    if (saved.isNotEmpty) return;
    final allowed = await enable();
    await repo.write("INSERT OR IGNORE INTO settings VALUES('alerts',?)", [
      allowed ? '1' : '0',
    ]);
  }

  Future<List<String>> check(FinanceRepository repo, DateTime month) async {
    final messages = <String>[];
    final enabled = await repo.query(
      "SELECT value FROM settings WHERE key='alerts'",
    );
    if (enabled.isEmpty || enabled.first['value'] != '1' || !delivery.supported) {
      return messages;
    }
    for (final budget in await repo.budgets(month)) {
      final spent = budget['spent'] as int;
      final limit = budget['amount'] as int;
      final level = spent >= limit
          ? 100
          : spent * 100 >= limit * 80
          ? 80
          : 0;
      if (level == 0) continue;
      final key = 'alert_${budget['id']}_$level';
      if ((await repo.query('SELECT key FROM settings WHERE key=?', [
        key,
      ])).isNotEmpty) {
        continue;
      }
      final message = level == 100
          ? '${budget['name']}: đã đạt hoặc vượt ngân sách tháng ${month.month}/${month.year}. Hãy kiểm soát các khoản chi tiếp theo.'
          : '${budget['name']}: đã chi tiêu ít nhất 80% ngân sách tháng ${month.month}/${month.year}. Chỉ còn tối đa 20% hạn mức.';
      await delivery.show(stableId(budget['id'] as String), message);
      await repo.write('INSERT OR REPLACE INTO settings VALUES(?,?)', [
        key,
        '1',
      ]);
      // Reaching 100% directly also consumes the lower threshold.
      if (level == 100) {
        await repo.write('INSERT OR REPLACE INTO settings VALUES(?,?)', [
          'alert_${budget['id']}_80',
          '1',
        ]);
      }
      messages.add(message);
    }
    return messages;
  }

  int stableId(String key) =>
      key.codeUnits.fold<int>(0, (hash, c) => (hash * 31 + c) & 0x7fffffff);
}
