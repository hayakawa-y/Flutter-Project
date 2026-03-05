// lib/health_context_provider.dart
import 'dart:math' as math;
import 'package:intl/intl.dart';

import 'local_store.dart';

class HealthContextProvider {
  /// Build context for last [days].
  Future<AiHealthContext> build({int days = 30}) async {
    final now = DateTime.now();
    final from = now.subtract(Duration(days: days));

    // Pull all records (desc) then filter window and sort asc for trends.
    final allDesc = LocalStore.getAllHealthRecordsDesc();
    if (allDesc.isEmpty) {
      return AiHealthContext.empty(reason: 'No local records found.');
    }

    final inRange = <Map<String, dynamic>>[];
    for (final m in allDesc) {
      final ts = _asDateTime(m['ts']);
      if (ts == null) continue;
      if (ts.isBefore(from) || ts.isAfter(now)) continue;
      inRange.add(m);
    }

    if (inRange.isEmpty) {
      return AiHealthContext.empty(reason: 'No local records in this time window.');
    }

    // sort asc by time
    inRange.sort((a, b) {
      final ta = (a['ts'] as int?) ?? 0;
      final tb = (b['ts'] as int?) ?? 0;
      return ta.compareTo(tb);
    });

    // Build series
    final systolic = <_Pt>[];
    final diastolic = <_Pt>[];
    final weight = <_Pt>[];
    final bmi = <_Pt>[];

    for (final m in inRange) {
      final ts = _asDateTime(m['ts']);
      if (ts == null) continue;

      final sys = _toDouble(m['systolic']);
      final dia = _toDouble(m['diastolic']);
      final w = _toDouble(m['weight']);
      final b = _toDouble(m['bmi']);

      if (sys != null) systolic.add(_Pt(ts, sys));
      if (dia != null) diastolic.add(_Pt(ts, dia));
      if (w != null) weight.add(_Pt(ts, w));
      if (b != null) bmi.add(_Pt(ts, b));
    }

    // Reduce to daily average
    List<_Pt> rd(List<_Pt> src) {
      final map = <DateTime, List<double>>{};
      for (final p in src) {
        final day = DateTime(p.t.year, p.t.month, p.t.day);
        map.putIfAbsent(day, () => []).add(p.v);
      }
      final out = <_Pt>[];
      final entries = map.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      for (final e in entries) {
        final avg = e.value.reduce((a, b) => a + b) / e.value.length;
        out.add(_Pt(e.key, avg));
      }
      return out;
    }

    final systolicD = rd(systolic);
    final diastolicD = rd(diastolic);
    final weightD = rd(weight);
    final bmiD = rd(bmi);

    double? last(List<_Pt> l) => l.isEmpty ? null : l.last.v;
    DateTime? lastTs(List<_Pt> l) => l.isEmpty ? null : l.last.t;

    double? avg(List<_Pt> l) =>
        l.isEmpty ? null : l.map((e) => e.v).reduce((a, b) => a + b) / l.length;

    String? trend(List<_Pt> l) {
      if (l.length < 2) return null;
      final first = l.first.v;
      final lastV = l.last.v;
      final diff = lastV - first;
      if (diff.abs() < 1e-6) return 'flat';
      final dir = diff > 0 ? 'up' : 'down';
      final pct = (first.abs() < 1e-9) ? null : (diff / first) * 100;
      final pctStr = pct == null ? '' : ' (${pct.toStringAsFixed(1)}%)';
      return '$dir by ${diff.toStringAsFixed(1)}$pctStr';
    }

    String fmtD(double? v, {int d = 1}) =>
        v == null ? '-' : (v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(d));

    final summary = AiHealthSummary(
      windowDays: days,
      latestSystolic: last(systolicD),
      latestDiastolic: last(diastolicD),
      latestWeightKg: last(weightD),
      latestBmi: last(bmiD),
      avgSystolic: avg(systolicD),
      avgDiastolic: avg(diastolicD),
      avgWeightKg: avg(weightD),
      avgBmi: avg(bmiD),
      lastBpAt: _maxDate(lastTs(systolicD), lastTs(diastolicD)),
      lastWeightAt: lastTs(weightD),
      lastBmiAt: lastTs(bmiD),
      trendSys: trend(systolicD),
      trendDia: trend(diastolicD),
      trendWeight: trend(weightD),
      trendBmi: trend(bmiD),
      points: {
        'systolic': systolicD.length,
        'diastolic': diastolicD.length,
        'weight': weightD.length,
        'bmi': bmiD.length,
      },
    );

    // Craft compact English context for LLM
    final f = DateFormat('yyyy-MM-dd');
    final sb = StringBuffer()
      ..writeln("You are given the user's recent health metrics from local logs for the last ${days} days:")
      ..writeln(
        '- Latest BP: ${fmtD(summary.latestSystolic)}/${fmtD(summary.latestDiastolic)} mmHg'
            '${summary.lastBpAt != null ? " (as of ${f.format(summary.lastBpAt!)})" : ""}.'
            ' Avg BP: ${fmtD(summary.avgSystolic)}/${fmtD(summary.avgDiastolic)}.'
            '${summary.trendSys != null || summary.trendDia != null ? " BP trend: sys ${summary.trendSys ?? "n/a"}, dia ${summary.trendDia ?? "n/a"}." : ""}',
      )
      ..writeln(
        '- Latest weight: ${fmtD(summary.latestWeightKg)} kg'
            '${summary.lastWeightAt != null ? " (as of ${f.format(summary.lastWeightAt!)})" : ""}.'
            ' Avg weight: ${fmtD(summary.avgWeightKg)}.'
            '${summary.trendWeight != null ? " Weight trend: ${summary.trendWeight}." : ""}',
      )
      ..writeln(
        '- Latest BMI: ${fmtD(summary.latestBmi)}'
            '${summary.lastBmiAt != null ? " (as of ${f.format(summary.lastBmiAt!)})" : ""}.'
            ' Avg BMI: ${fmtD(summary.avgBmi)}.'
            '${summary.trendBmi != null ? " BMI trend: ${summary.trendBmi}." : ""}',
      )
      ..writeln(
        '- Data points → BP(systolic/diastolic): ${summary.points['systolic']}/${summary.points['diastolic']}, '
            'Weight: ${summary.points['weight']}, BMI: ${summary.points['bmi']}.',
      )
      ..writeln(
        'Use these facts to personalize your advice. If something is missing, ask brief clarifying questions.',
      );

    return AiHealthContext(summary: summary, contextText: sb.toString());
  }
}

