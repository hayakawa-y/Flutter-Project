// lib/medication_list_page.dart
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../modifier/fancy_routes.dart';
import 'local_store.dart';
import 'medication_input_page.dart';
import 'notification_service.dart'; // ✅ 新增：删除时取消通知

class MedicationListPage extends StatelessWidget {
  const MedicationListPage({super.key});

  DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '--';
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  /// ✅ 直接从 medsBox 读取并排序
  List<Map<String, dynamic>> _readAllSorted(Box<Map> box) {
    final out = <Map<String, dynamic>>[];

    for (final k in box.keys) {
      final v = box.get(k);
      if (v == null) continue;

      final m = Map<String, dynamic>.from(v);
      m['_key'] = k; // 保留 hive key
      out.add(m);
    }

    int sd(Map<String, dynamic> m) => (m['startDate'] ?? 0) as int;
    out.sort((a, b) => sd(b).compareTo(sd(a)));
    return out;
  }

  /// ✅ 取出该药物保存的 notifIds
  List<int> _readNotifIds(Map<String, dynamic> data) {
    final raw = data['notifIds'];
    if (raw is! List) return const <int>[];
    return raw
        .map((e) => int.tryParse(e.toString()) ?? -1)
        .where((x) => x >= 0)
        .toList();
  }

  Future<bool> _confirmDelete(BuildContext context, String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete medication?'),
        content: Text('This will remove “$title”.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// ✅ 删除统一入口：先取消通知，再删数据
  Future<void> _deleteOne(
      BuildContext context, {
        required dynamic key,
        required Map<String, dynamic> data,
        required String title,
      }) async {
    try {
      final ids = _readNotifIds(data);
      if (ids.isNotEmpty) {
        await NotificationService.cancelMany(ids);
      }
      await LocalStore.deleteMed(key);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted: $title')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final box = LocalStore.medsBox;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Medications'),
        actions: [
          IconButton(
            tooltip: 'Add',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => pushFadeScale(context, const MedicationInputPage()),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => pushFadeScale(context, const MedicationInputPage()),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: ValueListenableBuilder(
        valueListenable: box.listenable(),
        builder: (context, Box<Map> b, _) {
          final items = _readAllSorted(b);

          if (items.isEmpty) {
            return _EmptyState(
              onAdd: () => pushFadeScale(context, const MedicationInputPage()),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final data = items[i];
              final key = data['_key'];

              final name = (data['name'] ?? '').toString();
              final dose = (data['dose'] ?? '').toString();

              final times = (data['times'] is List)
                  ? (data['times'] as List).map((e) => e.toString()).toList()
                  : const <String>[];

              final timesStr = times.isEmpty ? '—' : times.join(', ');
              final start = _toDate(data['startDate']);
              final end = _toDate(data['endDate']);
              final title = dose.isNotEmpty ? '$name ($dose)' : name;

              return Dismissible(
                key: ValueKey(key),
                direction: DismissDirection.endToStart,
                background: _DismissBg(),
                confirmDismiss: (_) => _confirmDelete(context, title),
                onDismissed: (_) async {
                  await _deleteOne(
                    context,
                    key: key,
                    data: data,
                    title: title,
                  );
                },
                child: _MedCard(
                  title: title,
                  times: timesStr,
                  start: _fmtDate(start),
                  end: _fmtDate(end),
                  onTap: () => pushFadeScale(
                    context,
                    MedicationInputPage(
                      docId: key,
                      initial: data,
                    ),
                  ),
                  onDelete: () async {
                    final ok = await _confirmDelete(context, title);
                    if (!ok) return;

                    await _deleteOne(
                      context,
                      key: key,
                      data: data,
                      title: title,
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _DismissBg extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Icon(
        Icons.delete_forever_rounded,
        color: Colors.red,
        size: 28,
      ),
    );
  }
}

class _MedCard extends StatelessWidget {
  const _MedCard({
    required this.title,
    required this.times,
    required this.start,
    required this.end,
    required this.onTap,
    required this.onDelete,
  });

  final String title;
  final String times;
  final String start;
  final String end;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          color: cs.secondaryContainer.withOpacity(.35),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant.withOpacity(.4)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Icon(Icons.vaccines_rounded, color: cs.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(
                      'Times: $times',
                      style:
                      TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Start: $start   End: $end',
                      style:
                      TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_rounded, color: Colors.red),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.medication_liquid_outlined, color: cs.primary, size: 48),
            const SizedBox(height: 12),
            const Text('No medications yet',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'Tap the button below to add your first medication.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add Medication'),
            ),
          ],
        ),
      ),
    );
  }
}