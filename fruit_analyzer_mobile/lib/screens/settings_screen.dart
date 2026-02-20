import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';
import '../services/theme_service.dart';

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

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
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
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final settings = NotificationSettings(
      telegramToken: _telegramToken.text.trim(),
      telegramChatId: _telegramChatId.text.trim(),
      telegramEnabled: _telegramEnabled,
      smtpServer: _smtpServer.text.trim(),
      smtpPort: int.tryParse(_smtpPort.text.trim()) ?? 587,
      email: _email.text.trim(),
      emailPassword: _emailPassword.text.trim(),
      emailEnabled: _emailEnabled,
    );
    await settings.save(prefs);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved!')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeService = Provider.of<ThemeService>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Theme Section
          _sectionHeader("🎨 App Appearance", Icons.palette_outlined),
          Card(
            child: SwitchListTile(
              secondary: Icon(themeService.isDarkMode ? Icons.dark_mode : Icons.light_mode, color: theme.colorScheme.primary),
              title: const Text("Dark Mode"),
              subtitle: Text(themeService.isDarkMode ? "Eyes comfortable" : "Bright and clear"),
              value: themeService.isDarkMode,
              onChanged: (_) => themeService.toggleTheme(),
            ),
          ),
          const SizedBox(height: 24),

          // Telegram Section
          _sectionHeader("📱 Telegram Alerts", Icons.message_outlined),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _inputField(_telegramToken, "Bot Token", obscure: true),
                  const SizedBox(height: 12),
                  _inputField(_telegramChatId, "Chat ID"),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Enable Telegram Alerts"),
                    value: _telegramEnabled,
                    onChanged: (val) => setState(() => _telegramEnabled = val),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Email Section
          _sectionHeader("📧 Email Settings", Icons.email_outlined),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _inputField(_smtpServer, "SMTP Server"),
                  const SizedBox(height: 12),
                  _inputField(_smtpPort, "SMTP Port"),
                  const SizedBox(height: 12),
                  _inputField(_email, "Email Address"),
                  const SizedBox(height: 12),
                  _inputField(_emailPassword, "Email Password", obscure: true),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Enable Email Alerts"),
                    value: _emailEnabled,
                    onChanged: (val) => setState(() => _emailEnabled = val),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _saveSettings,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
              elevation: 4,
            ),
            child: const Text("SAVE CONFIGURATION", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _inputField(TextEditingController controller, String label, {bool obscure = false}) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
