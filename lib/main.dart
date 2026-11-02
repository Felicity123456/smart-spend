import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data/database.dart';
import 'data/finance_repository.dart';
import 'features/home.dart';

final repositoryProvider = Provider<FinanceRepository>(
  (ref) => throw UnimplementedError(),
);
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final repository = FinanceRepository(await openDatabase());
    await repository.initialize(seedTestWallet: true);
    runApp(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repository)],
        child: const SmartSpendApp(),
      ),
    );
  } catch (_) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'Không thể mở dữ liệu. Vui lòng khởi động lại ứng dụng.',
            ),
          ),
        ),
      ),
    );
  }
}

final router = GoRouter(
  routes: [GoRoute(path: '/', builder: (_, _) => const Home())],
);

class SmartSpendApp extends StatelessWidget {
  const SmartSpendApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'SmartSpend - Personal Finance Management',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff147d64)),
      scaffoldBackgroundColor: const Color(0xfff5f7f8),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.symmetric(vertical: 6),
      ),
    ),
    routerConfig: router,
  );
}
