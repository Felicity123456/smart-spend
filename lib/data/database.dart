import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class LocalDatabase extends GeneratedDatabase {
  LocalDatabase(super.executor);
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      for (final sql in schema) {
        await customStatement(sql);
      }
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

Future<LocalDatabase> openDatabase() async {
  final dir = await getApplicationSupportDirectory();
  return LocalDatabase(
    NativeDatabase.createInBackground(
      File(p.join(dir.path, 'smartspend.sqlite')),
    ),
  );
}

const schema = [
  'CREATE TABLE wallets(id TEXT PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL, opening INTEGER NOT NULL CHECK(opening>=0), archived INTEGER NOT NULL DEFAULT 0)',
  "CREATE TABLE categories(id TEXT PRIMARY KEY, name TEXT NOT NULL, kind TEXT NOT NULL CHECK(kind IN ('INCOME','EXPENSE')), archived INTEGER NOT NULL DEFAULT 0)",
  "CREATE TABLE transactions(id TEXT PRIMARY KEY, wallet_id TEXT NOT NULL REFERENCES wallets(id), category_id TEXT NOT NULL REFERENCES categories(id), kind TEXT NOT NULL CHECK(kind IN ('INCOME','EXPENSE')), amount INTEGER NOT NULL CHECK(amount>0), note TEXT NOT NULL, occurred_at INTEGER NOT NULL)",
  'CREATE INDEX tx_date ON transactions(occurred_at DESC)',
  'CREATE TABLE transfers(id TEXT PRIMARY KEY, from_id TEXT NOT NULL REFERENCES wallets(id), to_id TEXT NOT NULL REFERENCES wallets(id), amount INTEGER NOT NULL CHECK(amount>0), occurred_at INTEGER NOT NULL, note TEXT NOT NULL, CHECK(from_id<>to_id))',
  'CREATE TABLE budgets(id TEXT PRIMARY KEY, category_id TEXT NOT NULL REFERENCES categories(id), period TEXT NOT NULL, amount INTEGER NOT NULL CHECK(amount>0), UNIQUE(category_id,period))',
  'CREATE TABLE goals(id TEXT PRIMARY KEY, name TEXT NOT NULL, target INTEGER NOT NULL CHECK(target>0), due_date INTEGER)',
  'CREATE TABLE contributions(id TEXT PRIMARY KEY, goal_id TEXT NOT NULL REFERENCES goals(id), wallet_id TEXT NOT NULL REFERENCES wallets(id), amount INTEGER NOT NULL CHECK(amount>0), occurred_at INTEGER NOT NULL)',
  'CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
];
