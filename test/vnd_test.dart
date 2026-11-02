import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:smart_spend/core/money.dart';
import 'package:smart_spend/data/database.dart';
import 'package:smart_spend/data/finance_repository.dart';

void main() {
  test('VND formatting and parsing preserves integer amounts', () {
    for (final amount in [30000, 300000, 3000000, 4000000]) {
      final formatted = formatVndInput(amount.toString());
      expect(parseMoney(formatted), amount);
      final edit = const VndInputFormatter().formatEditUpdate(
        TextEditingValue.empty,
        TextEditingValue(
          text: amount.toString(),
          selection: TextSelection.collapsed(offset: amount.toString().length),
        ),
      );
      expect(edit.text, formatted);
      expect(edit.selection.extentOffset, formatted.length);
    }
    expect(parseMoney('0', allowZero: true), 0);
    expect(() => parseMoney('30.00'), throwsException);
    expect(() => parseMoney('1.5'), throwsException);
  });
  test(
    'Test wallet seeds once and never overwrites existing balances',
    () async {
      final db = LocalDatabase(NativeDatabase.memory());
      final repo = FinanceRepository(db);
      await repo.initialize(seedTestWallet: true);
      expect((await repo.wallets()).single['balance'], 4000000);
      await repo.initialize(seedTestWallet: true);
      expect((await repo.wallets()).length, 1);
      await db.close();
      final secondDb = LocalDatabase(NativeDatabase.memory());
      final existing = FinanceRepository(secondDb);
      await existing.wallet('Ví cá nhân', 'cash', 123000);
      await existing.initialize(seedTestWallet: true);
      expect((await existing.wallets()).single['balance'], 123000);
      await secondDb.close();
    },
  );
}
