import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';
import '../services/theme_service.dart';

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
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('SETTINGS', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 2, color: theme.colorScheme.onSurface)),
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: theme.colorScheme.onSurface),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        children: [
          // Theme Section
          _sectionHeader("APPEARANCE", Icons.palette_outlined),
          Container(
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.05)),
              boxShadow: [
                if (!isDark) BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
              ],
            ),
            child: SwitchListTile(
              secondary: Icon(themeService.isDarkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded, color: theme.colorScheme.primary),
              title: Text("Dark Mode", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: theme.colorScheme.onSurface)),
              subtitle: Text(themeService.isDarkMode ? "Enabled" : "Disabled", style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.6))),
              value: themeService.isDarkMode,
              onChanged: (_) => themeService.toggleTheme(),
            ),
          ),
          const SizedBox(height: 32),

          // Telegram Section
          _sectionHeader("TELEGRAM NOTIFICATIONS", Icons.notifications_active_outlined),
          _glassContainer([
            _inputField(_telegramToken, "Bot Token", obscure: true),
            const SizedBox(height: 16),
            _inputField(_telegramChatId, "Chat ID"),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text("Enable Alerts", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
              value: _telegramEnabled,
              onChanged: (val) => setState(() => _telegramEnabled = val),
            ),
          ]),
          const SizedBox(height: 32),

          // Email Section
          _sectionHeader("EMAIL SERVER", Icons.alternate_email_rounded),
          _glassContainer([
            _inputField(_smtpServer, "SMTP Host"),
            const SizedBox(height: 16),
            _inputField(_smtpPort, "Port"),
            const SizedBox(height: 16),
            _inputField(_email, "Email User"),
            const SizedBox(height: 16),
            _inputField(_emailPassword, "Password", obscure: true),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text("Enable Email Alerts", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
              value: _emailEnabled,
              onChanged: (val) => setState(() => _emailEnabled = val),
            ),
          ]),
          
          const SizedBox(height: 48),
          GestureDetector(
            onTap: _saveSettings,
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [theme.colorScheme.primary, theme.colorScheme.secondary]),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: theme.colorScheme.primary.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))
                ],
              ),
              child: const Center(
                child: Text("SAVE SETTINGS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _glassContainer(List<Widget> children) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.05)),
        boxShadow: [
          if (!isDark) BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(title, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: theme.colorScheme.onSurface.withOpacity(0.6))),
    );
  }

  Widget _inputField(TextEditingController controller, String label, {bool obscure = false}) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.05)),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}
