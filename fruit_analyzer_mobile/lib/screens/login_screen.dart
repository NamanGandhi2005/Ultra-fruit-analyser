import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
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
  bool _isLoading = false;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final auth.FirebaseAuth _auth = auth.FirebaseAuth.instance;

  Future<void> _handleAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final email = _emailController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all fields')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (_isSignUp) {
        await prefs.setString('user_$username', password);
        final newUser = User(
          username: username,
          email: email,
          createdAt: DateTime.now().toIso8601String(),
          analysisCount: 0,
          isGuest: false,
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
            user = User(username: username, email: '', createdAt: '', analysisCount: 0, isGuest: false);
            await user.save(prefs);
          }

          if (!mounted) return;
          await prefs.setString('logged_in_user', username);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => HomeScreen(user: user!)),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid credentials')));
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGuestLogin() async {
    final user = User(
      username: 'Guest',
      email: '',
      createdAt: DateTime.now().toIso8601String(),
      analysisCount: 0,
      isGuest: true,
    );
    
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => HomeScreen(user: user)),
    );
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final auth.AuthCredential credential = auth.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final auth.UserCredential userCredential = await _auth.signInWithCredential(credential);
      final auth.User? firebaseUser = userCredential.user;

      if (firebaseUser != null) {
        final prefs = await SharedPreferences.getInstance();
        var user = await User.load(prefs, firebaseUser.displayName ?? firebaseUser.email ?? 'User');
        
        if (user == null) {
          user = User(
            username: firebaseUser.displayName ?? firebaseUser.email ?? 'User',
            email: firebaseUser.email ?? '',
            createdAt: DateTime.now().toIso8601String(),
            analysisCount: 0,
            isGuest: false,
          );
          await user.save(prefs);
        }

        if (!mounted) return;
        await prefs.setString('logged_in_user', user.username);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => HomeScreen(user: user!)),
        );
      }
    } catch (error) {
      print("Google Auth Error: $error");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Google Sign-In failed: $error'))
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topRight,
                radius: 1.5,
                colors: isDark 
                  ? [const Color(0xFF1C1F2A), const Color(0xFF0D0F14)]
                  : [const Color(0xFFFFFFFF), const Color(0xFFF0F2F8)],
              ),
            ),
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 50),
                    // Premium Logo
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.05),
                        shape: BoxShape.circle,
                        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.1)),
                        boxShadow: [
                          BoxShadow(color: theme.colorScheme.primary.withOpacity(0.1), blurRadius: 40, spreadRadius: 10)
                        ],
                      ),
                      child: Icon(Icons.auto_awesome_rounded, size: 64, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'AURA VISION',
                      style: GoogleFonts.poppins(
                        fontSize: 28, 
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      'AI FRUIT ANALYSIS',
                      style: GoogleFonts.poppins(
                        fontSize: 12, 
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 60),
                    
                    // Fields
                    _textField(_usernameController, 'Username', Icons.person_outline_rounded),
                    if (_isSignUp) ...[
                      const SizedBox(height: 16),
                      _textField(_emailController, 'Email Address', Icons.alternate_email_rounded),
                    ],
                    const SizedBox(height: 16),
                    _textField(_passwordController, 'Password', Icons.lock_outline_rounded, obscure: true),
                    const SizedBox(height: 40),
                    
                    // Action Button
                    GestureDetector(
                      onTap: _isLoading ? null : _handleAuth,
                      child: Container(
                        height: 60,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [theme.colorScheme.primary, theme.colorScheme.secondary]),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(color: theme.colorScheme.primary.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))
                          ],
                        ),
                        child: Center(
                          child: Text(
                            _isSignUp ? 'CREATE ACCOUNT' : 'SECURE SIGN IN', 
                            style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: _isLoading ? null : _handleGoogleSignIn,
                      icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
                      label: const Text('SIGN IN WITH GOOGLE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1)),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 60),
                        side: BorderSide(color: theme.colorScheme.onSurface.withOpacity(0.1)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        foregroundColor: theme.colorScheme.onSurface,
                      ),
                    ),

                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: _isLoading ? null : _handleGuestLogin,
                          child: Text('CONTINUE AS GUEST', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        ),
                        const SizedBox(width: 8),
                        Text('•', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.1))),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => setState(() => _isSignUp = !_isSignUp),
                          child: Text(
                            _isSignUp ? 'LOGIN' : 'REGISTER',
                            style: TextStyle(color: theme.colorScheme.primary, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: Center(child: CircularProgressIndicator(color: theme.colorScheme.primary)),
            ),
        ],
      ),
    );
  }

  Widget _textField(TextEditingController controller, String label, IconData icon, {bool obscure = false}) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withOpacity(0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.05)),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: TextStyle(fontSize: 15, color: theme.colorScheme.onSurface),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 13),
          prefixIcon: Icon(icon, size: 20, color: theme.colorScheme.primary.withOpacity(0.7)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          border: InputBorder.none,
        ),
      ),
    );
  }
}
