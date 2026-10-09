import 'package:flutter/material.dart';
import 'screens/voice_recorder_screen.dart';

void main() {
  runApp(const BitacoraLightyearApp());
}

class BitacoraLightyearApp extends StatelessWidget {
  const BitacoraLightyearApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bitácora Lightyear',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5C4EE5), // Morado principal
          primary: const Color(0xFF5C4EE5),
          secondary: const Color(0xFF2ECC71), // Verde
          tertiary: const Color(0xFF3498DB), // Azul
        ),
        useMaterial3: true,
      ),
      home: const VoiceRecorderScreen(),
    );
  }
}