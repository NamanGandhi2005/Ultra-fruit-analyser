import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/prediction_service.dart';
import 'services/notification_service.dart';
import 'services/theme_service.dart';
import 'services/pi_service.dart';
import 'services/database_service.dart';
import 'services/cloud_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'models/user.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  final prefs = await SharedPreferences.getInstance();
  final loggedInUsername = prefs.getString('logged_in_user');
  User? currentUser;
  if (loggedInUsername != null) {
    currentUser = await User.load(prefs, loggedInUsername);
  }

  final predictionService = PredictionService();
  await predictionService.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeService()),
        ChangeNotifierProvider(create: (_) => PiService()),
        Provider(create: (_) => DatabaseService()),
        Provider(create: (_) => CloudService()),
        Provider.value(value: predictionService),
        Provider(create: (_) => NotificationService()),
      ],
      child: FruitAnalyzerApp(initialUser: currentUser),
    ),
  );
}

class FruitAnalyzerApp extends StatelessWidget {
  final User? initialUser;
  const FruitAnalyzerApp({super.key, this.initialUser});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        return MaterialApp(
          title: 'Fruit Analyzer Pro',
          debugShowCheckedModeBanner: false,
          theme: themeService.themeData.copyWith(
            textTheme: GoogleFonts.poppinsTextTheme(themeService.themeData.textTheme),
          ),
          home: initialUser != null ? HomeScreen(user: initialUser!) : const LoginScreen(),
        );
      },
    );
  }
}
