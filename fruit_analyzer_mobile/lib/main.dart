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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
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
      child: const FruitAnalyzerApp(),
    ),
  );
}

class FruitAnalyzerApp extends StatelessWidget {
  const FruitAnalyzerApp({super.key});

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
          home: const LoginScreen(),
        );
      },
    );
  }
}
