import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/bluetooth_service.dart';
import 'dart:math' as math;

class PatientDashboard extends StatelessWidget {
  const PatientDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final bleData = context.watch<BluetoothHandler>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('ExoMetrix Patient View'),
        actions: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.bluetooth),
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    builder: (context) => Consumer<BluetoothHandler>(
                      builder: (context, ble, child) => Container(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Select ExoMetrix Device', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                ElevatedButton(
                                  onPressed: ble.isScanning ? null : () => ble.startScan(),
                                  child: Text(ble.isScanning ? 'Scanning...' : 'Scan'),
                                )
                              ],
                            ),
                            const SizedBox(height: 16),
                            Expanded(
                              child: ListView.builder(
                                itemCount: ble.scanResults.length,
                                itemBuilder: (context, index) {
                                  final device = ble.scanResults[index].device;
                                  return ListTile(
                                    title: Text(device.platformName.isNotEmpty ? device.platformName : 'Unknown Device'),
                                    subtitle: Text(device.remoteId.toString()),
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
              const Text('Mock Mode'),
              Switch(
                value: bleData.isMocking,
                onChanged: (_) => bleData.toggleMockMode(),
              ),
            ],
          )
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Current Angle: ${bleData.currentAngle.toStringAsFixed(1)}°',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            
            // Show latest AI classification feedback
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: bleData.lastClassification == 'Good step' 
                    ? Colors.green.withOpacity(0.2) 
                    : Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                bleData.lastClassification,
                style: TextStyle(
                  fontSize: 18, 
                  fontWeight: FontWeight.bold,
                  color: bleData.lastClassification == 'Good step' ? Colors.green[800] : Colors.red[800],
                ),
              ),
            ),
            const SizedBox(height: 40),

            // Gamified visualization placeholder (Stick figure leg)
            SizedBox(
              width: 200,
              height: 200,
              child: CustomPaint(
                painter: StickFigureLegPainter(angle: bleData.currentAngle),
              ),
            ),
            const SizedBox(height: 40),
            
            Text(
              'Points: ${bleData.points}',
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.green),
            ),
             const SizedBox(height: 10),
             Text(
              'Total Steps Analyzed: ${bleData.totalSteps}',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      ),
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
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;

    final jointPainter = Paint()..color = Colors.red;

    // Origin: hip
    final offsetHip = Offset(size.width / 2, 20);
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
    canvas.drawCircle(offsetHip, 8, jointPainter);
    canvas.drawCircle(offsetKnee, 8, jointPainter);
    canvas.drawCircle(offsetAnkle, 8, jointPainter);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
