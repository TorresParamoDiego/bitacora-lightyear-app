
import 'package:flutter/material.dart';
import 'voice_recorder_screen.dart';
import 'activities_screen.dart';
import 'transcriptions_screen.dart'; // Añadir arriba
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  

  // Cambiar esta clave reconstruye ActivitiesScreen.
  int _activitiesRefreshKey = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const VoiceRecorderScreen(),

          ActivitiesScreen(
            key: ValueKey(_activitiesRefreshKey),
          ),
          const TranscriptionsScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        onTap: (index) {
          setState(() {
            _currentIndex = index;

            // Al entrar a Actividades, fuerza una consulta nueva.
            if (index == 1) {
              _activitiesRefreshKey++;
            }
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
          BottomNavigationBarItem( // Nuevo ítem de navegación
            icon: Icon(Icons.history),
            label: 'Historial',
          ),
        ],
      ),
    );
  }
}
