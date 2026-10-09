import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart'; 
/// Componente visual interactivo que permite confirmar o cancelar una grabación.
/// 
/// Utiliza un [GestureDetector] montado sobre un [Transform.translate] para calcular
/// matemáticamente el desplazamiento (Drag). Implementa una interpolación de color dinámico 
/// (de morado a rojo o verde) y dispara retroalimentación háptica nativa (mediante
/// el paquete 'vibration') al cruzar el umbral del 75% del contenedor.
class SlideControls extends StatefulWidget {
  final VoidCallback onCancel;
  final VoidCallback onStopAndSave;

  const SlideControls({
    super.key,
    required this.onCancel,
    required this.onStopAndSave,
  });

  @override
  State<SlideControls> createState() => _SlideControlsState();
}

class _SlideControlsState extends State<SlideControls> {
  double _dragPosition = 0.0;
  final double _buttonWidth = 64.0;
  bool _hapticPlayed = false; // Bandera para no repetir la vibración

  void _onDragUpdate(DragUpdateDetails details, double maxDrag) {
    setState(() {
      _dragPosition += details.delta.dx;
      
      if (_dragPosition < -maxDrag) _dragPosition = -maxDrag;
      if (_dragPosition > maxDrag) _dragPosition = maxDrag;
    });

    final threshold = maxDrag * 0.75;

    // Disparar vibración justo cuando cruza el límite
    if (_dragPosition.abs() >= threshold) {
      if (!_hapticPlayed) {
        // Fuerza al hardware a vibrar durante 80 milisegundos
        Vibration.vibrate(duration: 80); 
        _hapticPlayed = true;
      }
    } else {
      _hapticPlayed = false;
    }
  }

  void _onDragEnd(DragEndDetails details, double maxDrag) {
    final threshold = maxDrag * 0.75;
    
    if (_dragPosition < -threshold) {
      widget.onCancel();
    } else if (_dragPosition > threshold) {
      widget.onStopAndSave();
    }
    
    setState(() {
      _dragPosition = 0.0;
      _hapticPlayed = false; // Reiniciar para la siguiente grabación
    });
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryPurple = Color(0xFF5C4EE5);
    const Color cancelRed = Colors.redAccent;
    const Color confirmGreen = Color(0xFF2ECC71);

    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxWidth = constraints.maxWidth;
        final double maxDrag = (maxWidth - _buttonWidth) / 2 - 6;

        double progress = (_dragPosition.abs() / maxDrag).clamp(0.0, 1.0);
        
        Color? buttonColor = primaryPurple;
        if (_dragPosition < 0) {
          buttonColor = Color.lerp(primaryPurple, cancelRed, progress);
        } else if (_dragPosition > 0) {
          buttonColor = Color.lerp(primaryPurple, confirmGreen, progress);
        }

        return Container(
          height: 80,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: Colors.grey.shade300, width: 1),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: 24),
                    child: Icon(Icons.close, color: cancelRed, size: 28),
                  ),
                  Padding(
                    padding: EdgeInsets.only(right: 24),
                    child: Icon(Icons.check, color: confirmGreen, size: 28),
                  ),
                ],
              ),
              
              Transform.translate(
                offset: Offset(_dragPosition, 0),
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) => _onDragUpdate(details, maxDrag),
                  onHorizontalDragEnd: (details) => _onDragEnd(details, maxDrag),
                  child: Container(
                    width: _buttonWidth,
                    height: _buttonWidth,
                    decoration: BoxDecoration(
                      color: buttonColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (buttonColor ?? Colors.black).withOpacity(0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: const Icon(Icons.mic, color: Colors.white, size: 32),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}