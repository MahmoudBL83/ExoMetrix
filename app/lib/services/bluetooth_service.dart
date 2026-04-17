import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

class BluetoothHandler extends ChangeNotifier {
  double _currentAngle = 0.0;
  bool _isConnected = false;
  bool _isMocking = false;
  Timer? _mockTimer;

  // ML/Session Statistics
  int _points = 0;
  int _goodSteps = 0;
  int _badSteps = 0;
  String _lastClassification = 'Waiting for data...';
  double _lastAssistance = 0.0;

  double get currentAngle => _currentAngle;
  bool get isConnected => _isConnected;
  bool get isMocking => _isMocking;
  int get points => _points;
  int get goodSteps => _goodSteps;
  int get badSteps => _badSteps;
  String get lastClassification => _lastClassification;
  double get lastAssistance => _lastAssistance;
  
  double get stabilityScore => (_goodSteps + _badSteps) == 0 
      ? 100.0 
      : (_goodSteps / (_goodSteps + _badSteps)) * 100;

  int get totalSteps => _goodSteps + _badSteps;

  // Track if a prediction is currently in flight to avoid overwhelming backend
  bool _isPredicting = false;

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
    int tick = 0;
    _mockTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      tick++;
      // Simulate knee angle (0 to 120 smoothly)
      _currentAngle = 60 + 60 * (1.0 * tick % 30) / 30;
      if (tick % 60 < 30) {
        _currentAngle = 120 - _currentAngle; // reversed
      }
      
      // Inject some "bad" steps randomly when angle is high
      if (tick % 100 == 0) {
         _currentAngle = 155.0; // Force a bad step trigger
      }

      // Every 1 second (10 ticks), send evaluation to AI Engine
      if (tick % 10 == 0) {
        _evaluateStepWithAI(_currentAngle);
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

  Future<void> _evaluateStepWithAI(double angle) async {
    if (_isPredicting) return;
    _isPredicting = true;

    // Define endpoint. Android emulator needs 10.0.2.2 to access host localhost
    String baseUrl = 'http://127.0.0.1:5328';
    if (!kIsWeb && Platform.isAndroid) {
      baseUrl = 'http://10.0.2.2:5328';
    }

    try {
      final response = await http.post(
        Uri.parse('\/api/predict'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'angle': angle}),
      ).timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _lastClassification = data['classification'] ?? 'Unknown';
        _lastAssistance = (data['assistance_percent'] ?? 0.0).toDouble();

        if (_lastClassification == 'Good step') {
          _goodSteps++;
          _points += 10;
        } else {
          _badSteps++;
          _points -= 5;
          if (_points < 0) _points = 0;
        }
        notifyListeners();
      }
    } catch (e) {
      print('AI Evaluation Error: \');
      _lastClassification = 'Network Error / API Offline';
    } finally {
      _isPredicting = false;
    }
  }

  // Real BLE logic placeholder
  Future<void> connectToDevice() async {
     // TODO: Implement flutter_blue_plus connection
  }
}
