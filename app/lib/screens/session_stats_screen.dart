import 'dart:io';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../services/bluetooth_service.dart';

enum StatsTimeWindow { last30Seconds, last2Minutes, fullSession }

class SessionStatsScreen extends StatefulWidget {
  const SessionStatsScreen({super.key});

  @override
  State<SessionStatsScreen> createState() => _SessionStatsScreenState();
}

class _SessionStatsScreenState extends State<SessionStatsScreen> {
  StatsTimeWindow _selectedWindow = StatsTimeWindow.last2Minutes;
  bool _isExporting = false;

  Duration? _durationForWindow(StatsTimeWindow window) {
    switch (window) {
      case StatsTimeWindow.last30Seconds:
        return const Duration(seconds: 30);
      case StatsTimeWindow.last2Minutes:
        return const Duration(minutes: 2);
      case StatsTimeWindow.fullSession:
        return null;
    }
  }

  String _windowLabel(StatsTimeWindow window) {
    switch (window) {
      case StatsTimeWindow.last30Seconds:
        return 'Last 30s';
      case StatsTimeWindow.last2Minutes:
        return 'Last 2m';
      case StatsTimeWindow.fullSession:
        return 'Full Session';
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds.toString().padLeft(2, '0')}s';
    }

    return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  }

  String _formatTimestamp(DateTime dateTime) {
    final y = dateTime.year.toString().padLeft(4, '0');
    final mo = dateTime.month.toString().padLeft(2, '0');
    final d = dateTime.day.toString().padLeft(2, '0');
    final h = dateTime.hour.toString().padLeft(2, '0');
    final mi = dateTime.minute.toString().padLeft(2, '0');
    final s = dateTime.second.toString().padLeft(2, '0');
    final ms = dateTime.millisecond.toString().padLeft(3, '0');
    return '$y-$mo-$d $h:$mi:$s.$ms';
  }

  String _buildCsv({
    required BluetoothHandler bleData,
    required List<AngleSample> samples,
    required String windowLabel,
  }) {
    final csv = StringBuffer();

    csv.writeln('window,$windowLabel');
    csv.writeln('exported_at,${DateTime.now().toIso8601String()}');
    csv.writeln(
        'session_duration_seconds,${bleData.sessionDuration.inSeconds}');
    csv.writeln('total_steps,${bleData.totalSteps}');
    csv.writeln('good_steps,${bleData.goodSteps}');
    csv.writeln('bad_steps,${bleData.badSteps}');
    csv.writeln('stability_score,${bleData.stabilityScore.toStringAsFixed(2)}');
    csv.writeln('last_classification,${bleData.lastClassification}');
    csv.writeln(
        'last_assistance_percent,${bleData.lastAssistance.toStringAsFixed(2)}');
    csv.writeln(
      'last_toe_clearance_mm,${bleData.lastToeClearanceMm.toStringAsFixed(2)}');
    csv.writeln('last_cadence_spm,${bleData.lastCadenceSpm.toStringAsFixed(2)}');
    csv.writeln('last_gait_phase,${bleData.lastGaitPhase}');
    csv.writeln('last_activity_class,${bleData.lastActivityClass}');
    csv.writeln('last_intention_class,${bleData.lastIntentionClass}');
    csv.writeln('last_model_score,${bleData.lastModelScore.toStringAsFixed(4)}');
    csv.writeln('last_anomaly_strength,${bleData.lastAnomalyStrength.toStringAsFixed(4)}');
    csv.writeln(
      'model_confidence_percent,${(bleData.lastModelConfidence * 100).toStringAsFixed(2)}');
    csv.writeln('');
    csv.writeln('index,timestamp,angle_deg');

    for (var i = 0; i < samples.length; i++) {
      final sample = samples[i];
      csv.writeln(
          '$i,${sample.timestamp.toIso8601String()},${sample.angle.toStringAsFixed(2)}');
    }

    return csv.toString();
  }

  Future<void> _exportCsv(
      BluetoothHandler bleData, List<AngleSample> samples) async {
    if (_isExporting) {
      return;
    }

    if (samples.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No samples available for export yet.')),
      );
      return;
    }

    setState(() {
      _isExporting = true;
    });

    try {
      final csv = _buildCsv(
        bleData: bleData,
        samples: samples,
        windowLabel: _windowLabel(_selectedWindow),
      );

      await Clipboard.setData(ClipboardData(text: csv));

      String resultMessage = 'CSV copied to clipboard.';
      if (!kIsWeb) {
        final directory = await getTemporaryDirectory();
        final fileName =
            'exometrix_stats_${DateTime.now().millisecondsSinceEpoch}.csv';
        final file =
            File('${directory.path}${Platform.pathSeparator}$fileName');
        await file.writeAsString(csv, flush: true);
        resultMessage = 'CSV saved to ${file.path} and copied to clipboard.';
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(resultMessage)),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV export failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bleData = context.watch<BluetoothHandler>();
    final samples = bleData.samplesWithin(_durationForWindow(_selectedWindow));

    final spots = samples
        .asMap()
        .entries
        .map((entry) => FlSpot(entry.key.toDouble(), entry.value.angle))
        .toList(growable: false);

    final angles =
        samples.map((sample) => sample.angle).toList(growable: false);
    final avgAngle = angles.isEmpty
        ? 0.0
        : angles.reduce((sum, angle) => sum + angle) / angles.length;
    final minAngle = angles.isEmpty ? 0.0 : angles.reduce(math.min);
    final maxAngle = angles.isEmpty ? 0.0 : angles.reduce(math.max);
    final spreadAngle = maxAngle - minAngle;
    final sampledDuration = samples.length > 1
        ? samples.last.timestamp.difference(samples.first.timestamp)
        : Duration.zero;

    final chartMinY = math.max(0.0, minAngle - 10);
    final chartMaxY = math.min(180.0, maxAngle + 10);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        title: const Text(
          'Detailed Session Stats',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Export CSV',
            onPressed: _isExporting ? null : () => _exportCsv(bleData, samples),
            icon: _isExporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Time Window',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: StatsTimeWindow.values.map((window) {
                  final isSelected = _selectedWindow == window;
                  return ChoiceChip(
                    label: Text(_windowLabel(window)),
                    selected: isSelected,
                    onSelected: (_) {
                      setState(() {
                        _selectedWindow = window;
                      });
                    },
                    selectedColor: Colors.blueAccent.withValues(alpha: 0.18),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.blueAccent : Colors.black87,
                      fontWeight: FontWeight.w700,
                    ),
                  );
                }).toList(growable: false),
              ),
              const SizedBox(height: 20),
              Container(
                height: 320,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Knee Angle Trend',
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${samples.length} samples',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: samples.isEmpty
                          ? Center(
                              child: Text(
                                'No samples in this window. Try Full Session or enable Mock mode.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            )
                          : LineChart(
                              LineChartData(
                                minX: 0,
                                maxX: spots.length.toDouble() - 1,
                                minY: chartMinY,
                                maxY: chartMaxY,
                                gridData: FlGridData(
                                  show: true,
                                  drawVerticalLine: false,
                                  horizontalInterval: 20,
                                  getDrawingHorizontalLine: (_) => FlLine(
                                    color: Colors.grey.withValues(alpha: 0.15),
                                    strokeWidth: 1,
                                  ),
                                ),
                                borderData: FlBorderData(show: false),
                                titlesData: FlTitlesData(
                                  bottomTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                  topTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                  rightTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 40,
                                      getTitlesWidget: (value, _) => Text(
                                        value.toInt().toString(),
                                        style: TextStyle(
                                          color: Colors.grey[500],
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: spots,
                                    isCurved: true,
                                    curveSmoothness: 0.28,
                                    color: Colors.blueAccent,
                                    barWidth: 3,
                                    isStrokeCapRound: true,
                                    dotData: const FlDotData(show: false),
                                    belowBarData: BarAreaData(
                                      show: true,
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.blueAccent
                                              .withValues(alpha: 0.28),
                                          Colors.blueAccent
                                              .withValues(alpha: 0.02),
                                        ],
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.25,
                children: [
                  _buildMetricCard('Avg Angle',
                      '${avgAngle.toStringAsFixed(1)}°', Icons.tune),
                  _buildMetricCard(
                      'Min / Max',
                      '${minAngle.toStringAsFixed(1)}° / ${maxAngle.toStringAsFixed(1)}°',
                      Icons.swap_vert),
                  _buildMetricCard('Range',
                      '${spreadAngle.toStringAsFixed(1)}°', Icons.straighten),
                  _buildMetricCard(
                      'Samples', samples.length.toString(), Icons.timeline),
                  _buildMetricCard(
                      'Stability',
                      '${bleData.stabilityScore.toStringAsFixed(1)}%',
                      Icons.monitor_heart_outlined),
                  _buildMetricCard(
                      'Good Steps',
                      bleData.goodSteps.toString(),
                      Icons.check_circle_outline,
                      color: Colors.green),
                  _buildMetricCard(
                      'Bad Steps',
                      bleData.badSteps.toString(),
                      Icons.cancel_outlined,
                      color: Colors.red),
                  _buildMetricCard(
                      'Model Score',
                      bleData.lastModelScore.toStringAsFixed(3),
                      Icons.analytics_outlined,
                      color: bleData.lastModelScore >= 0 ? Colors.green : Colors.red),
                  _buildMetricCard(
                      'Anomaly',
                      '${(bleData.lastAnomalyStrength * 100).toStringAsFixed(0)}%',
                      Icons.warning_amber_outlined,
                      color: bleData.lastAnomalyStrength > 0.5 ? Colors.red : Colors.orange),
                    _buildMetricCard(
                      'Toe Clearance',
                      '${bleData.lastToeClearanceMm.toStringAsFixed(1)} mm',
                      Icons.trending_up),
                    _buildMetricCard('Cadence',
                        '${bleData.lastCadenceSpm.toStringAsFixed(0)} spm', Icons.directions_run),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Session Snapshot',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 8),
                    _buildSnapshotRow('Classification', bleData.lastClassification, 
                        bleData.lastClassification.contains('Good') ? Colors.green : Colors.red),
                    _buildSnapshotRow('Assistance', '${bleData.lastAssistance.toStringAsFixed(1)}%', null),
                    _buildSnapshotRow('Activity', '${_getActivityIcon(bleData.lastActivityClass)} ${bleData.lastActivityClass}', null),
                    _buildSnapshotRow('Intention', '${_getIntentionIcon(bleData.lastIntentionClass)} ${bleData.lastIntentionClass}', null),
                    _buildSnapshotRow('Gait phase', bleData.lastGaitPhase, null),
                    _buildSnapshotRow('Toe clearance', '${bleData.lastToeClearanceMm.toStringAsFixed(1)} mm', null),
                    _buildSnapshotRow('Cadence', '${bleData.lastCadenceSpm.toStringAsFixed(0)} spm', null),
                    _buildSnapshotRow('Model score', bleData.lastModelScore.toStringAsFixed(4), 
                        bleData.lastModelScore >= 0 ? Colors.green : Colors.red),
                    _buildSnapshotRow('Anomaly', '${(bleData.lastAnomalyStrength * 100).toStringAsFixed(1)}%', 
                        bleData.lastAnomalyStrength > 0.5 ? Colors.red : Colors.orange),
                    _buildSnapshotRow('Confidence', '${(bleData.lastModelConfidence * 100).toStringAsFixed(0)}%', 
                        _getConfidenceColor(bleData.lastModelConfidence)),
                    Text('Session duration: ${_formatDuration(bleData.sessionDuration)}'),
                    if (samples.isNotEmpty)
                      Text('Latest sample: ${_formatTimestamp(samples.last.timestamp)}'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSnapshotRow(String label, String value, Color? valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: valueColor ?? Colors.black87)),
        ],
      ),
    );
  }

  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.8) return Colors.green;
    if (confidence >= 0.5) return Colors.orange;
    return Colors.red;
  }

  String _getActivityIcon(String activity) {
    if (activity.contains('levelground') || activity.contains('walking')) return '🚶';
    if (activity.contains('ramp')) return '↗️';
    if (activity.contains('stair')) return '🪜';
    if (activity.contains('treadmill')) return '🏃';
    return '❓';
  }

  String _getIntentionIcon(String intention) {
    if (intention.contains('walking') || intention.contains('levelground')) return '🚶';
    if (intention.contains('up')) return '⬆️';
    if (intention.contains('down')) return '⬇️';
    if (intention.contains('run')) return '🏃';
    return '❓';
  }

  Widget _buildMetricCard(String title, String value, IconData icon, {Color? color}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: color ?? Colors.blueGrey[700]),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: color ?? Colors.black87,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
