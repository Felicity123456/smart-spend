import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:smart_spend/core/money.dart';
import 'package:smart_spend/data/database.dart';
import 'package:smart_spend/data/finance_repository.dart';

void main() {
  late LocalDatabase db;
  late FinanceRepository repo;
  late String cash;
  late String bank;
  late String expense;
  late String income;
  final date = DateTime(2026, 11, 1);
  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    repo = FinanceRepository(db);
    await repo.initialize();
    await repo.wallet('Cash', 'cash', 500000);
    await repo.wallet('Bank', 'bank', 0);
    final wallets = await repo.wallets();
    cash = wallets[0]['id'];
    bank = wallets[1]['id'];
    final cats = await repo.query('SELECT * FROM categories');
    expense = cats.firstWhere((c) => c['kind'] == 'EXPENSE')['id'];
    income = cats.firstWhere((c) => c['kind'] == 'INCOME')['id'];
  });
  tearDown(() async => db.close());
  Future<void> spend(int amount, {String? id}) => repo.saveTransaction(
    id: id,
    wallet: cash,
    category: expense,
    kind: 'EXPENSE',
    amount: amount,
    note: 'Lunch',
    date: date,
  );
  Future<int> balance(String id) async =>
      (await repo.wallets()).firstWhere((w) => w['id'] == id)['balance'];
  test('TC01: expense reduces wallet balance', () async {
    await spend(75000);
    expect(await balance(cash), 425000);
  });
  test('TC02: amount validation', () async {
    for (final input in ['0', '-1', '1.5', 'abc']) {
      expect(() => parseMoney(input), throwsException);
    }
    expect(parseMoney('75000'), 75000);
    await expectLater(spend(0), throwsException);
  });
  test(
    'TC03: transfer conserves assets and rejects identical wallets',
    () async {
      await repo.transfer(cash, bank, 100000, '', date);
      expect(await balance(cash), 400000);
      expect(await balance(bank), 100000);
      await expectLater(
        repo.transfer(cash, cash, 1, '', date),
        throwsException,
      );
    },
  );
  test('TC04: budget reflects 80 percent spending', () async {
    await repo.write('INSERT INTO budgets VALUES(?,?,?,?)', [
      newId(),
      expense,
      '2026-11',
      100000,
    ]);
    await spend(80000);
    final b = (await repo.budgets(date)).single;
    expect(b['spent'] * 100, b['amount'] * 80);
  });
  test('TC05: editing and deletion rebuild ledger', () async {
    await spend(50000);
    final id = (await repo.transactions(date)).single['id'];
    await spend(80000, id: id);
    expect(await balance(cash), 420000);
    await repo.deleteTransaction(id);
    expect(await balance(cash), 500000);
  });
  test('TC06: savings contribution is not expense', () async {
    final id = newId();
    await repo.write('INSERT INTO goals VALUES(?,?,?,NULL)', [
      id,
      'Laptop',
      1000000,
    ]);
    await repo.contribute(id, cash, 100000);
    expect(await balance(cash), 400000);
    expect((await repo.goals()).single['saved'], 100000);
    expect(
      (await repo.summary(date))
          .fold<int>(0, (s, r) => s + (r['total'] as int)),
      0,
    );
  });
  test('TC08: month boundaries are half open', () async {
    await spend(1);
    await repo.saveTransaction(
      wallet: cash,
      category: income,
      kind: 'INCOME',
      amount: 10,
      note: '',
      date: DateTime(2026, 12, 1),
    );
    expect((await repo.transactions(date)).length, 1);
  });
  test('TC09: archived category keeps history', () async {
    await spend(1);
    await repo.archive('categories', expense);
    expect((await repo.transactions(date)).single['category_id'], expense);
    await expectLater(spend(1), throwsException);
  });
  test('overdraft rolls back transfer and edited transaction', () async {
    await expectLater(
      repo.transfer(cash, bank, 600000, '', date),
      throwsException,
    );
    expect(await balance(cash), 500000);
    expect((await repo.query('SELECT * FROM transfers')), isEmpty);
    await spend(1);
    final id = (await repo.transactions(date)).single['id'];
    await expectLater(spend(600000, id: id), throwsException);
    expect(await balance(cash), 499999);
  });
  test('query paginates transactions', () async {
    for (var i = 0; i < 35; i++) {
      await spend(1);
    }
    expect((await repo.transactions(date)).length, 30);
    expect((await repo.transactions(date, offset: 30)).length, 5);
  });
}
