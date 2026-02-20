import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class NotificationSettings {
  final String telegramToken;
  final String telegramChatId;
  final bool telegramEnabled;
  final String smtpServer;
  final int smtpPort;
  final String email;
  final String emailPassword;
  final bool emailEnabled;

  NotificationSettings({
    required this.telegramToken,
    required this.telegramChatId,
    required this.telegramEnabled,
    required this.smtpServer,
    required this.smtpPort,
    required this.email,
    required this.emailPassword,
    required this.emailEnabled,
  });

  factory NotificationSettings.fromPrefs(SharedPreferences prefs) {
    return NotificationSettings(
      telegramToken: prefs.getString('telegramToken') ?? '',
      telegramChatId: prefs.getString('telegramChatId') ?? '',
      telegramEnabled: prefs.getBool('telegramEnabled') ?? false,
      smtpServer: prefs.getString('smtpServer') ?? '',
      smtpPort: prefs.getInt('smtpPort') ?? 587,
      email: prefs.getString('email') ?? '',
      emailPassword: prefs.getString('emailPassword') ?? '',
      emailEnabled: prefs.getBool('emailEnabled') ?? false,
    );
  }

  Future<void> save(SharedPreferences prefs) async {
    await prefs.setString('telegramToken', telegramToken);
    await prefs.setString('telegramChatId', telegramChatId);
    await prefs.setBool('telegramEnabled', telegramEnabled);
    await prefs.setString('smtpServer', smtpServer);
    await prefs.setInt('smtpPort', smtpPort);
    await prefs.setString('email', email);
    await prefs.setString('emailPassword', emailPassword);
    await prefs.setBool('emailEnabled', emailEnabled);
  }
}

class NotificationService {
  Future<void> sendTelegramAlert(NotificationSettings settings, String message, {String? imagePath}) async {
    if (!settings.telegramEnabled || settings.telegramToken.isEmpty || settings.telegramChatId.isEmpty) return;

    try {
      if (imagePath != null) {
        final url = Uri.parse('https://api.telegram.org/bot${settings.telegramToken}/sendPhoto');
        final request = http.MultipartRequest('POST', url)
          ..fields['chat_id'] = settings.telegramChatId
          ..fields['caption'] = message
          ..files.add(await http.MultipartFile.fromPath('photo', imagePath));
        await request.send();
      } else {
        final url = Uri.parse('https://api.telegram.org/bot${settings.telegramToken}/sendMessage');
        await http.post(url, body: {
          'chat_id': settings.telegramChatId,
          'text': message,
        });
      }
    } catch (e) {
      print("Telegram Error: $e");
    }
  }

  Future<void> sendEmailAlert(NotificationSettings settings, String subject, String body) async {
    // Note: Proper email sending requires a real SMTP client or backend.
    // Implementing a full SMTP client in Dart for mobile is complex.
    // For now, we simulate or use a simple API if available.
    if (!settings.emailEnabled || settings.email.isEmpty) return;
    print("Email Alert: $subject - $body");
    // TODO: Integrate mailer package if needed, though usually requires more setup.
  }
}
