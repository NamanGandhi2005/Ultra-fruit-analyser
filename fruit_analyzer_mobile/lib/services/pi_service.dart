import 'dart:async';
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
  final DateTime timestamp;

  PiResult({
    required this.fruit,
    required this.confidence,
    required this.isRotten,
    required this.nutrients,
    required this.focusMode,
    required this.lensPos,
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
  String get ip => _ip;
  String get baseUrl => 'http://$_ip:5000';
  
  String _streamTimestamp = DateTime.now().millisecondsSinceEpoch.toString();
  String get streamUrl => '$baseUrl/video_feed?t=$_streamTimestamp';

  void refreshStream() {
    _streamTimestamp = DateTime.now().millisecondsSinceEpoch.toString();
    notifyListeners();
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

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }
}
