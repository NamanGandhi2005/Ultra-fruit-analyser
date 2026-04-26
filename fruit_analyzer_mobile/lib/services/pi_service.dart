import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PiResult {
  final String fruit;
  final double confidence;
  final bool isRotten;
  final Map<String, dynamic> nutrients;
  final String focusMode;
  final double lensPos;
  final bool automatedEnabled;
  final String display1Mode;
  final String display2Mode;
  final DateTime timestamp;

  PiResult({
    required this.fruit,
    required this.confidence,
    required this.isRotten,
    required this.nutrients,
    required this.focusMode,
    required this.lensPos,
    required this.automatedEnabled,
    required this.display1Mode,
    required this.display2Mode,
    required this.timestamp,
  });

  factory PiResult.fromJson(Map<String, dynamic> json) {
    final lastResult = json['last_result'] as Map<String, dynamic>?;
    return PiResult(
      fruit: lastResult?['fruit'] ?? 'Waiting...',
      confidence: (lastResult?['confidence'] ?? 0.0).toDouble(),
      isRotten: lastResult?['is_rotten'] ?? false,
      nutrients: Map<String, dynamic>.from(lastResult?['nutrients'] ?? {}),
      focusMode: json['focus_mode'] ?? 'auto',
      lensPos: (json['lens_pos'] ?? 0.0).toDouble(),
      automatedEnabled: json['automated_enabled'] ?? true,
      display1Mode: json['display1_mode'] ?? 'result',
      display2Mode: json['display2_mode'] ?? 'result',
      timestamp: DateTime.now(),
    );
  }
}

class PiService extends ChangeNotifier {
  final Dio _dio = Dio();
  String _ip = '192.168.1.65';
  bool _isConnected = false;
  PiResult? _latestResult;
  Timer? _statusTimer;
  Uint8List? _currentFrame;

  PiService() {
    _loadIp();
  }

  Future<void> _loadIp() async {
    final prefs = await SharedPreferences.getInstance();
    _ip = prefs.getString('pi_ip') ?? '192.168.1.65';
    notifyListeners();
  }

  bool get isConnected => _isConnected;
  PiResult? get latestResult => _latestResult;
  Uint8List? get currentFrame => _currentFrame;
  String get ip => _ip;
  String get baseUrl {
    if (_ip.startsWith('http')) return _ip;
    return 'http://$_ip:5000';
  }

  Future<void> fetchFrame() async {
    if (!_isConnected) return;
    try {
      final response = await _dio.get('$baseUrl/latest_frame', 
        options: Options(
          responseType: ResponseType.bytes, 
          receiveTimeout: const Duration(milliseconds: 1500),
          sendTimeout: const Duration(milliseconds: 1000),
        ));
      if (response.statusCode == 200) {
        _currentFrame = Uint8List.fromList(response.data);
        notifyListeners();
      }
    } catch (e) {
      // Quietly ignore frame fetch errors
    }
  }

  void setIp(String newIp) {
    _ip = newIp;
    notifyListeners();
  }

  Future<void> connect() async {
    await checkStatus();
    _startStatusPolling();
  }

  void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      checkStatus();
    });
  }

  Future<void> checkStatus() async {
    try {
      final response = await _dio.get('$baseUrl/status', 
        options: Options(receiveTimeout: const Duration(seconds: 2), sendTimeout: const Duration(seconds: 2)));
      if (response.statusCode == 200) {
        _latestResult = PiResult.fromJson(response.data);
        _isConnected = true;
      } else {
        _isConnected = false;
      }
    } catch (e) {
      _isConnected = false;
    }
    notifyListeners();
  }

  Future<void> triggerScan() async {
    try {
      await _dio.post('$baseUrl/trigger_scan');
    } catch (e) {
      print("Error triggering scan: $e");
    }
  }

  Future<void> setFruitMode(String mode) async {
    try {
      await _dio.post('$baseUrl/set_fruit', data: {'fruit': mode});
    } catch (e) {
      print("Error setting fruit mode: $e");
    }
  }

  Future<void> setFocus(String mode, {double? pos}) async {
    try {
      final Map<String, dynamic> data = {'mode': mode};
      if (pos != null) data['pos'] = pos;
      await _dio.post('$baseUrl/set_focus', data: data);
    } catch (e) {
      print("Error setting focus: $e");
    }
  }

  Future<void> setAutomation(bool enabled) async {
    try {
      await _dio.post('$baseUrl/set_automation', data: {'enabled': enabled});
    } catch (e) {
      print("Error setting automation: $e");
    }
  }

  Future<void> setDisplay(int lcd, String mode, {String? l1, String? l2}) async {
    try {
      final Map<String, dynamic> data = {'lcd': lcd, 'mode': mode};
      if (l1 != null) data['l1'] = l1;
      if (l2 != null) data['l2'] = l2;
      await _dio.post('$baseUrl/set_display', data: data);
    } catch (e) {
      print("Error setting display: $e");
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }
}
