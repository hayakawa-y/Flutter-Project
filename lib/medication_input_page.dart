// lib/medication_input_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'local_store.dart';
import 'notification_service.dart';
import '../modifier/fancy_routes.dart';
import 'medication_list_page.dart';

class MedicationInputPage extends StatefulWidget {
  const MedicationInputPage({super.key, this.docId, this.initial});

  final dynamic docId;
  final Map<String, dynamic>? initial;

  @override
  State<MedicationInputPage> createState() => _MedicationInputPageState();
}

class _MedicationInputPageState extends State<MedicationInputPage> {
  final _form = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _dose = TextEditingController();

  final List<TimeOfDay> _times = [];

  DateTime? _start;
  DateTime? _end;

  bool _saving = false;

  bool _popupEnabled = false; // ✅ 用它作为“到点提醒开关”
  bool _alarmEnabled = false; // 先留着，不用也行

  bool get _isEdit => widget.docId != null;

  @override
  void initState() {
    super.initState();

    final m = widget.initial;
    if (m != null) {
      _name.text = (m['name'] ?? '').toString();
      _dose.text = (m['dose'] ?? '').toString();

      final ts =
          (m['times'] as List?)?.map((e) => e.toString()).toList() ?? const [];
      _times.addAll(ts.map(_parseTime));
      _times.sort((a, b) => (a.hour * 60 + a.minute) - (b.hour * 60 + b.minute));

      _start = _toDate(m['startDate']);
      _end = _toDate(m['endDate']);

      _popupEnabled = m['popupEnabled'] == true;
      _alarmEnabled = m['alarmEnabled'] == true;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _dose.dispose();
    super.dispose();
  }

  DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  TimeOfDay _parseTime(String s) {
    try {
      final p = s.split(':');
      return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
    } catch (_) {
      return const TimeOfDay(hour: 8, minute: 0);
    }
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    if (_saving) return; // ✅ 防重复保存

    if (!_form.currentState!.validate()) return;

    if (_start == null || _end == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select start and end dates')),
      );
      return;
    }

    if (_times.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one time')),
      );
      return;
    }

    if (_end!.isBefore(_start!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End date cannot be earlier than start')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      // ✅ 如果是编辑，先取消旧通知
      final oldNotifIds = (widget.initial?['notifIds'] as List?)
          ?.map((e) => int.tryParse(e.toString()) ?? -1)
          .where((x) => x >= 0)
          .toList() ??
          const <int>[];
      if (oldNotifIds.isNotEmpty) {
        await NotificationService.cancelMany(oldNotifIds);
      }

      // 先写一份（notifIds 后面再补）
      final data = <String, dynamic>{
        'name': _name.text.trim(),
        'dose': _dose.text.trim(),
        'times': _times.map(_fmtTime).toList(),
        'startDate': _start!.millisecondsSinceEpoch,
        'endDate': _end!.millisecondsSinceEpoch,
        'popupEnabled': _popupEnabled,
        'alarmEnabled': _alarmEnabled,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };

      // ✅ 保存并拿到 key（新增会返回新 key）
      final key = await LocalStore.upsertMed(key: widget.docId, data: data);

      // ✅ 如果开了提醒：排本地通知（失败也不影响保存）
      List<int> notifIds = [];
      if (_popupEnabled) {
        try {
          final title = 'Medication Reminder';
          final body = _dose.text.trim().isEmpty
              ? 'Time to take ${_name.text.trim()}'
              : 'Take ${_name.text.trim()}  (${_dose.text.trim()})';

          final timesInDay = _times
              .map((t) => DateTime(2000, 1, 1, t.hour, t.minute))
              .toList();

          // baseId：用 hive key 的 hash 做个稳定 int
          final baseId = key.hashCode.abs() % 1000000;

          notifIds = await NotificationService.scheduleMedication(
            baseId: baseId,
            title: title,
            body: body,
            startDate: _start!,
            endDate: _end!,
            timesInDay: timesInDay,
          );
        } catch (_) {
          // 忽略提醒错误，保存仍成功
        }
      }

      // ✅ 把 notifIds 写回去（方便下次编辑/删除取消）
      final merged = Map<String, dynamic>.from(data);
      merged['notifIds'] = notifIds;
      await LocalStore.upsertMed(key: key, data: merged);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Medication saved ✅')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _times.isNotEmpty ? _times.last : const TimeOfDay(hour: 8, minute: 0),
    );
    if (t == null) return;

    final exists = _times.any((x) => x.hour == t.hour && x.minute == t.minute);
    if (exists) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This time already exists')),
      );
      return;
    }

    setState(() {
      _times.add(t);
      _times.sort((a, b) => (a.hour * 60 + a.minute) - (b.hour * 60 + b.minute));
    });
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _start ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (d == null) return;

    setState(() {
      _start = DateTime(d.year, d.month, d.day);
      if (_end != null && _end!.isBefore(_start!)) _end = _start;
    });
  }

  Future<void> _pickEndDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _end ?? (_start ?? now),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (d == null) return;

    final picked = DateTime(d.year, d.month, d.day);
    if (_start != null && picked.isBefore(_start!)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End date cannot be earlier than start')),
      );
      return;
    }

    setState(() => _end = picked);
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd');

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Medication' : 'Add Medication'),
        actions: [
          IconButton(
            tooltip: 'View list',
            icon: const Icon(Icons.list),
            onPressed: () => pushFadeScale(context, const MedicationListPage()),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Icon(Icons.check),
            label: Text(_saving ? 'Saving...' : 'Save'),
          ),
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Medicine Name *'),
              validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Enter medicine name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _dose,
              decoration: const InputDecoration(labelText: 'Dose (optional)'),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: const Icon(Icons.access_time),
              label: const Text('Add Time'),
              onPressed: _pickTime,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: -6,
              children: _times.isEmpty
                  ? const [Text('No times yet')]
                  : _times
                  .map(
                    (t) => InputChip(
                  label: Text(_fmtTime(t)),
                  onDeleted: () => setState(() => _times.remove(t)),
                ),
              )
                  .toList(),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today),
                    label:
                    Text(_start == null ? 'Start Date' : df.format(_start!)),
                    onPressed: _pickStartDate,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event),
                    label: Text(_end == null ? 'End Date' : df.format(_end!)),
                    onPressed: _pickEndDate,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ✅ 你要的“到点弹窗提醒”就用这个开关
            SwitchListTile(
              title: const Text('Popup Reminder'),
              value: _popupEnabled,
              onChanged: (v) => setState(() => _popupEnabled = v),
            ),

            // 先留着，不影响
            SwitchListTile(
              title: const Text('Alarm Reminder'),
              value: _alarmEnabled,
              onChanged: (v) => setState(() => _alarmEnabled = v),
            ),
          ],
        ),
      ),
    );
  }
}