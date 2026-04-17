import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../services/bluetooth_service.dart';

class ClinicianDashboard extends StatefulWidget {
  const ClinicianDashboard({super.key});

  @override
  State<ClinicianDashboard> createState() => _ClinicianDashboardState();
}

class _ClinicianDashboardState extends State<ClinicianDashboard> {
  final List<FlSpot> dataPoints = [];
  int tick = 0;

  @override
  Widget build(BuildContext context) {
    final bleData = context.watch<BluetoothHandler>();

    // Add new data point whenever the angle updates
    if (dataPoints.length > 50) {
      dataPoints.removeAt(0);
    }
    // Only update if there's actual new mocking data or BLE data
    dataPoints.add(FlSpot(tick.toDouble(), bleData.currentAngle));
    tick++;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clinician Dashboard'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
               Text(
                  'Realtime Knee Angle log',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  bleData.isConnected ? '● Connected' : '○ Disconnected',
                  style: TextStyle(
                    color: bleData.isConnected ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              flex: 2,
              child: LineChart(
                LineChartData(
                  minY: -20,
                  maxY: 180,
                  titlesData: const FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false), // Hide timeline
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                      ),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: true),
                  lineBarsData: [
                    LineChartBarData(
                      spots: dataPoints,
                      isCurved: true,
                      color: Colors.redAccent,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              flex: 1,
              child: ListView(
                children: [
                 Card(
                    child: ListTile(
                      leading: const Icon(Icons.analytics, color: Colors.blue),
                      title: const Text('Session Stability Score'),
                      subtitle: Text('\ / 100'),
                      trailing: Text(
                        bleData.stabilityScore > 80 ? 'Low Risk' : 'High Risk',
                        style: TextStyle(
                          color: bleData.stabilityScore > 80 ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.check_circle_outline, color: Colors.green),
                      title: const Text('Target Adherence'),
                      subtitle: Text('Good: \ | Bad: \'),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.hardware, color: Colors.purple),
                      title: const Text('Assistance Prediction'),
                      subtitle: Text('Patient needs \% mechanical assistance'),
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
