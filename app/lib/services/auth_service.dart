import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService extends ChangeNotifier {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'auth_token';
  static const _userIdKey = 'user_id';
  static const _usernameKey = 'username';
  
  String get baseUrl {
    // Use appropriate base URL for the device
    return 'http://10.0.2.2:5328';  // Android emulator localhost
  }
  
  String? _token;
  int? _userId;
  String? _username;
  bool _isLoading = false;
  String? _error;
  
  String? get token => _token;
  int? get userId => _userId;
  String? get username => _username;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isLoggedIn => _token != null;
  
  AuthService() {
    _loadToken();
  }
  
  Future<void> _loadToken() async {
    _token = await _storage.read(key: _tokenKey);
    final uidStr = await _storage.read(key: _userIdKey);
    _username = await _storage.read(key: _usernameKey);
    if (uidStr != null) {
      _userId = int.tryParse(uidStr);
    }
    notifyListeners();
  }
  
  Future<bool> register(String username, String password, {String? email}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
          'email': email,
        }),
      );
      
      final data = jsonDecode(response.body);
      
      if (data['success'] == true) {
        await _saveAuth(data);
        return true;
      } else {
        _error = data['error'] ?? 'Registration failed';
        return false;
      }
    } catch (e) {
      _error = 'Connection error: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      );
      
      final data = jsonDecode(response.body);
      
      if (data['success'] == true) {
        await _saveAuth(data);
        return true;
      } else {
        _error = data['error'] ?? 'Login failed';
        return false;
      }
    } catch (e) {
      _error = 'Connection error: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  Future<void> logout() async {
    try {
      if (_token != null) {
        await http.post(
          Uri.parse('$baseUrl/api/logout'),
          headers: {'Authorization': 'Bearer $_token'},
        );
      }
    } catch (_) {}
    
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userIdKey);
    await _storage.delete(key: _usernameKey);
    _token = null;
    _userId = null;
    _username = null;
    _error = null;
    notifyListeners();
  }
  
  Future<void> _saveAuth(Map<String, dynamic> data) async {
    _token = data['token'];
    _userId = data['user_id'];
    _username = data['username'];
    await _storage.write(key: _tokenKey, value: _token);
    await _storage.write(key: _userIdKey, value: _userId.toString());
    await _storage.write(key: _usernameKey, value: _username);
    notifyListeners();
  }
  
  Map<String, String> get authHeaders => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $_token',
  };
}