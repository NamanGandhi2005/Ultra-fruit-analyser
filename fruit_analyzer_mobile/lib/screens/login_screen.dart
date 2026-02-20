import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignUp = false;

  Future<void> _handleAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final email = _emailController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all fields')));
      return;
    }

    if (_isSignUp) {
      await prefs.setString('user_$username', password);
      final newUser = User(
        username: username,
        email: email,
        createdAt: DateTime.now().toIso8601String(),
        analysisCount: 0,
      );
      await newUser.save(prefs);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account created! Please login.')));
      setState(() => _isSignUp = false);
    } else {
      final storedPass = prefs.getString('user_$username');
      if (storedPass == password) {
        var user = await User.load(prefs, username);
        if (user == null) {
          user = User(username: username, email: '', createdAt: '', analysisCount: 0);
          await user.save(prefs);
        }

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => HomeScreen(user: user!)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid credentials')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark 
              ? [const Color(0xFF1a252f), const Color(0xFF121212)]
              : [const Color(0xFFF5F6FA), Colors.white],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo Section
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.apple_rounded, size: 80, color: theme.colorScheme.primary),
                ),
                const SizedBox(height: 24),
                Text(
                  'Fruit Analyzer Pro',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 32, 
                    fontWeight: FontWeight.bold,
                    letterSpacing: -1,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                Text(
                  'Precision Quality Assessment',
                  style: GoogleFonts.poppins(
                    fontSize: 14, 
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 50),
                
                // Form Section
                _textField(_usernameController, 'Username', Icons.person_outline),
                if (_isSignUp) ...[
                  const SizedBox(height: 16),
                  _textField(_emailController, 'Email (Optional)', Icons.mail_outline),
                ],
                const SizedBox(height: 16),
                _textField(_passwordController, 'Password', Icons.lock_outline, obscure: true),
                const SizedBox(height: 40),
                
                ElevatedButton(
                  onPressed: _handleAuth,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 60),
                    elevation: 5,
                    shadowColor: theme.colorScheme.primary.withOpacity(0.3),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(
                    _isSignUp ? 'CREATE ACCOUNT' : 'SECURE LOGIN', 
                    style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
                  ),
                ),
                
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () => setState(() => _isSignUp = !_isSignUp),
                  child: Text(
                    _isSignUp ? 'Already have an account? Login' : 'New user? Create an account',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _textField(TextEditingController controller, String label, IconData icon, {bool obscure = false}) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 22, color: theme.colorScheme.primary.withOpacity(0.7)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: theme.brightness == Brightness.dark 
            ? Colors.white.withOpacity(0.05) 
            : Colors.black.withOpacity(0.04),
      ),
    );
  }
}
