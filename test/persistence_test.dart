import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_spend/data/database.dart';
import 'package:smart_spend/data/finance_repository.dart';

void main() {
  test('TC07: SQLite preserves data after reopening without network', () async {
    final dir = await Directory.systemTemp.createTemp('smartspend_test_');
    final file = File('${dir.path}/test.sqlite');
    var db = LocalDatabase(NativeDatabase(file));
    var repo = FinanceRepository(db);
    await repo.initialize();
    await repo.wallet('Offline wallet', 'cash', 500000);
    await db.close();
    db = LocalDatabase(NativeDatabase(file));
    repo = FinanceRepository(db);
    expect((await repo.wallets()).single['balance'], 500000);
    expect((await repo.wallets()).single['name'], 'Offline wallet');
    await db.close();
    await dir.delete(recursive: true);
  });
}
