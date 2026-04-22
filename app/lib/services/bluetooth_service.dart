import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class AngleSample {
  final DateTime timestamp;
  final double angle;

  const AngleSample({required this.timestamp, required this.angle});
}

class BluetoothHandler extends ChangeNotifier {
  late String _apiBaseUrl;
  bool _apiReachable = false;
  bool _modelLoaded = false;
  String _apiStatusDetail = 'Not checked yet';

  BluetoothHandler() {
    _apiBaseUrl = _defaultApiBaseUrl();
    Future<void>.delayed(Duration.zero, () {
      checkModelStatus();
    });
  }

  String _normalizeBaseUrl(String value) {
    var normalized = value.trim();
    if (normalized.isEmpty) {
      return normalized;
    }

    if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'http://$normalized';
    }

    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }

    return normalized;
  }

  String _defaultApiBaseUrl() {
    const configuredBaseUrl =
        String.fromEnvironment('EXOMETRIX_API_BASE_URL', defaultValue: '');
    if (configuredBaseUrl.trim().isNotEmpty) {
      return _normalizeBaseUrl(configuredBaseUrl);
    }

    if (kIsWeb) {
      return 'http://127.0.0.1:5328';
    }

    if (Platform.isAndroid) {
      return 'http://10.0.2.2:5328';
    }

    return 'http://127.0.0.1:5328';
  }

  double _currentAngle = 0.0;
  bool _isConnected = false;
  bool _isMocking = false;
  bool _isSimulating = false;
  Timer? _mockTimer;
  Timer? _aiTimer;
  Timer? _simulationTimer;

  List<double> _simulationAngles = const [];
  int _simulationIndex = 0;

  BluetoothDevice? _connectedDevice;

  // ML/Session Statistics
  int _points = 0;
  int _goodSteps = 0;
  int _badSteps = 0;
  String _lastClassification = 'Waiting for data...';
  double _lastAssistance = 0.0;
  double _lastCadenceSpm = 0.0;
  double _lastToeClearanceMm = 0.0;
  String _lastGaitPhase = 'unknown';
  String _lastActivityClass = 'unknown';
  String _lastIntentionClass = 'walking';
  double _lastModelConfidence = 0.0;
  DateTime? _sessionStartedAt;
  final List<double> _angleHistory = [];
  final List<AngleSample> _sampleHistory = [];

  // Keep up to ~6 minutes at 10 Hz so the 2-minute/full windows remain useful.
  static const int _maxHistoryPoints = 3600;

  double get currentAngle => _currentAngle;
  bool get isConnected => _isConnected;
  bool get isMocking => _isMocking;
  bool get isSimulating => _isSimulating;
  int get points => _points;
  int get goodSteps => _goodSteps;
  int get badSteps => _badSteps;
  String get lastClassification => _lastClassification;
  double get lastAssistance => _lastAssistance;
  double get lastCadenceSpm => _lastCadenceSpm;
  double get lastToeClearanceMm => _lastToeClearanceMm;
  String get lastGaitPhase => _lastGaitPhase;
  String get lastActivityClass => _lastActivityClass;
  String get lastIntentionClass => _lastIntentionClass;
  double get lastModelConfidence => _lastModelConfidence;
  List<double> get angleHistory => List.unmodifiable(_angleHistory);
  List<AngleSample> get angleSamples => List.unmodifiable(_sampleHistory);
  String get apiBaseUrl => _apiBaseUrl;
  bool get isApiReachable => _apiReachable;
  bool get isModelLoaded => _modelLoaded;
  String get apiStatusDetail => _apiStatusDetail;
  Duration get sessionDuration => _sessionStartedAt == null
      ? Duration.zero
      : DateTime.now().difference(_sessionStartedAt!);

  double get stabilityScore => (_goodSteps + _badSteps) == 0
      ? 100.0
      : (_goodSteps / (_goodSteps + _badSteps)) * 100;

  int get totalSteps => _goodSteps + _badSteps;
  bool get isStreamActive => _isConnected || _isMocking || _isSimulating;
  bool _isPredicting = false;

  void setApiBaseUrl(String value) {
    final normalized = _normalizeBaseUrl(value);
    if (normalized.isEmpty) {
      return;
    }

    if (normalized == _apiBaseUrl) {
      return;
    }

    _apiBaseUrl = normalized;
    _apiStatusDetail = 'Endpoint updated. Refresh status to validate.';
    notifyListeners();
  }

  Future<void> checkModelStatus() async {
    try {
      final response = await http
          .get(Uri.parse('$_apiBaseUrl/api/model/status'))
          .timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _apiReachable = true;
        _modelLoaded = data['loaded'] == true;

        if (_modelLoaded) {
          final modelType = data['model_type']?.toString() ?? 'unknown';
          _apiStatusDetail = 'Online - $modelType loaded';

          if (totalSteps == 0 && !isStreamActive) {
            _lastClassification =
                'Backend online - start sensor/mock/simulation stream';
          }
        } else {
          _apiStatusDetail = 'Online, but model is not loaded';
        }
      } else {
        _apiReachable = false;
        _modelLoaded = false;
        _apiStatusDetail = 'Status check failed (${response.statusCode})';
      }
    } catch (_) {
      _apiReachable = false;
      _modelLoaded = false;
      _apiStatusDetail = 'Offline or unreachable from mobile app';
    }

    notifyListeners();
  }

  List<AngleSample> samplesWithin(Duration? window) {
    if (window == null) {
      return angleSamples;
    }

    final cutoff = DateTime.now().subtract(window);
    return _sampleHistory
        .where((sample) => sample.timestamp.isAfter(cutoff))
        .toList(growable: false);
  }

  void _appendAngle(double angle) {
    _sampleHistory.add(AngleSample(timestamp: DateTime.now(), angle: angle));
    if (_sampleHistory.length > _maxHistoryPoints) {
      _sampleHistory.removeAt(0);
    }

    _angleHistory.add(angle);
    if (_angleHistory.length > _maxHistoryPoints) {
      _angleHistory.removeAt(0);
    }
  }

  void resetSessionStats() {
    _points = 0;
    _goodSteps = 0;
    _badSteps = 0;
    _lastClassification = 'Waiting for data...';
    _lastAssistance = 0.0;
    _lastCadenceSpm = 0.0;
    _lastToeClearanceMm = 0.0;
    _lastGaitPhase = 'unknown';
    _lastActivityClass = 'unknown';
    _lastIntentionClass = 'walking';
    _lastModelConfidence = 0.0;
    _sessionStartedAt = null;
    _angleHistory.clear();
    _sampleHistory.clear();
    _currentAngle = 0.0;
    notifyListeners();
  }

  void toggleMockMode() {
    if (_isSimulating) {
      stopSimulation(notify: false);
    }

    _isMocking = !_isMocking;
    if (_isMocking) {
      if (_isConnected) disconnectDevice();
      _startMocking();
    } else {
      _stopMocking();
    }
    notifyListeners();
  }

  void startSimulation(
    List<double> angles, {
    Duration interval = const Duration(seconds: 1),
  }) {
    final sanitizedAngles = angles
        .where((angle) => angle.isFinite)
        .map((angle) => angle.clamp(0.0, 180.0).toDouble())
        .toList(growable: false);

    if (sanitizedAngles.isEmpty) {
      return;
    }

    if (_isMocking) {
      _stopMocking();
      _isMocking = false;
    }

    if (_isConnected) {
      disconnectDevice();
    }

    stopSimulation(notify: false);

    _sessionStartedAt ??= DateTime.now();
    _simulationAngles = sanitizedAngles;
    _simulationIndex = 0;
    _isSimulating = true;
    _apiStatusDetail = 'Simulation stream active';

    _runNextSimulationStep();
    _simulationTimer = Timer.periodic(interval, (timer) {
      final hasMore = _runNextSimulationStep();
      if (!hasMore) {
        stopSimulation(notify: false);
        if (_apiReachable) {
          _lastClassification = 'Simulation finished';
        }
        notifyListeners();
      }
    });

    notifyListeners();
  }

  bool _runNextSimulationStep() {
    if (_simulationIndex >= _simulationAngles.length) {
      return false;
    }

    _currentAngle = _simulationAngles[_simulationIndex];
    _appendAngle(_currentAngle);
    _evaluateStepWithAI(_currentAngle);
    _simulationIndex++;
    notifyListeners();
    return true;
  }

  void stopSimulation({bool notify = true}) {
    _simulationTimer?.cancel();
    _simulationTimer = null;
    _simulationAngles = const [];
    _simulationIndex = 0;

    if (_isSimulating) {
      _isSimulating = false;
      if (notify) {
        notifyListeners();
      }
    }
  }

  void _startMocking() {
    _sessionStartedAt ??= DateTime.now();
    int tick = 0;
    _mockTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      tick++;
      final phase = tick / 8.0;
      final smoothSwing = 65 + 40 * math.sin(phase);
      final microVariance = 6 * math.sin(phase * 2.7);
      _currentAngle =
          (smoothSwing + microVariance).clamp(5.0, 165.0).toDouble();

      // Inject an occasional compensation-like movement for demo realism.
      if (tick % 75 == 0) {
        _currentAngle = 155.0;
      }

      _appendAngle(_currentAngle);
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
      if (_isSimulating) {
        stopSimulation(notify: false);
      }

      await device.connect(license: License.free);
      _connectedDevice = device;
      _isConnected = true;
      _isMocking = false;
      _sessionStartedAt ??= DateTime.now();
      notifyListeners();

      // Discover services to find the MPU6050 angle data
      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        for (var characteristic in service.characteristics) {
          // In a real app, match UUID here. e.g., if (characteristic.uuid == myExpectedUuid)
          if (characteristic.properties.notify) {
            await characteristic.setNotifyValue(true);
            characteristic.onValueReceived.listen((value) {
              // Parse incoming UTF8 or byte array to double
              try {
                String strVal = utf8.decode(value);
                _currentAngle = double.parse(strVal).clamp(0.0, 180.0);
              } catch (e) {
                if (value.isNotEmpty) {
                  _currentAngle = value.first.toDouble().clamp(0.0, 180.0);
                }
              }
              _appendAngle(_currentAngle);
              notifyListeners();
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
      debugPrint('Connection failed: $e');
      _isConnected = false;
      notifyListeners();
    }
  }

  void disconnectDevice() async {
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
      _connectedDevice = null;
    }
    _isConnected = false;
    _aiTimer?.cancel();
    notifyListeners();
  }

  // --- AI API Logic ---
  void _applyClassification(
    String classification,
    double assistance, {
    double cadenceSpm = 0.0,
    double toeClearanceMm = 0.0,
    String gaitPhase = 'unknown',
    String activityClass = 'unknown',
    String intentionClass = 'walking',
    double modelConfidence = 0.0,
  }) {
    _lastClassification = classification;
    _lastAssistance = assistance;
    _lastCadenceSpm = cadenceSpm;
    _lastToeClearanceMm = toeClearanceMm;
    _lastGaitPhase = gaitPhase;
    _lastActivityClass = activityClass;
    _lastIntentionClass = intentionClass;
    _lastModelConfidence = modelConfidence;

    if (classification == 'Good step') {
      _goodSteps++;
      _points += 10;
    } else {
      _badSteps++;
      _points -= 5;
      if (_points < 0) {
        _points = 0;
      }
    }

    notifyListeners();
  }

  void _runOfflineMockEvaluation(double angle) {
    final withinTargetWindow = angle >= 20 && angle <= 120;
    final classification =
        withinTargetWindow ? 'Good step' : 'Compensating (bad) step';

    final deviation = (angle - 70).abs();
    final assistance = (10 + deviation * 0.5).clamp(5.0, 85.0).toDouble();
    final cadenceSpm = 88.0;
    final toeClearanceMm = withinTargetWindow ? 18.0 : 9.0;
    final gaitPhase = angle > 60 ? 'swing' : 'stance';

    _applyClassification(
      classification,
      assistance,
      cadenceSpm: cadenceSpm,
      toeClearanceMm: toeClearanceMm,
      gaitPhase: gaitPhase,
      activityClass: 'levelground',
      intentionClass: withinTargetWindow ? 'walking' : 'upstairs',
      modelConfidence: 0.55,
    );
  }

  Future<void> _evaluateStepWithAI(double angle) async {
    if (_isPredicting) return;
    _isPredicting = true;

    try {
      final start = math.max(0, _angleHistory.length - 60);
      final angleSeries = _angleHistory.sublist(start);

      final response = await http
          .post(
            Uri.parse('$_apiBaseUrl/api/predict'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'angle': angle,
              'angle_series': angleSeries,
            }),
          )
          .timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final classification = data['classification']?.toString() ?? 'Unknown';
        final assistance = (data['assistance_percent'] ?? 0.0).toDouble();
        final cadenceSpm =
            (data['cadence_spm'] ?? data['cadence'] ?? 0.0).toDouble();
        final toeClearanceMm =
            (data['toe_clearance_mm'] ?? data['clearance'] ?? 0.0).toDouble();
        final gaitPhase =
            data['gait_phase']?.toString() ?? data['phase']?.toString() ?? 'unknown';
        final activityClass = data['activity_class']?.toString() ?? 'unknown';
        final intentionClass = data['intention_class']?.toString() ?? 'walking';
        final modelConfidence =
            (data['model_confidence'] ?? data['confidence'] ?? 0.0).toDouble();

        _apiReachable = true;
        _modelLoaded = data['model_loaded'] == true || _modelLoaded;
        _apiStatusDetail = _modelLoaded
            ? 'Live predictions: ${activityClass.toUpperCase()} / ${intentionClass.toUpperCase()}'
            : 'Live predictions from API';

        _applyClassification(
          classification,
          assistance,
          cadenceSpm: cadenceSpm,
          toeClearanceMm: toeClearanceMm,
          gaitPhase: gaitPhase,
          activityClass: activityClass,
          intentionClass: intentionClass,
          modelConfidence: modelConfidence,
        );
      } else {
        _apiReachable = false;
        _modelLoaded = false;
        _apiStatusDetail = 'Prediction request failed (${response.statusCode})';

        if (_isMocking) {
          _runOfflineMockEvaluation(angle);
        }
      }
    } catch (e) {
      _apiReachable = false;
      _modelLoaded = false;
      _apiStatusDetail = 'Prediction API offline - using fallback';

      if (_isMocking) {
        _runOfflineMockEvaluation(angle);
      } else {
        _lastClassification = 'API Offline';
        _lastAssistance = 0.0;
        _lastCadenceSpm = 0.0;
        _lastToeClearanceMm = 0.0;
        _lastGaitPhase = 'unknown';
        _lastActivityClass = 'unknown';
        _lastIntentionClass = 'walking';
        _lastModelConfidence = 0.0;
        notifyListeners();
      }
    } finally {
      _isPredicting = false;
    }
  }

  @override
  void dispose() {
    _mockTimer?.cancel();
    _aiTimer?.cancel();
    _simulationTimer?.cancel();
    _scanResultsSubscription?.cancel();
    super.dispose();
  }
}
