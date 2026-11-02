import 'package:drift/drift.dart';

import '../core/money.dart';
import 'database.dart';

typedef DataRowMap = Map<String, dynamic>;

class FinanceRepository {
  final LocalDatabase db;
  FinanceRepository(this.db);
  Future<List<DataRowMap>> query(
    String sql, [
    List<Object> args = const [],
  ]) async =>
      (await db
              .customSelect(
                sql,
                variables: args.map((v) => Variable(v)).toList(),
              )
              .get())
          .map((r) => r.data)
          .toList();
  Future<void> write(String sql, List<Object?> args) =>
      db.customStatement(sql, args);
  Future<void> initialize({bool seedTestWallet = false}) async {
    if (seedTestWallet) {
      await db.transaction(() async {
        final seeded = await query(
          "SELECT key FROM settings WHERE key='test_wallet_initialized'",
        );
        if (seeded.isEmpty) {
          if ((await query('SELECT id FROM wallets LIMIT 1')).isEmpty) {
            await wallet('Ví test', 'cash', 4000000);
          }
          await write(
            "INSERT INTO settings VALUES('test_wallet_initialized','1')",
            [],
          );
        }
      });
    }
    if ((await query('SELECT * FROM categories')).isEmpty) {
      await db.transaction(() async {
        for (final name in [
          'Ăn uống',
          'Di chuyển',
          'Mua sắm',
          'Hóa đơn',
          'Giải trí',
          'Sức khỏe',
        ]) {
          await write('INSERT INTO categories VALUES(?,?,?,0)', [
            newId(),
            name,
            'EXPENSE',
          ]);
        }
        for (final name in ['Lương', 'Thưởng', 'Thu nhập khác']) {
          await write('INSERT INTO categories VALUES(?,?,?,0)', [
            newId(),
            name,
            'INCOME',
          ]);
        }
      });
    }
  }

  Future<List<DataRowMap>> wallets() => query(
    '''SELECT w.*, w.opening
    + COALESCE((SELECT SUM(CASE kind WHEN 'INCOME' THEN amount ELSE -amount END) FROM transactions WHERE wallet_id=w.id),0)
    + COALESCE((SELECT SUM(amount) FROM transfers WHERE to_id=w.id),0)
    - COALESCE((SELECT SUM(amount) FROM transfers WHERE from_id=w.id),0)
    - COALESCE((SELECT SUM(amount) FROM contributions WHERE wallet_id=w.id),0) AS balance FROM wallets w''',
  );
  Future<void> checkBalances() async {
    if ((await wallets()).any((w) => (w['balance'] as int) < 0)) {
      throw Exception('Số dư ví không đủ. Thao tác đã được hoàn tác.');
    }
  }

  Future<void> activeWallet(String id) async {
    if ((await query('SELECT id FROM wallets WHERE id=? AND archived=0', [
      id,
    ])).isEmpty) {
      throw Exception('Ví không còn hoạt động.');
    }
  }

  Future<void> wallet(
    String name,
    String type,
    int opening, {
    String? id,
  }) async {
    if (name.trim().isEmpty || opening < 0) {
      throw Exception('Tên ví và số dư ban đầu không hợp lệ.');
    }
    if (id == null) {
      await write('INSERT INTO wallets VALUES(?,?,?,?,0)', [
        newId(),
        name.trim(),
        type,
        opening,
      ]);
    } else {
      await write('UPDATE wallets SET name=?,type=? WHERE id=?', [
        name.trim(),
        type,
        id,
      ]);
    }
  }

  Future<void> archive(String table, String id) async {
    if (!['wallets', 'categories'].contains(table)) {
      throw Exception('Không hợp lệ');
    }
    await write('UPDATE $table SET archived=1 WHERE id=?', [id]);
  }

  Future<void> category(String name, String kind, {String? id}) async {
    if (name.trim().isEmpty) throw Exception('Vui lòng nhập tên.');
    if (id == null) {
      await write('INSERT INTO categories VALUES(?,?,?,0)', [
        newId(),
        name.trim(),
        kind,
      ]);
    } else {
      await write('UPDATE categories SET name=? WHERE id=?', [name.trim(), id]);
    }
  }

