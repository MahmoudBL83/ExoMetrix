import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BluetoothHandler extends ChangeNotifier {
  double _currentAngle = 0.0;
  bool _isConnected = false;
  bool _isMocking = false;
  Timer? _mockTimer;
  Timer? _aiTimer;

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _angleCharacteristic;

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
  bool _isPredicting = false;

  void toggleMockMode() {
    _isMocking = !_isMocking;
    if (_isMocking) {
      if (_isConnected) disconnectDevice();
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
      _currentAngle = 60 + 60 * (1.0 * tick % 30) / 30;
      if (tick % 60 < 30) {
        _currentAngle = 120 - _currentAngle;
      }
      
      if (tick % 100 == 0) {
         _currentAngle = 155.0; // Inject bad step
      }
      notifyListeners();
    });

    _aiTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
       _evaluateStepWithAI(_currentAngle);
    });

    _isConnected = true;
  }

  void _stopMocking() {
    _mockTimer?.cancel();
    _aiTimer?.cancel();
    _isConnected = false;
    _currentAngle = 0.0;
    notifyListeners();
  }

  // --- Real BLE Logic ---
  bool isScanning = false;
  List<ScanResult> scanResults = [];
  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;

  void startScan() async {
    if (isScanning) return;
    scanResults.clear();
    isScanning = true;
    notifyListeners();

    _scanResultsSubscription = FlutterBluePlus.scanResults.listen((results) {
      scanResults = results;
      notifyListeners();
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    
    await Future.delayed(const Duration(seconds: 5));
    isScanning = false;
    notifyListeners();
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect(license: License.free);
      _connectedDevice = device;
      _isConnected = true;
      _isMocking = false;
      notifyListeners();

      // Discover services to find the MPU6050 angle data
      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        for (var characteristic in service.characteristics) {
          // In a real app, match UUID here. e.g., if (characteristic.uuid == myExpectedUuid)
          if (characteristic.properties.notify) {
            _angleCharacteristic = characteristic;
            await characteristic.setNotifyValue(true);
            characteristic.onValueReceived.listen((value) {
              // Parse incoming UTF8 or byte array to double
              try {
                String strVal = utf8.decode(value);
                _currentAngle = double.parse(strVal);
                notifyListeners();
              } catch (e) {
                print("Error parsing BLE data: $e");
              }
            });
            break;
          }
        }
      }

      // Periodically run AI Evaluation against real hardware data
      _aiTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
       _evaluateStepWithAI(_currentAngle);
      });

    } catch (e) {
      print("Connection failed: $e");
      _isConnected = false;
      notifyListeners();
    }
  }

  void disconnectDevice() async {
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
      _connectedDevice = null;
    }
    _angleCharacteristic = null;
    _isConnected = false;
    _aiTimer?.cancel();
    notifyListeners();
  }

  // --- AI API Logic ---
  Future<void> _evaluateStepWithAI(double angle) async {
    if (_isPredicting) return;
    _isPredicting = true;

    String baseUrl = 'http://127.0.0.1:5328';
    if (!kIsWeb && Platform.isAndroid) {
      baseUrl = 'http://10.0.2.2:5328';
    }

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/predict'),
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
      print("AI Evaluation Error:"); // Truncated to avoid string escaping problems
      _lastClassification = 'API Offline';
    } finally {
      _isPredicting = false;
    }
  }
}
