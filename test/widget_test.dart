import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';
import 'package:smart_spend/main.dart';
import 'package:smart_spend/data/database.dart';
import 'package:smart_spend/data/finance_repository.dart';
import 'package:smart_spend/features/home.dart';

void main() {
  testWidgets('Onboarding wallet validates input and creates wallet', (
    tester,
  ) async {
    final db = LocalDatabase(NativeDatabase.memory());
    final repo = FinanceRepository(db);
    await repo.initialize();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: Home()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chào mừng đến SmartSpend'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    expect(find.textContaining('không hợp lệ'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Ví tiền mặt');
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    expect((await repo.wallets()).single['name'], 'Ví tiền mặt');
    await tester.pumpWidget(const SizedBox());
    await db.close();
  });
}
