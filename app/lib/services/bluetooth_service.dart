import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BluetoothHandler extends ChangeNotifier {
  double _currentAngle = 0.0;
  bool _isConnected = false;
  bool _isMocking = false;
  Timer? _mockTimer;

  double get currentAngle => _currentAngle;
  bool get isConnected => _isConnected;
  bool get isMocking => _isMocking;

  void toggleMockMode() {
    _isMocking = !_isMocking;
    if (_isMocking) {
      _startMocking();
    } else {
      _stopMocking();
    }
    notifyListeners();
  }

  void _startMocking() {
    // Simulating walking knee angles between 0 and 120 smoothly
    int tick = 0;
    _mockTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      tick++;
      // Simple sine wave to simulate knee angle
      _currentAngle = 60 + 60 * (1.0 * tick % 30) / 30; // Not a real sine wave, just oscillating
      if (tick % 60 < 30) {
        _currentAngle = 120 - _currentAngle; // reversed
      }
      notifyListeners();
    });
    _isConnected = true;
  }

  void _stopMocking() {
    _mockTimer?.cancel();
    _isConnected = false;
    _currentAngle = 0.0;
    notifyListeners();
  }

  // Real BLE logic to be implemented later 
  Future<void> connectToDevice() async {
     // TODO: Implement flutter_blue_plus logic here to find ESP32
  }
}
