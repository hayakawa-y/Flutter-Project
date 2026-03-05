// lib/health_analytics_page.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'local_store.dart';

class HealthAnalyticsPage extends StatefulWidget {
  const HealthAnalyticsPage({super.key});

  @override
  State<HealthAnalyticsPage> createState() => _HealthAnalyticsPageState();
}

class _HealthAnalyticsPageState extends State<HealthAnalyticsPage> {
  final GlobalKey _captureKey = GlobalKey();
  bool _sharing = false;

  Future<void> _shareChart() async {
    if (_sharing) return;
    setState(() => _sharing = true);

    try {
      final ctx = _captureKey.currentContext;
      if (ctx == null) throw Exception('Capture area not ready');

      final renderObject = ctx.findRenderObject();
      if (renderObject == null || renderObject is! RenderRepaintBoundary) {
        throw Exception('RenderRepaintBoundary not found');
      }

      // 截图
      final ui.Image image = await renderObject.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Failed to encode image');

      final Uint8List pngBytes = byteData.buffer.asUint8List();

      // 写入临时文件
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/health_analytics_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(pngBytes, flush: true);

      // 调起系统分享
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'My Health Analytics Report',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Share failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final records = LocalStore.getAllHealthRecordsDesc();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Health Analytics'),
        actions: [
          IconButton(
            tooltip: 'Share chart',
            onPressed: records.isEmpty || _sharing ? null : _shareChart,
            icon: _sharing
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Icon(Icons.share),
          ),
        ],
      ),
      body: records.isEmpty
          ? const Center(child: Text('No data available'))
          : Padding(
        padding: const EdgeInsets.all(16),
        child: RepaintBoundary(
          key: _captureKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('BMI Trend'),
                const SizedBox(height: 12),
                _bmiChart(records),
                const SizedBox(height: 32),
                _sectionTitle('Blood Pressure Trend'),
                const SizedBox(height: 12),
                _bpChart(records),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  /// BMI 图
  Widget _bmiChart(List<Map<String, dynamic>> records) {
    final sorted = [...records]
      ..sort((a, b) => (a['ts'] as int).compareTo(b['ts'] as int));

    final spots = <FlSpot>[];
    for (int i = 0; i < sorted.length; i++) {
      final bmi = (sorted[i]['bmi'] ?? 0).toDouble();
      spots.add(FlSpot(i.toDouble(), bmi));
    }

    return SizedBox(
      height: 260,
      child: LineChart(
        LineChartData(
          minY: 10,
          maxY: 40,
          gridData: const FlGridData(show: true),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: true),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= sorted.length) {
                    return const SizedBox.shrink();
                  }
                  final ts = sorted[index]['ts'] as int;
                  final dt = DateTime.fromMillisecondsSinceEpoch(ts);
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      DateFormat('MM/dd').format(dt),
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: true),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: Colors.blue,
              barWidth: 3,
              dotData: const FlDotData(show: true),
            ),
          ],
        ),
      ),
    );
  }

  /// 血压图
  Widget _bpChart(List<Map<String, dynamic>> records) {
    final sorted = [...records]
      ..sort((a, b) => (a['ts'] as int).compareTo(b['ts'] as int));

    final sysSpots = <FlSpot>[];
    final diaSpots = <FlSpot>[];

    for (int i = 0; i < sorted.length; i++) {
      final sys = (sorted[i]['systolic'] ?? 0).toDouble();
      final dia = (sorted[i]['diastolic'] ?? 0).toDouble();
      sysSpots.add(FlSpot(i.toDouble(), sys));
      diaSpots.add(FlSpot(i.toDouble(), dia));
    }

    return SizedBox(
      height: 260,
      child: LineChart(
        LineChartData(
          minY: 40,
          maxY: 200,
          gridData: const FlGridData(show: true),
          titlesData: const FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true),
            ),
          ),
          borderData: FlBorderData(show: true),
          lineBarsData: [
            LineChartBarData(
              spots: sysSpots,
              isCurved: true,
              color: Colors.red,
              barWidth: 3,
              dotData: const FlDotData(show: true),
            ),
            LineChartBarData(
              spots: diaSpots,
              isCurved: true,
              color: Colors.green,
              barWidth: 3,
              dotData: const FlDotData(show: true),
            ),
          ],
        ),
      ),
    );
  }
}