// lib/health_record_list_page.dart
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'local_store.dart';

class HealthRecordListPage extends StatelessWidget {
  const HealthRecordListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final box = LocalStore.healthBox;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Health History'),
        actions: [
          IconButton(
            tooltip: 'Clear all',
            icon: const Icon(Icons.delete_forever_rounded),
            onPressed: () async {
              await box.clear();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cleared ✅')),
                );
              }
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<Box<Map>>(
        valueListenable: box.listenable(),
        builder: (context, _, __) {
          final list = LocalStore.getAllHealthRecordsDesc();
          if (list.isEmpty) {
            return const Center(child: Text('No records yet'));
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final m = list[i];

              // 更容错：ts 可能是 int / num / String
              final tsRaw = m['ts'];
              final ts = tsRaw is int
                  ? tsRaw
                  : tsRaw is num
                  ? tsRaw.toInt()
                  : int.tryParse(tsRaw?.toString() ?? '0') ?? 0;

              final dt = DateTime.fromMillisecondsSinceEpoch(ts);

              return Card(
                child: ListTile(
                  title: Text(
                    '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
                        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    'BP: ${m['systolic']}/${m['diastolic']}  •  W: ${m['weight']}kg  •  BMI: ${m['bmi']}',
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}