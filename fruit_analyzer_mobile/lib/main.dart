import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'services/prediction_service.dart';
import 'services/notification_service.dart';
import 'services/theme_service.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final predictionService = PredictionService();
  await predictionService.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeService()),
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
