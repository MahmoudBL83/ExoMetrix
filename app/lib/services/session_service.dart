import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class SessionData {
  final int id;
  final String? name;
  final String startedAt;
  final String? endedAt;
  final int goodSteps;
  final int badSteps;
  final int totalSamples;
  final double avgAngle;
  
  SessionData({
    required this.id,
    this.name,
    required this.startedAt,
    this.endedAt,
    required this.goodSteps,
    required this.badSteps,
    required this.totalSamples,
    required this.avgAngle,
  });
  
  factory SessionData.fromJson(Map<String, dynamic> json) {
    return SessionData(
      id: json['id'],
      name: json['name'],
      startedAt: json['started_at'],
      endedAt: json['ended_at'],
      goodSteps: json['good_steps'] ?? 0,
      badSteps: json['bad_steps'] ?? 0,
      totalSamples: json['total_samples'] ?? 0,
      avgAngle: (json['avg_angle'] ?? 0.0).toDouble(),
    );
  }
  
  int get totalSteps => goodSteps + badSteps;
  
  double get stabilityPercent => totalSteps > 0 ? (goodSteps / totalSteps) * 100 : 0;
  
  Duration get duration {
    if (endedAt == null) return Duration.zero;
    final start = DateTime.parse(startedAt);
    final end = DateTime.parse(endedAt!);
    return end.difference(start);
  }
}

class SessionService {
  final AuthService _auth;
  
  SessionService(this._auth);
  
  String get _baseUrl => _auth.baseUrl;
  Map<String, String> get _headers => _auth.authHeaders;
  
  Future<List<SessionData>> getSessions() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/sessions'),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['sessions'] as List)
            .map((s) => SessionData.fromJson(s))
            .toList();
      }
    } catch (_) {}
    return [];
  }
  
  Future<int?> createSession({String? name}) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/sessions'),
        headers: _headers,
        body: jsonEncode({'name': name}),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['session_id'];
      }
    } catch (_) {}
    return null;
  }
  
  Future<SessionData?> getSession(int sessionId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/sessions/$sessionId'),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        return SessionData.fromJson(jsonDecode(response.body));
      }
    } catch (_) {}
    return null;
  }
  
  Future<bool> endSession(int sessionId, {required int goodSteps, required int badSteps, required int totalSamples, required double avgAngle}) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/sessions/$sessionId/end'),
        headers: _headers,
        body: jsonEncode({
          'good_steps': goodSteps,
          'bad_steps': badSteps,
          'total_samples': totalSamples,
          'avg_angle': avgAngle,
        }),
      );
      
      return response.statusCode == 200;
    } catch (_) {}
    return false;
  }
  
  Future<bool> deleteSession(int sessionId) async {
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/api/sessions/$sessionId'),
        headers: _headers,
      );
      
      return response.statusCode == 200;
    } catch (_) {}
    return false;
  }
}