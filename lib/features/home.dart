import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:share_plus/share_plus.dart';

import '../core/money.dart';
import '../core/budget_alerts.dart';
import '../data/finance_repository.dart';
import '../main.dart';

class Home extends ConsumerStatefulWidget {
  const Home({super.key});
  @override
  ConsumerState<Home> createState() => _HomeState();
}

class _HomeState extends ConsumerState<Home> {
  FinanceRepository get repo => ref.read(repositoryProvider);
  final alerts = BudgetAlerts();
  int page = 0, offset = 0;
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  String search = '';
  String? categoryFilter;
  List<DataRowMap> wallets = [],
      categories = [],
      transactions = [],
      summary = [],
      budgets = [],
      goals = [],
      transfers = [],
      contributions = [];
  bool loading = true;
  bool alertsEnabled = false;
  String? alertError;
  String? error;
  final titles = [
    'Tổng quan',
    'Giao dịch',
    'Ví của tôi',
    'Danh mục',
    'Ngân sách',
    'Báo cáo',
    'Tiết kiệm',
    'Cài đặt',
  ];
  final icons = [
    Icons.dashboard_outlined,
    Icons.swap_vert,
    Icons.account_balance_wallet_outlined,
    Icons.category_outlined,
    Icons.pie_chart_outline,
    Icons.bar_chart,
    Icons.savings_outlined,
    Icons.settings_outlined,
  ];
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      wallets = await repo.wallets();
      categories = await repo.query('SELECT * FROM categories');
      transactions = await repo.transactions(
        month,
        search: search,
        category: categoryFilter,
        offset: offset,
      );
      summary = await repo.summary(month);
      budgets = await repo.budgets(month);
      try {
        await alerts.ensurePermission(repo);
        final messages = await alerts.check(repo, DateTime.now());
        final preferences = await repo.query(
          "SELECT value FROM settings WHERE key='alerts'",
        );
        alertsEnabled =
            preferences.isNotEmpty && preferences.first['value'] == '1';
        alertError = null;
        if (messages.isNotEmpty && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(messages.join('\n')),
                  duration: const Duration(seconds: 6),
                ),
              );
            }
          });
        }
      } catch (_) {
        alertError = 'Chưa thể gửi thông báo. Kiểm tra quyền thông báo trong cài đặt thiết bị.';
      }
      goals = await repo.goals();
      transfers = await repo.query(
        'SELECT t.*,a.name AS source,b.name AS destination FROM transfers t JOIN wallets a ON a.id=t.from_id JOIN wallets b ON b.id=t.to_id ORDER BY occurred_at DESC LIMIT 30',
      );
      contributions = await repo.query(
        'SELECT c.*,g.name AS goal,w.name AS wallet FROM contributions c JOIN goals g ON g.id=c.goal_id JOIN wallets w ON w.id=c.wallet_id ORDER BY occurred_at DESC LIMIT 30',
      );
    } catch (e) {
      error = 'Không thể tải dữ liệu: $e';
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> action(Future<void> Function() fn) async {
    try {
      await fn();
      await load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Đã lưu thay đổi')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  int total(String kind) => summary
      .where((r) => r['kind'] == kind)
      .fold(0, (s, r) => s + (r['total'] as int));
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 850;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/branding/smartspend_logo.png',
              width: 36,
              height: 36,
              semanticLabel: 'Logo SmartSpend',
            ),
            const SizedBox(width: 10),
            const Text(
              'SmartSpend',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))],
      ),
      drawer: wide ? null : Drawer(child: SafeArea(child: menu())),
      body: Row(
        children: [
          if (wide) SizedBox(width: 230, child: menu()),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(error!),
                        TextButton(
                          onPressed: load,
                          child: const Text('Thử lại'),
                        ),
                      ],
                    ),
                  )
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1000),
                      child: ListView(
                        padding: const EdgeInsets.all(24),
                        children: [
                          Text(
                            titles[page],
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          if ([0, 1, 4, 5].contains(page))
                            Row(
                              children: [
                                IconButton(
                                  onPressed: () => changeMonth(-1),
                                  icon: const Icon(Icons.chevron_left),
                                ),
                                Text('Tháng ${month.month}/${month.year}'),
                                IconButton(
                                  onPressed: () => changeMonth(1),
                                  icon: const Icon(Icons.chevron_right),
                                ),
                              ],
                            ),
                          const SizedBox(height: 12),
                          ...content(),
                          const SizedBox(height: 90),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: page == 7
          ? null
          : FloatingActionButton.extended(
              onPressed: () => openAdd(),
              icon: const Icon(Icons.add),
              label: Text(
                [
                  'Ghi thu / chi',
                  'Ghi thu / chi',
                  'Tạo ví',
                  'Tạo danh mục',
                  'Đặt ngân sách',
                  'Ghi thu / chi',
                  'Tạo mục tiêu',
                ][page],
              ),
            ),
    );
  }

  Widget menu() => ListView(
    children: [
      const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'PERSONAL FINANCE\nQuản lý hôm nay, vững vàng ngày mai.',
          style: TextStyle(color: Colors.teal),
        ),
      ),
      for (int i = 0; i < titles.length; i++)
        ListTile(
          selected: page == i,
          leading: Icon(icons[i]),
          title: Text(titles[i]),
          onTap: () {
            setState(() => page = i);
            if (MediaQuery.sizeOf(context).width <= 850) Navigator.pop(context);
          },
        ),
    ],
  );
  void changeMonth(int n) {
    month = DateTime(month.year, month.month + n);
    offset = 0;
    load();
  }

  Widget empty(String label) => Padding(
    padding: const EdgeInsets.all(30),
    child: Column(
      children: [
        const Icon(Icons.inbox_outlined, size: 48, color: Colors.grey),
        const SizedBox(height: 12),
        Text(label, textAlign: TextAlign.center),
      ],
    ),
  );
  Widget tile(
    String title,
    String subtitle, {
    Widget? trailing,
    VoidCallback? onTap,
    IconData icon = Icons.receipt_long,
  }) => Card(
    child: ListTile(
      leading: CircleAvatar(child: Icon(icon)),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: trailing,
      onTap: onTap,
    ),
  );
  Widget metric(String title, int amount, Color color) => Container(
    width: 260,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 10),
        Text(
          money(amount),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 25,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );
  List<Widget> content() {
    switch (page) {
      case 0:
        return [
          if (wallets.isEmpty)
            tile(
              'Chào mừng đến SmartSpend',
              'Tạo ví đầu tiên để bắt đầu ghi thu chi.',
              onTap: walletForm,
              icon: Icons.waving_hand_outlined,
            ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              metric(
                'Số dư các ví',
                wallets.fold(0, (s, r) => s + (r['balance'] as int)),
                const Color(0xff147d64),
              ),
              metric(
                'Thu nhập tháng này',
                total('INCOME'),
                const Color(0xff376aac),
              ),
              metric(
                'Chi tiêu tháng này',
                total('EXPENSE'),
                const Color(0xffbe684d),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Ngân sách tháng',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          ...budgetCards(),
          const SizedBox(height: 20),
          Text(
            'Giao dịch gần đây',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          ...transactionCards(transactions.take(5).toList()),
        ];
      case 1:
        return [
          TextFormField(
            initialValue: search,
            decoration: const InputDecoration(
              labelText: 'Tìm theo ghi chú / danh mục',
              prefixIcon: Icon(Icons.search),
            ),
            onFieldSubmitted: (v) {
              search = v;
              offset = 0;
              load();
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: categoryFilter,
            decoration: const InputDecoration(labelText: 'Lọc danh mục'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Tất cả')),
              for (final c in categories)
                DropdownMenuItem(
                  value: c['id'] as String,
                  child: Text(c['name'] as String),
                ),
            ],
            onChanged: (v) {
              categoryFilter = v;
              offset = 0;
              load();
            },
          ),
          ...transactionCards(transactions),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: offset > 0
                    ? () {
                        offset -= 30;
                        load();
                      }
                    : null,
                child: const Text('Trang trước'),
              ),
              Text('Trang ${offset ~/ 30 + 1}'),
              TextButton(
                onPressed: transactions.length == 30
                    ? () {
                        offset += 30;
                        load();
                      }
                    : null,
                child: const Text('Trang sau'),
              ),
            ],
          ),
          OutlinedButton.icon(
            onPressed: () => transactionForm(transfer: true),
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Chuyển tiền giữa ví'),
          ),
          const Text('Chuyển ví gần đây'),
          for (final t in transfers)
            tile(
              '${t['source']} → ${t['destination']}',
              dateText(t['occurred_at']),
              trailing: Text(money(t['amount'] as int)),
            ),
        ];
      case 2:
        return [
          if (wallets.isEmpty) empty('Bạn chưa có ví.'),
          for (final w in wallets)
            tile(
              w['name'],
              w['archived'] == 1 ? 'Đã lưu trữ' : w['type'],
              icon: Icons.account_balance_wallet,
              trailing: Text(money(w['balance'] as int)),
              onTap: () => walletForm(w),
            ),
        ];
      case 3:
        return [
          for (final c in categories)
            tile(
              c['name'],
              '${c['kind'] == 'INCOME' ? 'Thu nhập' : 'Chi tiêu'}${c['archived'] == 1 ? ' • Đã lưu trữ' : ''}',
              onTap: () => categoryForm(c),
            ),
        ];
      case 4:
        return budgetCards();
      case 5:
        final expense = summary
            .where((r) => r['kind'] == 'EXPENSE' && r['total'] > 0)
            .toList();
        return [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              metric('Tổng thu', total('INCOME'), Colors.teal),
              metric('Tổng chi', total('EXPENSE'), Colors.deepOrange),
            ],
          ),
          const SizedBox(height: 24),
          if (expense.isEmpty)
            empty('Chưa có chi tiêu trong tháng này.')
          else
            SizedBox(
              height: 230,
              child: PieChart(
                PieChartData(
                  sections: [
                    for (int i = 0; i < expense.length; i++)
                      PieChartSectionData(
                        value: (expense[i]['total'] as int).toDouble(),
                        title:
                            '${(expense[i]['total'] * 100 / total('EXPENSE')).round()}%',
                        color: Colors.primaries[i % Colors.primaries.length],
                        radius: 65,
                      ),
                  ],
                  centerSpaceRadius: 45,
                ),
              ),
            ),
          for (int i = 0; i < expense.length; i++)
            tile(
              expense[i]['name'],
              'Chi tiêu',
              trailing: Text(money(expense[i]['total'])),
              icon: Icons.circle,
            ),
          const Text(
            'Chuyển ví và đóng góp tiết kiệm không được tính vào chi tiêu.',
          ),
        ];
      case 6:
        return [
          if (goals.isEmpty) empty('Tạo mục tiêu cho điều bạn đang hướng tới.'),
          for (final g in goals)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      g['name'],
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text('${money(g['saved'])} / ${money(g['target'])}'),
                    if (g['due_date'] != null)
                      Text('Hạn: ${dateText(g['due_date'])}'),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: ((g['saved'] as int) / (g['target'] as int)).clamp(
                        0,
                        1,
                      ),
                    ),
                    TextButton(
                      onPressed: () => contributionForm(g),
                      child: const Text('Đóng góp từ ví'),
                    ),
                  ],
                ),
              ),
            ),
          const Text('Lịch sử đóng góp'),
          for (final c in contributions)
            tile(
              c['goal'],
              '${c['wallet']} • ${dateText(c['occurred_at'])}',
              trailing: Text(money(c['amount'])),
            ),
        ];
      default:
        return [
          tile(
            'Nhắc ngân sách trên thiết bị',
            alertError ??
                (alertsEnabled
                    ? 'Đang bật • Nhắc khi đạt 80% và 100% ngân sách'
                    : 'Đang tắt • Nhấn để cấp quyền và bật nhắc nhở'),
            icon: Icons.notifications_outlined,
            onTap: toggleAlerts,
          ),
          tile(
            'SmartSpend - Personal Finance Management',
            'Phiên bản 1.0 • Flutter / Dart\nDữ liệu SQLite trên thiết bị • Tiền tệ VND',
            icon: Icons.info_outline,
          ),
          tile(
            'Xuất giao dịch CSV',
            'Chia sẻ toàn bộ lịch sử thu / chi',
            icon: Icons.ios_share,
            onTap: export,
          ),
          tile(
            'Lưu ý dữ liệu',
            'Gỡ ứng dụng hoặc mất thiết bị có thể làm mất dữ liệu. Hãy xuất CSV định kỳ.',
            icon: Icons.storage,
          ),
        ];
    }
  }

  String dateText(dynamic millis) {
    final d = DateTime.fromMillisecondsSinceEpoch(millis as int);
    return '${d.day}/${d.month}/${d.year}';
  }

  List<Widget> transactionCards(List<DataRowMap> rows) => rows.isEmpty
      ? [empty('Chưa có giao dịch. Nhấn + để ghi khoản đầu tiên.')]
      : [
          for (final t in rows)
            tile(
              t['category'],
              '${t['wallet']} • ${dateText(t['occurred_at'])}\n${t['note']}',
              trailing: Text(
                '${t['kind'] == 'INCOME' ? '+' : '-'}${money(t['amount'])}',
                style: TextStyle(
                  color: t['kind'] == 'INCOME'
                      ? Colors.teal
                      : Colors.deepOrange,
                ),
              ),
              onTap: () => transactionForm(existing: t),
            ),
        ];
  List<Widget> budgetCards() => budgets.isEmpty
      ? [empty('Chưa có ngân sách cho tháng này.')]
      : [
          for (final b in budgets)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            b['name'],
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          onPressed: () => budgetForm(b),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      ],
                    ),
                    Text('${money(b['spent'])} / ${money(b['amount'])}'),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: ((b['spent'] as int) / (b['amount'] as int)).clamp(
                        0,
                        1,
                      ),
                      color: b['spent'] >= b['amount']
                          ? Colors.red
                          : Colors.teal,
                    ),
                    if (b['spent'] * 100 >= b['amount'] * 80)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          b['spent'] >= b['amount']
                              ? 'Đã đạt / vượt ngân sách'
                              : 'Đã sử dụng ít nhất 80% ngân sách',
                          style: const TextStyle(color: Colors.deepOrange),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ];
  void openAdd() {
    switch (page) {
      case 2:
        walletForm();
      case 3:
        categoryForm();
      case 4:
        budgetForm();
      case 6:
        goalForm();
      default:
        transactionForm();
    }
  }

  Future<void> form(
    String title,
    Map<String, String> values,
    Map<String, Map<String, String>> choices,
    Future<void> Function(Map<String, String>) save, {
    Future<void> Function()? remove,
    bool withDate = false,
  }) async {
    final controllers = {
      for (final e in values.entries)
        e.key: TextEditingController(
          text:
              [
                'Số tiền',
                'Số dư ban đầu',
                'Hạn mức',
                'Mục tiêu',
              ].contains(e.key)
              ? formatVndInput(e.value.replaceAll('.', ''))
              : e.value,
        ),
    };
    final selected = {
      for (final e in choices.entries) e.key: e.value.keys.firstOrNull,
    };
    String? message;
    bool busy = false;
    DateTime date = DateTime.tryParse(values['_date'] ?? '') ?? DateTime.now();
    final route = DialogRoute<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final e in controllers.entries)
                    if (!e.key.startsWith('_'))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: TextField(
                          controller: e.value,
                          inputFormatters:
                              [
                                'Số tiền',
                                'Số dư ban đầu',
                                'Hạn mức',
                                'Mục tiêu',
                              ].contains(e.key)
                              ? [const VndInputFormatter()]
                              : null,
                          keyboardType:
                              [
                                'Số tiền',
                                'Số dư ban đầu',
                                'Hạn mức',
                                'Mục tiêu',
                              ].contains(e.key)
                              ? TextInputType.number
                              : TextInputType.text,
                          decoration: InputDecoration(labelText: e.key),
                        ),
                      ),
                  for (final e in choices.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: DropdownButtonFormField<String>(
                        initialValue: selected[e.key],
                        isExpanded: true,
                        decoration: InputDecoration(labelText: e.key),
                        items: [
                          for (final v in e.value.entries)
                            DropdownMenuItem(
                              value: v.key,
                              child: Text(v.value),
                            ),
                        ],
                        onChanged: busy ? null : (v) => selected[e.key] = v,
                      ),
                    ),
                  if (withDate)
                    TextButton.icon(
                      onPressed: busy
                          ? null
                          : () async {
                              final d = await showDatePicker(
                                context: ctx,
                                initialDate: date,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (d != null) update(() => date = d);
                            },
                      icon: const Icon(Icons.calendar_month),
                      label: Text(
                        'Ngày: ${date.day}/${date.month}/${date.year}',
                      ),
                    ),
                  if (message != null)
                    Text(message!, style: const TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ),
          actions: [
            if (remove != null)
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        final yes = await showDialog<bool>(
                          context: ctx,
                          builder: (c) => AlertDialog(
                            title: const Text('Xác nhận thao tác'),
                            content: const Text(
                              'Bạn muốn xóa giao dịch hoặc lưu trữ mục này?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(c, false),
                                child: const Text('Hủy'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(c, true),
                                child: const Text('Xác nhận'),
                              ),
                            ],
                          ),
                        );
                        if (yes != true) return;
                        update(() => busy = true);
                        try {
                          await remove();
                          if (ctx.mounted) Navigator.pop(ctx);
                          await load();
                        } catch (e) {
                          update(() {
                            busy = false;
                            message = e.toString();
                          });
                        }
                      },
                child: const Text('Xóa / Lưu trữ'),
              ),
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      update(() => busy = true);
                      try {
                        await save({
                          for (final e in controllers.entries)
                            e.key: e.value.text,
                          for (final e in selected.entries)
                            e.key: e.value ?? '',
                          '_date': date.toIso8601String(),
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                        await load();
                      } catch (e) {
                        update(() {
                          busy = false;
                          message = e.toString().replaceFirst(
                            'Exception: ',
                            '',
                          );
                        });
                      }
                    },
              child: Text(busy ? 'Đang lưu…' : 'Lưu'),
            ),
          ],
        ),
      ),
    );
    await Navigator.of(context).push(route);
    await route.completed;
    for (final c in controllers.values) {
      c.dispose();
    }
  }

  Map<String, String> walletChoices() => {
    for (final w in wallets.where((w) => w['archived'] == 0))
      w['id']: w['name'],
  };
  Future<void> walletForm([DataRowMap? w]) => form(
    w == null ? 'Tạo ví' : 'Chỉnh sửa ví',
    {'Tên ví': w?['name'] ?? '', if (w == null) 'Số dư ban đầu': '4.000.000'},
    {
      'Loại ví': {
        'cash': 'Tiền mặt',
        'bank': 'Ngân hàng',
        'ewallet': 'Ví điện tử',
      },
    },
    (v) async {
      final opening = w == null
          ? parseMoney(v['Số dư ban đầu']!, allowZero: true)
          : 0;
      if (opening < 0) {
        throw Exception('Số dư ban đầu phải là số nguyên không âm.');
      }
      await repo.wallet(v['Tên ví']!, v['Loại ví']!, opening, id: w?['id']);
    },
    remove: w == null ? null : () => repo.archive('wallets', w['id']),
  );
  Future<void> categoryForm([DataRowMap? c]) => form(
    'Danh mục',
    {'Tên danh mục': c?['name'] ?? ''},
    {
      if (c == null) 'Loại': {'EXPENSE': 'Chi tiêu', 'INCOME': 'Thu nhập'},
    },
    (v) => repo.category(
      v['Tên danh mục']!,
      c?['kind'] ?? v['Loại']!,
      id: c?['id'],
    ),
    remove: c == null ? null : () => repo.archive('categories', c['id']),
  );
  Future<void> transactionForm({
    bool transfer = false,
    DataRowMap? existing,
  }) async {
    if (walletChoices().isEmpty) {
      await walletForm();
      return;
    }
    if (transfer) {
      await form(
        'Chuyển tiền',
        {'Số tiền': '', 'Ghi chú': ''},
        {'Ví nguồn': walletChoices(), 'Ví đích': walletChoices()},
        (v) => repo.transfer(
          v['Ví nguồn']!,
          v['Ví đích']!,
          parseMoney(v['Số tiền']!),
          v['Ghi chú']!,
          DateTime.parse(v['_date']!),
        ),
        withDate: true,
      );
      return;
    }
    String? kind = existing?['kind'];
    kind ??= await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Ghi giao dịch'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, 'EXPENSE'),
            child: const Text('Chi tiêu'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, 'INCOME'),
            child: const Text('Thu nhập'),
          ),
        ],
      ),
    );
    if (kind == null) return;
    final cs = {
      for (final c in categories.where(
        (c) => c['kind'] == kind && c['archived'] == 0,
      ))
        c['id'] as String: c['name'] as String,
    };
    // Preserve the current selections when editing; archived entries remain unavailable.
    Map<String, String> first(Map<String, String> values, String? id) => {
      if (id != null && values.containsKey(id)) id: values[id]!,
      ...values,
    };
    if (cs.isEmpty) {
      await categoryForm();
      return;
    }
    await form(
      kind == 'EXPENSE' ? 'Ghi chi tiêu' : 'Ghi thu nhập',
      {
        'Số tiền': existing?['amount'].toString() ?? '',
        'Ghi chú': existing?['note'] ?? '',
        '_date': existing == null
            ? DateTime.now().toIso8601String()
            : DateTime.fromMillisecondsSinceEpoch(existing['occurred_at'])
                  .toIso8601String(),
      },
      {
        'Ví': first(walletChoices(), existing?['wallet_id']),
        'Danh mục': first(cs, existing?['category_id']),
      },
      (v) => repo.saveTransaction(
        id: existing?['id'],
        wallet: v['Ví']!,
        category: v['Danh mục']!,
        kind: kind!,
        amount: parseMoney(v['Số tiền']!),
        note: v['Ghi chú']!,
        date: DateTime.parse(v['_date']!),
      ),
      withDate: true,
      remove: existing == null
          ? null
          : () => repo.deleteTransaction(existing['id']),
    );
  }

  Future<void> budgetForm([DataRowMap? b]) => form(
    'Ngân sách ${month.month}/${month.year}',
    {'Hạn mức': b?['amount'].toString() ?? ''},
    {
      'Danh mục': {
        if (b != null) b['category_id']: b['name'],
        for (final c in categories.where(
          (c) => c['kind'] == 'EXPENSE' && c['archived'] == 0,
        ))
          c['id']: c['name'],
      },
    },
    (v) async {
      if (v['Danh mục']!.isEmpty) throw Exception('Chọn danh mục chi tiêu.');
      await repo.write(
        'INSERT INTO budgets VALUES(?,?,?,?) ON CONFLICT(category_id,period) DO UPDATE SET amount=excluded.amount',
        [newId(), v['Danh mục'], monthKey(month), parseMoney(v['Hạn mức']!)],
      );
    },
  );
  Future<void> goalForm() => form(
    'Mục tiêu tiết kiệm',
    {'Tên mục tiêu': '', 'Mục tiêu': ''},
    {},
    (v) async {
      if (v['Tên mục tiêu']!.trim().isEmpty) {
        throw Exception('Nhập tên mục tiêu.');
      }
      await repo.write('INSERT INTO goals VALUES(?,?,?,?)', [
        newId(),
        v['Tên mục tiêu'],
        parseMoney(v['Mục tiêu']!),
        DateTime.parse(v['_date']!).millisecondsSinceEpoch,
      ]);
    },
    withDate: true,
  );
  Future<void> contributionForm(DataRowMap g) async {
    if (walletChoices().isEmpty) {
      await walletForm();
      return;
    }
    await form(
      'Đóng góp: ${g['name']}',
      {'Số tiền': ''},
      {'Ví': walletChoices()},
      (v) => repo.contribute(g['id'], v['Ví']!, parseMoney(v['Số tiền']!)),
    );
  }

  Future<void> toggleAlerts() => action(() async {
    final rows = await repo.query(
      "SELECT value FROM settings WHERE key='alerts'",
    );
    final enabled = rows.isNotEmpty && rows.first['value'] == '1';
    if (enabled) {
      await repo.write(
        "INSERT OR REPLACE INTO settings VALUES('alerts','0')",
        [],
      );
    } else {
      if (!await alerts.enable()) {
        throw Exception(
          'Chưa được cấp quyền thông báo. Hãy kiểm tra cài đặt thiết bị.',
        );
      }
      await repo.write(
        "INSERT OR REPLACE INTO settings VALUES('alerts','1')",
        [],
      );
    }
  });
  Future<void> export() => action(() async {
    final rows = await repo.query(
      'SELECT t.*,w.name AS wallet,c.name AS category FROM transactions t JOIN wallets w ON w.id=t.wallet_id JOIN categories c ON c.id=t.category_id ORDER BY occurred_at',
    );
    String cell(Object? v) {
      var s = v.toString();
      if (RegExp(r'^[=+@\-\t\r]').hasMatch(s)) s = "'$s";
      return '"${s.replaceAll('"', '""')}"';
    }

    final csv =
        '\uFEFFNgày,Ví,Danh mục,Loại,Số tiền VND,Ghi chú\r\n${rows.map((r) => [dateText(r['occurred_at']), r['wallet'], r['category'], r['kind'], r['amount'], r['note']].map(cell).join(',')).join('\r\n')}';
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            Uint8List.fromList(utf8.encode(csv)),
            mimeType: 'text/csv',
            name: 'smartspend.csv',
          ),
        ],
        fileNameOverrides: ['smartspend.csv'],
      ),
    );
  });
}
