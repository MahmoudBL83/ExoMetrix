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
      backgroundColor: Colors.blue[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black87,
        title: const Text('ExoMetrix Training', style: TextStyle(fontWeight: FontWeight.bold)),
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
                      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                                const Text('ExoMetrix Devices', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  ),
                                  onPressed: ble.isScanning ? null : () => ble.startScan(),
                                  icon: ble.isScanning 
                                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) 
                                      : const Icon(Icons.search, size: 18),
                                  label: Text(ble.isScanning ? 'Scanning...' : 'Scan'),
                                )
                              ],
                            ),
                            const SizedBox(height: 20),
                            Expanded(
                              child: ListView.separated(
                                separatorBuilder: (context, index) => const Divider(),
                                itemCount: ble.scanResults.length,
                                itemBuilder: (context, index) {
                                  final device = ble.scanResults[index].device;
                                  return ListTile(
                                    leading: const CircleAvatar(
                                      backgroundColor: Colors.blueAccent,
                                      child: Icon(Icons.bluetooth, color: Colors.white),
                                    ),
                                    title: Text(device.platformName.isNotEmpty ? device.platformName : 'Unknown Device', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    subtitle: Text(device.remoteId.toString(), style: const TextStyle(fontSize: 12)),
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
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
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
                        color: Colors.blueAccent.withOpacity(0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Total Score',
                        style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${bleData.points}',
                        style: const TextStyle(fontSize: 56, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Level 1 Participant',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // AI Feedback Indicator
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: bleData.lastClassification == 'Good step' 
                        ? Colors.green.withOpacity(0.15) 
                        : Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: bleData.lastClassification == 'Good step' 
                        ? Colors.green.withOpacity(0.5) 
                        : Colors.orange.withOpacity(0.5),
                      width: 2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        bleData.lastClassification == 'Good step' ? Icons.check_circle : Icons.warning_rounded,
                        color: bleData.lastClassification == 'Good step' ? Colors.green[700] : Colors.orange[700],
                      ),
                      const SizedBox(width: 8),
                      Text(
                        bleData.lastClassification,
                        style: TextStyle(
                          fontSize: 18, 
                          fontWeight: FontWeight.bold,
                          color: bleData.lastClassification == 'Good step' ? Colors.green[800] : Colors.orange[800],
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
                            color: Colors.black.withOpacity(0.05),
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
                        painter: StickFigureLegPainter(angle: bleData.currentAngle),
                      ),
                    ),
                    Positioned(
                      bottom: 20,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${bleData.currentAngle.toStringAsFixed(1)}°',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
                    _buildMiniStat('Steps Analyzed', '${bleData.totalSteps}', Icons.directions_walk),
                    _buildMiniStat('Session Time', '12m', Icons.timer_outlined),
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
                color: Colors.black.withOpacity(0.05),
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
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w600),
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
