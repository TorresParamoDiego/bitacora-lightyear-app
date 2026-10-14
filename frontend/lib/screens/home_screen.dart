import 'package:flutter/material.dart';
import 'voice_recorder_screen.dart';
import 'activities_screen.dart'; // La pantalla que propusimos anteriormente

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  // Utilizamos las dos pantallas principales
  final List<Widget> _screens = [
    const VoiceRecorderScreen(),
    const ActivitiesScreen(), 
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack mantiene vivo el estado de ambas pantallas (ej. la grabadora no se reinicia al cambiar de tab)
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.mic),
            label: 'Grabar',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list_alt),
            label: 'Actividades',
          ),
        ],
      ),
    );
  }
}