/// Result object to feed AI.
class AiHealthContext {
  final AiHealthSummary summary;
  final String contextText;
  final bool ok;
  final String? note;

  AiHealthContext({required this.summary, required this.contextText})
      : ok = true,
        note = null;

  AiHealthContext.empty({String? reason})
      : summary = AiHealthSummary.empty(),
        contextText = 'No health context available.',
        ok = false,
        note = reason;
}

class AiHealthSummary {
  final int windowDays;

  final double? latestSystolic;
  final double? latestDiastolic;
  final double? latestWeightKg;
  final double? latestBmi;

  final double? avgSystolic;
  final double? avgDiastolic;
  final double? avgWeightKg;
  final double? avgBmi;

  final DateTime? lastBpAt;
  final DateTime? lastWeightAt;
  final DateTime? lastBmiAt;

  final String? trendSys;
  final String? trendDia;
  final String? trendWeight;
  final String? trendBmi;

  final Map<String, int> points;

  AiHealthSummary({
    required this.windowDays,
    required this.latestSystolic,
    required this.latestDiastolic,
    required this.latestWeightKg,
    required this.latestBmi,
    required this.avgSystolic,
    required this.avgDiastolic,
    required this.avgWeightKg,
    required this.avgBmi,
    required this.lastBpAt,
    required this.lastWeightAt,
    required this.lastBmiAt,
    required this.trendSys,
    required this.trendDia,
    required this.trendWeight,
    required this.trendBmi,
    required this.points,
  });

  AiHealthSummary.empty()
      : windowDays = 0,
        latestSystolic = null,
        latestDiastolic = null,
        latestWeightKg = null,
        latestBmi = null,
        avgSystolic = null,
        avgDiastolic = null,
        avgWeightKg = null,
        avgBmi = null,
        lastBpAt = null,
        lastWeightAt = null,
        lastBmiAt = null,
        trendSys = null,
        trendDia = null,
        trendWeight = null,
        trendBmi = null,
        points = const {};
}

/// ---------- helpers ----------
class _Pt {
  _Pt(this.t, this.v);
  final DateTime t;
  final double v;
}

double? _toDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

DateTime? _asDateTime(dynamic v) {
  if (v == null) return null;
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}

DateTime? _maxDate(DateTime? a, DateTime? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a.isAfter(b) ? a : b;
}