import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:smart_spend/core/budget_alerts.dart';
import 'package:smart_spend/data/database.dart';
import 'package:smart_spend/data/finance_repository.dart';

class FakeDelivery implements AlertDelivery {
  bool allowed = true;
  bool fail = false;
  int requests = 0;
  final messages = <String>[];
  @override
  bool get supported => true;
  @override
  Future<bool> requestPermission() async {
    requests++;
    return allowed;
  }

  @override
  Future<void> show(int id, String body) async {
    if (fail) throw Exception('Unavailable');
    messages.add(body);
  }
}

void main() {
  late LocalDatabase db;
  late FinanceRepository repo;
  late FakeDelivery delivery;
  late BudgetAlerts alerts;
  late String wallet;
  late String category;
  final month = DateTime(2026, 11);
  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    repo = FinanceRepository(db);
    await repo.initialize();
    await repo.wallet('Cash', 'cash', 4000000);
    wallet = (await repo.wallets()).single['id'];
    category = (await repo.query(
      "SELECT id FROM categories WHERE kind='EXPENSE' LIMIT 1",
    )).single['id'];
    await repo.write('INSERT INTO budgets VALUES(?,?,?,?)', [
      'budget',
      category,
      '2026-11',
      1000000,
    ]);
    delivery = FakeDelivery();
    alerts = BudgetAlerts(delivery: delivery);
  });
  tearDown(() async {
    await db.close();
  });
  Future<void> expense(int amount) => repo.saveTransaction(
    wallet: wallet,
    category: category,
    kind: 'EXPENSE',
    amount: amount,
    note: '',
    date: month,
  );
  test('Requests permission once and respects disabled preference', () async {
    await alerts.ensurePermission(repo);
    await alerts.ensurePermission(repo);
    expect(delivery.requests, 1);
    await repo.write("UPDATE settings SET value='0' WHERE key='alerts'", []);
    await alerts.ensurePermission(repo);
    await expense(800000);
    await alerts.check(repo, month);
    expect(delivery.requests, 1);
    expect(delivery.messages, isEmpty);
  });
  test('No alert below 80%, alerts once at 80% and again at 100%', () async {
    await alerts.ensurePermission(repo);
    await expense(799999);
    expect(await alerts.check(repo, month), isEmpty);
    await expense(1);
    await alerts.check(repo, month);
    expect(delivery.messages.single, contains('80%'));
    await alerts.check(repo, month);
    expect(delivery.messages.length, 1);
    await expense(200000);
    await alerts.check(repo, month);
    expect(delivery.messages.length, 2);
    await alerts.check(repo, month);
    expect(delivery.messages.length, 2);
    expect(await alerts.check(repo, DateTime(2026, 12)), isEmpty);
  });
  test(
    'Failed notification retries and direct 100% suppresses stale 80% alert',
    () async {
      await alerts.ensurePermission(repo);
      await expense(1000000);
      delivery.fail = true;
      await expectLater(alerts.check(repo, month), throwsException);
      delivery.fail = false;
      await alerts.check(repo, month);
      expect(delivery.messages.length, 1);
      final tx = (await repo.transactions(month)).single;
      await repo.saveTransaction(
        id: tx['id'],
        wallet: wallet,
        category: category,
        kind: 'EXPENSE',
        amount: 800000,
        note: '',
        date: month,
      );
      expect(await alerts.check(repo, month), isEmpty);
    },
  );
}
