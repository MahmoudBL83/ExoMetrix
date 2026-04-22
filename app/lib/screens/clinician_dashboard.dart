import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../services/bluetooth_service.dart';
import 'session_stats_screen.dart';

class ClinicianDashboard extends StatefulWidget {
  const ClinicianDashboard({super.key});

  @override
  State<ClinicianDashboard> createState() => _ClinicianDashboardState();
}

class _ClinicianDashboardState extends State<ClinicianDashboard> {
  void _showApiSettingsDialog(BuildContext context, BluetoothHandler bleData) {
    final controller = TextEditingController(text: bleData.apiBaseUrl);

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Backend API Endpoint'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Base URL',
                  hintText: 'http://10.0.2.2:5328',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Android emulator: http://10.0.2.2:5328\nPhysical phone: http://<your-pc-lan-ip>:5328',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                controller.text = 'http://10.0.2.2:5328';
              },
              child: const Text('Use Emulator URL'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                bleData.setApiBaseUrl(controller.text);
                bleData.checkModelStatus();
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Save & Check'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildApiStatusCard(BluetoothHandler bleData) {
    final statusColor = bleData.isApiReachable ? Colors.green : Colors.orange;
    final statusTitle =
        bleData.isApiReachable ? 'Backend Online' : 'Backend Offline';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.cloud_done_outlined, color: statusColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusTitle,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  bleData.apiStatusDetail,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  bleData.apiBaseUrl,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bleData = context.watch<BluetoothHandler>();
    final dataPoints = bleData.angleHistory
        .asMap()
        .entries
        .map((entry) => FlSpot(entry.key.toDouble(), entry.value))
        .toList();

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        title: const Text('Clinician Dashboard',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Refresh API status',
            onPressed: () {
              bleData.checkModelStatus();
            },
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'API settings',
            onPressed: () => _showApiSettingsDialog(context, bleData),
            icon: const Icon(Icons.settings_ethernet),
          ),
          IconButton(
            tooltip: 'Detailed stats',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SessionStatsScreen(),
                ),
              );
            },
            icon: const Icon(Icons.analytics_outlined),
          ),
          Row(
            children: [
              const Text('Mock',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              Switch(
                value: bleData.isMocking,
                onChanged: (_) => bleData.toggleMockMode(),
                activeColor: Colors.blueAccent,
              ),
              IconButton(
                tooltip: 'Reset Session',
                onPressed: bleData.resetSessionStats,
                icon: const Icon(Icons.restart_alt),
              ),
              const SizedBox(width: 6),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header & Status
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Realtime Kinematics',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: bleData.isConnected
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          bleData.isConnected
                              ? Icons.bluetooth_connected
                              : Icons.bluetooth_disabled,
                          size: 16,
                          color:
                              bleData.isConnected ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          bleData.isConnected ? 'Connected' : 'Disconnected',
                          style: TextStyle(
                            color:
                                bleData.isConnected ? Colors.green : Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildApiStatusCard(bleData),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
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
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                      avatar: const Icon(Icons.route, size: 16),
                      label: Text('Activity: ${bleData.lastActivityClass}'),
                      backgroundColor: Colors.blue.withValues(alpha: 0.12),
                    ),
                    Chip(
                      avatar: const Icon(Icons.psychology_alt_outlined, size: 16),
                      label: Text('Intention: ${bleData.lastIntentionClass}'),
                      backgroundColor: Colors.green.withValues(alpha: 0.12),
                    ),
                    Chip(
                      avatar: const Icon(Icons.waves, size: 16),
                      label: Text('Phase: ${bleData.lastGaitPhase}'),
                      backgroundColor: Colors.cyan.withValues(alpha: 0.12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Chart Card
              Container(
                height: 280,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Knee Angle Log',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: dataPoints.isEmpty
                          ? Center(
                              child: Text(
                                'No data yet. Enable Mock mode to stream sample session data.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            )
                          : LineChart(
                              LineChartData(
                                minY: -20,
                                maxY: 180,
                                gridData: FlGridData(
                                  show: true,
                                  drawVerticalLine: false,
                                  horizontalInterval: 40,
                                  getDrawingHorizontalLine: (value) {
                                    return FlLine(
                                      color:
                                          Colors.grey.withValues(alpha: 0.15),
                                      strokeWidth: 1,
                                    );
                                  },
                                ),
                                titlesData: FlTitlesData(
                                  bottomTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 40,
                                      getTitlesWidget: (value, meta) {
                                        return Text(
                                          value.toInt().toString(),
                                          style: TextStyle(
                                            color: Colors.grey[500],
                                            fontSize: 12,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  topTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                  rightTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                ),
                                borderData: FlBorderData(show: false),
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: dataPoints,
                                    isCurved: true,
                                    curveSmoothness: 0.3,
                                    color: Colors.blueAccent,
                                    barWidth: 4,
                                    isStrokeCapRound: true,
                                    dotData: const FlDotData(show: false),
                                    belowBarData: BarAreaData(
                                      show: true,
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.blueAccent
                                              .withValues(alpha: 0.3),
                                          Colors.blueAccent
                                              .withValues(alpha: 0.0),
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
              const SizedBox(height: 24),

              // KPI Grid
              GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.1,
                children: [
                  _buildStatCard(
                    context,
                    title: 'Stability Score',
                    value: bleData.stabilityScore.toStringAsFixed(1),
                    subtitle:
                        bleData.stabilityScore > 80 ? 'Low Risk' : 'High Risk',
                    icon: Icons.monitor_heart_outlined,
                    color: bleData.stabilityScore > 80
                        ? Colors.green
                        : Colors.orange,
                  ),
                  _buildStatCard(
                    context,
                    title: 'Mechanical Assist',
                    value: '${bleData.lastAssistance.toStringAsFixed(1)}%',
                    subtitle: 'Predicted needs',
                    icon: Icons.precision_manufacturing_outlined,
                    color: Colors.purple,
                  ),
                  _buildStatCard(
                    context,
                    title: 'Good Steps',
                    value: bleData.goodSteps.toString(),
                    subtitle: 'Target adherence',
                    icon: Icons.check_circle_outline,
                    color: Colors.blue,
                  ),
                  _buildStatCard(
                    context,
                    title: 'Compensations',
                    value: bleData.badSteps.toString(),
                    subtitle: 'Requires attention',
                    icon: Icons.warning_amber_rounded,
                    color: Colors.redAccent,
                  ),
                  _buildStatCard(
                    context,
                    title: 'Toe Clearance',
                    value: '${bleData.lastToeClearanceMm.toStringAsFixed(1)} mm',
                    subtitle: 'Swing safety margin',
                    icon: Icons.trending_up,
                    color: Colors.teal,
                  ),
                  _buildStatCard(
                    context,
                    title: 'Cadence',
                    value: '${bleData.lastCadenceSpm.toStringAsFixed(0)} spm',
                    subtitle:
                        'Confidence ${(bleData.lastModelConfidence * 100).toStringAsFixed(0)}%',
                    icon: Icons.directions_run,
                    color: Colors.deepPurple,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[500],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