  Future<void> saveTransaction({
    String? id,
    required String wallet,
    required String category,
    required String kind,
    required int amount,
    required String note,
    required DateTime date,
  }) => db.transaction(() async {
    if (amount <= 0) throw Exception('Số tiền phải lớn hơn 0.');
    await activeWallet(wallet);
    if ((await query(
      'SELECT id FROM categories WHERE id=? AND kind=? AND archived=0',
      [category, kind],
    )).isEmpty) {
      throw Exception('Danh mục không phù hợp.');
    }
    if (id != null) await write('DELETE FROM transactions WHERE id=?', [id]);
    await write('INSERT INTO transactions VALUES(?,?,?,?,?,?,?)', [
      id ?? newId(),
      wallet,
      category,
      kind,
      amount,
      note,
      date.millisecondsSinceEpoch,
    ]);
    await checkBalances();
  });
  Future<void> deleteTransaction(String id) => db.transaction(() async {
    await write('DELETE FROM transactions WHERE id=?', [id]);
    await checkBalances();
  });
  Future<void> transfer(
    String from,
    String to,
    int amount,
    String note,
    DateTime date,
  ) => db.transaction(() async {
    if (from == to || amount <= 0) {
      throw Exception('Chọn hai ví khác nhau và số tiền dương.');
    }
    await activeWallet(from);
    await activeWallet(to);
    await write('INSERT INTO transfers VALUES(?,?,?,?,?,?)', [
      newId(),
      from,
      to,
      amount,
      date.millisecondsSinceEpoch,
      note,
    ]);
    await checkBalances();
  });
  Future<void> contribute(String goal, String wallet, int amount) =>
      db.transaction(() async {
        if (amount <= 0) throw Exception('Số tiền phải lớn hơn 0.');
        await activeWallet(wallet);
        await write('INSERT INTO contributions VALUES(?,?,?,?,?)', [
          newId(),
          goal,
          wallet,
          amount,
          DateTime.now().millisecondsSinceEpoch,
        ]);
        await checkBalances();
      });
  Future<List<DataRowMap>> transactions(
    DateTime month, {
    String search = '',
    String? category,
    int offset = 0,
  }) {
    final start = DateTime(month.year, month.month).millisecondsSinceEpoch;
    final end = DateTime(month.year, month.month + 1).millisecondsSinceEpoch;
    return query(
      '''SELECT t.*,c.name AS category,w.name AS wallet FROM transactions t JOIN categories c ON c.id=t.category_id JOIN wallets w ON w.id=t.wallet_id
      WHERE occurred_at>=? AND occurred_at<? AND (note LIKE ? OR c.name LIKE ?) ${category == null ? '' : 'AND category_id=?'} ORDER BY occurred_at DESC,id DESC LIMIT 30 OFFSET ?''',
      [start, end, '%$search%', '%$search%', ?category, offset],
    );
  }

  Future<List<DataRowMap>> summary(DateTime month) => query(
    '''SELECT c.id,c.name,c.kind,COALESCE(SUM(t.amount),0) AS total FROM categories c LEFT JOIN transactions t ON t.category_id=c.id AND t.occurred_at>=? AND t.occurred_at<? GROUP BY c.id''',
    [
      DateTime(month.year, month.month).millisecondsSinceEpoch,
      DateTime(month.year, month.month + 1).millisecondsSinceEpoch,
    ],
  );
  Future<List<DataRowMap>> budgets(DateTime month) => query(
    '''SELECT b.*,c.name,COALESCE((SELECT SUM(amount) FROM transactions WHERE category_id=b.category_id AND kind='EXPENSE' AND occurred_at>=? AND occurred_at<?),0) AS spent FROM budgets b JOIN categories c ON c.id=b.category_id WHERE period=?''',
    [
      DateTime(month.year, month.month).millisecondsSinceEpoch,
      DateTime(month.year, month.month + 1).millisecondsSinceEpoch,
      monthKey(month),
    ],
  );
  Future<List<DataRowMap>> goals() => query(
    'SELECT g.*,COALESCE((SELECT SUM(amount) FROM contributions WHERE goal_id=g.id),0) AS saved FROM goals g',
  );
}
