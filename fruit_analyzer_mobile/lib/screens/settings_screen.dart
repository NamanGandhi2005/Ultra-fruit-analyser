import 'dart:io';
import 'dart:typed_data';
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

  Future<void> _pickAndUploadModel() async {
    final piService = Provider.of<PiService>(context, listen: false);
    final predictionService = Provider.of<PredictionService>(context, listen: false);
    
    // Explicitly ask for all files or handle the extension check
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any, 
    );

    if (result != null) {
      final fileName = result.files.single.name;
      if (!fileName.endsWith('.pth')) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select a .pth file")));
        return;
      }

      setState(() => _isUploading = true);
      try {
        final filePath = result.files.single.path!;
        final formData = dio.FormData.fromMap({
          'model': await dio.MultipartFile.fromFile(filePath, filename: fileName),
        });

        final uploadDio = dio.Dio();
        final response = await uploadDio.post(
          '${piService.baseUrl}/upload_model',
          data: formData,
        );

        if (response.data['status'] == 'success') {
          final onnxRes = await uploadDio.get('${piService.baseUrl}/download_onnx', options: dio.Options(responseType: dio.ResponseType.bytes));
          final infoRes = await uploadDio.get('${piService.baseUrl}/download_info', options: dio.Options(responseType: dio.ResponseType.json));

          await predictionService.updateModel(
            Uint8List.fromList(onnxRes.data),
            infoRes.data as Map<String, dynamic>,
            fileName,
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Model updated and converted successfully!")));
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Model update failed: $e")));
        }
      } finally {
        if (mounted) setState(() => _isUploading = false);
      }
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
                  if (_isUploading)
                    const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    TextButton.icon(
                      onPressed: _pickAndUploadModel,
                      icon: const Icon(Icons.upload_file),
                      label: const Text("UPLOAD .PTH"),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              const Text("Upload a PyTorch (.pth) model to the Pi for auto-conversion to ONNX.", 
                style: TextStyle(fontSize: 10, color: Colors.white54)),
              const Divider(height: 24),
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
