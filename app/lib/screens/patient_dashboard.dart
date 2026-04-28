import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/bluetooth_service.dart';
import 'dart:math' as math;

class PatientDashboard extends StatelessWidget {
  const PatientDashboard({super.key});

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  }

  List<double> _parseAngles(String input) {
    final matches = RegExp(r'-?\d+(?:\.\d+)?').allMatches(input);
    return matches
        .map((match) => double.tryParse(match.group(0) ?? ''))
        .whereType<double>()
        .map((value) => value.clamp(0.0, 180.0).toDouble())
        .toList(growable: false);
  }

  void _showSimulationDialog(BuildContext context, BluetoothHandler bleData) {
    final controller = TextEditingController(
      text: '30, 45, 60, 75, 90, 110, 140, 100, 70, 50',
    );

    final Map<String, String> presets = {
      'Normal Walking': '30, 45, 60, 75, 90, 110, 140, 100, 70, 50',
      'Stair Ascent': '20, 35, 55, 80, 105, 115, 100, 85, 65, 40',
      'Stair Descent': '90, 85, 70, 55, 40, 25, 30, 50, 70, 85',
      'Ramp Ascent': '25, 40, 60, 85, 105, 120, 115, 95, 70, 45',
      'Ramp Descent': '95, 90, 75, 55, 35, 20, 25, 45, 65, 80',
      'Treadmill': '45, 55, 70, 85, 95, 100, 95, 85, 70, 55',
      'Bad Step (Low)': '10, 15, 20, 25, 30, 15, 10, 5, 8, 12',
      'Bad Step (High)': '140, 150, 160, 170, 165, 155, 145, 140, 150, 160',
    };

    void selectPreset(String name) {
      controller.text = presets[name] ?? '';
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Run Angle Simulation'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: presets.keys.map((name) => 
                  ActionChip(
                    label: Text(name, style: const TextStyle(fontSize: 11)),
                    onPressed: () => selectPreset(name),
                  )
                ).toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Enter angles like: 30,45,60,90,120',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'This streams your angles to the backend model (not mock fallback).',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          actions: [
            if (bleData.isSimulating)
              TextButton(
                onPressed: () {
                  bleData.stopSimulation();
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('Stop Simulation'),
              ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final angles = _parseAngles(controller.text);
                if (angles.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter at least one valid angle.'),
                    ),
                  );
                  return;
                }

                bleData.startSimulation(angles);
                Navigator.of(dialogContext).pop();

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Simulation started with ${angles.length} angles',
                    ),
                  ),
                );
              },
              child: const Text('Run Simulation'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bleData = context.watch<BluetoothHandler>();
    final isGoodStep = bleData.lastClassification == 'Good step';
    final isInfoState = bleData.lastClassification == 'Waiting for data...' ||
        bleData.lastClassification.startsWith('Backend online');

    return Scaffold(
      backgroundColor: Colors.blue[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black87,
        title: const Text('ExoMetrix Training',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.bluetooth),
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    builder: (context) => Consumer<BluetoothHandler>(
                      builder: (context, ble, child) => Container(
                        padding: const EdgeInsets.all(24),
                        height: 400,
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('ExoMetrix Devices',
                                    style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold)),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(20)),
                                  ),
                                  onPressed: ble.isScanning
                                      ? null
                                      : () => ble.startScan(),
                                  icon: ble.isScanning
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : const Icon(Icons.search, size: 18),
                                  label: Text(
                                      ble.isScanning ? 'Scanning...' : 'Scan'),
                                )
                              ],
                            ),
                            const SizedBox(height: 20),
                            Expanded(
                              child: ListView.separated(
                                separatorBuilder: (context, index) =>
                                    const Divider(),
                                itemCount: ble.scanResults.length,
                                itemBuilder: (context, index) {
                                  final device = ble.scanResults[index].device;
                                  return ListTile(
                                    leading: const CircleAvatar(
                                      backgroundColor: Colors.blueAccent,
                                      child: Icon(Icons.bluetooth,
                                          color: Colors.white),
                                    ),
                                    title: Text(
                                        device.platformName.isNotEmpty
                                            ? device.platformName
                                            : 'Unknown Device',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    subtitle: Text(device.remoteId.toString(),
                                        style: const TextStyle(fontSize: 12)),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () {
                                      ble.connectToDevice(device);
                                      Navigator.pop(context);
                                    },
                                  );
                                },
                              ),
                            )
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              IconButton(
                tooltip: 'Run simulation angles',
                icon: Icon(
                  bleData.isSimulating ? Icons.play_circle : Icons.play_arrow,
                ),
                onPressed: () => _showSimulationDialog(context, bleData),
              ),
              Switch(
                value: bleData.isMocking,
                activeColor: Colors.blueAccent,
                onChanged: (_) => bleData.toggleMockMode(),
              ),
              const SizedBox(width: 8),
            ],
          )
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Top Score Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Colors.blueAccent, Colors.lightBlue],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blueAccent.withValues(alpha: 0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Total Score',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${bleData.points}',
                        style: const TextStyle(
                            fontSize: 56,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Level 1 Participant',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // AI Feedback Indicator
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: isGoodStep
                        ? Colors.green.withValues(alpha: 0.15)
                        : isInfoState
                            ? Colors.blue.withValues(alpha: 0.12)
                            : Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: isGoodStep
                          ? Colors.green.withValues(alpha: 0.5)
                          : isInfoState
                              ? Colors.blue.withValues(alpha: 0.4)
                              : Colors.orange.withValues(alpha: 0.5),
                      width: 2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isGoodStep
                            ? Icons.check_circle
                            : isInfoState
                                ? Icons.info_outline
                                : Icons.warning_rounded,
                        color: isGoodStep
                            ? Colors.green[700]
                            : isInfoState
                                ? Colors.blue[700]
                                : Colors.orange[700],
                      ),
                      const SizedBox(width: 8),
                      Text(
                        bleData.lastClassification,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isGoodStep
                              ? Colors.green[800]
                              : isInfoState
                                  ? Colors.blue[800]
                                  : Colors.orange[800],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),

                // Gamified visualization
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 240,
                      height: 240,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 200,
                      height: 200,
                      child: CustomPaint(
                        painter:
                            StickFigureLegPainter(angle: bleData.currentAngle),
                      ),
                    ),
                    Positioned(
                      bottom: 20,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${bleData.currentAngle.toStringAsFixed(1)}°',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 48),

                // Bottom Stats
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildMiniStat('Steps Analyzed', '${bleData.totalSteps}',
                        Icons.directions_walk),
                    _buildMiniStat(
                        'Session Time',
                        _formatDuration(bleData.sessionDuration),
                        Icons.timer_outlined),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, IconData icon) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.blueAccent, size: 28),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        Text(
          label,
          style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class StickFigureLegPainter extends CustomPainter {
  final double angle;

  StickFigureLegPainter({required this.angle});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blueAccent
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    final jointPainter = Paint()..color = Colors.white;
    final jointBorder = Paint()
      ..color = Colors.blueAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    // Origin: hip
    final offsetHip = Offset(size.width / 2, 30);
    // Knee
    final offsetKnee = Offset(size.width / 2, size.height / 2);
    // Ankle - rotating based on angle
    final radians = angle * (math.pi / 180);
    final ankleY = math.cos(radians) * 80 + offsetKnee.dy;
    final ankleX = math.sin(radians) * 80 + offsetKnee.dx;

    final offsetAnkle = Offset(ankleX, ankleY);

    // Thigh
    canvas.drawLine(offsetHip, offsetKnee, paint);
    // Shin
    canvas.drawLine(offsetKnee, offsetAnkle, paint);

    // Joints
    _drawJoint(canvas, offsetHip, jointPainter, jointBorder);
    _drawJoint(canvas, offsetKnee, jointPainter, jointBorder);
    _drawJoint(canvas, offsetAnkle, jointPainter, jointBorder);
  }

  void _drawJoint(Canvas canvas, Offset offset, Paint fill, Paint stroke) {
    canvas.drawCircle(offset, 10, fill);
    canvas.drawCircle(offset, 10, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
