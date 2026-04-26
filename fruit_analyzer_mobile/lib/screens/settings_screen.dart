import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart' as dio;
import '../services/notification_service.dart';
import '../services/theme_service.dart';
import '../services/pi_service.dart';
import '../services/prediction_service.dart';
import 'package:google_fonts/google_fonts.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _telegramToken = TextEditingController();
  final _telegramChatId = TextEditingController();
  bool _telegramEnabled = false;

  final _smtpServer = TextEditingController();
  final _smtpPort = TextEditingController();
  final _email = TextEditingController();
  final _emailPassword = TextEditingController();
  bool _emailEnabled = false;
  final _piIp = TextEditingController();
  bool _isUploading = false;

  String? _localModelPath;
  String? _localModelName;
  String? _localInfoPath;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final piService = Provider.of<PiService>(context, listen: false);
    final settings = NotificationSettings.fromPrefs(prefs);
    setState(() {
      _telegramToken.text = settings.telegramToken;
      _telegramChatId.text = settings.telegramChatId;
      _telegramEnabled = settings.telegramEnabled;
      _smtpServer.text = settings.smtpServer;
      _smtpPort.text = settings.smtpPort.toString();
      _email.text = settings.email;
      _emailPassword.text = settings.emailPassword;
      _emailEnabled = settings.emailEnabled;
      _piIp.text = prefs.getString('pi_ip') ?? piService.ip;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final piService = Provider.of<PiService>(context, listen: false);

    await prefs.setString('pi_ip', _piIp.text.trim());
    piService.setIp(_piIp.text.trim());

    final settings = NotificationSettings(
      telegramToken: _telegramToken.text.trim(),
      telegramChatId: _telegramChatId.text.trim(),
      telegramEnabled: _telegramEnabled,
      smtpServer: _smtpServer.text.trim(),
      smtpPort: int.tryParse(_smtpPort.text) ?? 587,
      email: _email.text.trim(),
      emailPassword: _emailPassword.text.trim(),
      emailEnabled: _emailEnabled,
    );
    await settings.save(prefs);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Settings Saved Successfully")));
    }
  }

  Future<void> _pickModel() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['onnx'],
    );
    if (result != null) {
      setState(() {
        _localModelPath = result.files.single.path;
        _localModelName = result.files.single.name;
      });
    }
  }

  Future<void> _pickInfo() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result != null) {
      setState(() {
        _localInfoPath = result.files.single.path;
      });
    }
  }

  Future<void> _applyModelUpdate() async {
    if (_localModelPath == null || _localInfoPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select both .onnx and .json files"))
      );
      return;
    }

    final piService = Provider.of<PiService>(context, listen: false);
    final predictionService = Provider.of<PredictionService>(context, listen: false);

    setState(() => _isUploading = true);
    try {
      // 1. Update Mobile Inference
      final modelBytes = await File(_localModelPath!).readAsBytes();
      final infoJson = json.decode(await File(_localInfoPath!).readAsString());
      await predictionService.updateModel(modelBytes, infoJson, _localModelName!);

      // 2. Upload to Pi if connected
      if (piService.isConnected) {
        final formData = dio.FormData.fromMap({
          'model': await dio.MultipartFile.fromFile(_localModelPath!, filename: _localModelName),
          'info': await dio.MultipartFile.fromFile(_localInfoPath!, filename: 'model_info.json'),
        });

        await dio.Dio().post(
          '${piService.baseUrl}/upload_model',
          data: formData,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Model applied successfully!")));
        setState(() {
          _localModelPath = null;
          _localInfoPath = null;
          _localModelName = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Update failed: $e")));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeService = Provider.of<ThemeService>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text("SETTINGS", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        actions: [
          IconButton(onPressed: _saveSettings, icon: const Icon(Icons.check_circle_outline, color: Colors.blueAccent)),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader("APPEARANCE", Icons.palette_outlined),
            _glassContainer([
              ListTile(
                title: const Text("Dark Mode", style: TextStyle(fontWeight: FontWeight.w500)),
                trailing: Switch(
                  value: themeService.isDarkMode,
                  onChanged: (_) => themeService.toggleTheme(),
                ),
              ),
            ]),
            const SizedBox(height: 32),

            _sectionHeader("🧠 AI MODEL MANAGEMENT", Icons.psychology_outlined),
            _glassContainer([
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Active Model", style: TextStyle(fontSize: 12, color: Colors.grey)),
                      Consumer<PredictionService>(
                        builder: (context, ps, _) => Text(ps.activeModelName, 
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(height: 24),
              
              // New separate selection fields
              _modelSelectionField(
                label: "ONNX Model",
                fileName: _localModelName ?? "No file selected",
                onTap: _pickModel,
                icon: Icons.model_training,
              ),
              const SizedBox(height: 12),
              _modelSelectionField(
                label: "Info JSON",
                fileName: _localInfoPath != null ? "model_info.json" : "No file selected",
                onTap: _pickInfo,
                icon: Icons.info_outline,
              ),
              
              const SizedBox(height: 20),
              
              if (_isUploading)
                const Center(child: CircularProgressIndicator())
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: (_localModelPath != null && _localInfoPath != null) ? _applyModelUpdate : null,
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text("APPLY & UPLOAD TO PI"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),

              const Divider(height: 32),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () async {
                    await Provider.of<PredictionService>(context, listen: false).resetToDefault();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Reset to default model.")));
                    }
                  },
                  child: const Text("RESET TO DEFAULT MODEL"),
                ),
              ),
            ]),
            const SizedBox(height: 32),

            _sectionHeader("🤖 PI REMOTE CONFIG", Icons.memory_rounded),
            _glassContainer([
              _inputField(_piIp, "Pi IP Address"),
              const SizedBox(height: 8),
              const Text("Required for model conversion. Default: 192.168.1.65", style: TextStyle(fontSize: 10, color: Colors.grey)),
            ]),
            const SizedBox(height: 32),

            _sectionHeader("TELEGRAM NOTIFICATIONS", Icons.notifications_active_outlined),
            _glassContainer([
              _inputField(_telegramToken, "Bot Token", obscure: true),
              const SizedBox(height: 16),
              _inputField(_telegramChatId, "Chat ID"),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Enabled", style: TextStyle(fontWeight: FontWeight.w500)),
                  Switch(value: _telegramEnabled, onChanged: (v) => setState(() => _telegramEnabled = v)),
                ],
              ),
            ]),
            const SizedBox(height: 32),

            _sectionHeader("EMAIL ALERTS", Icons.email_outlined),
            _glassContainer([
              _inputField(_smtpServer, "SMTP Server (e.g. smtp.gmail.com)"),
              const SizedBox(height: 16),
              _inputField(_smtpPort, "Port (e.g. 587)"),
              const SizedBox(height: 16),
              _inputField(_email, "Email Address"),
              const SizedBox(height: 16),
              _inputField(_emailPassword, "App Password", obscure: true),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Enabled", style: TextStyle(fontWeight: FontWeight.w500)),
                  Switch(value: _emailEnabled, onChanged: (v) => setState(() => _emailEnabled = v)),
                ],
              ),
            ]),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _modelSelectionField({required String label, required String fileName, required VoidCallback onTap, required IconData icon}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.blueAccent),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  Text(fileName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const Icon(Icons.folder_open, size: 18, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.blueAccent),
          const SizedBox(width: 8),
          Text(label, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.1, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _glassContainer(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(children: children),
    );
  }

  Widget _inputField(TextEditingController controller, String label, {bool obscure = false}) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }
}
