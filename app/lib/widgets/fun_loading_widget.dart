import 'dart:async';
import 'package:flutter/material.dart';

class FunLoadingWidget extends StatefulWidget {
  final bool isSplash;
  
  const FunLoadingWidget({super.key, this.isSplash = false});

  @override
  State<FunLoadingWidget> createState() => _FunLoadingWidgetState();
}

class _FunLoadingWidgetState extends State<FunLoadingWidget> {
  late final List<String> _messages;
  int _currentIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _messages = widget.isSplash 
      ? ["Démarrage d'AutoRoomzio..."] 
      : [
          "Connexion aux serveurs MyRoomz...",
          "Vérification des places disponibles...",
          "Préparation de votre bureau...",
          "Réchauffement de la machine à café...",
          "Ajustement de votre siège ergonomique...",
          "C'est presque prêt !",
        ];
        
    if (!widget.isSplash) {
      _timer = Timer.periodic(const Duration(milliseconds: 1800), (timer) {
        if (mounted) {
          setState(() {
            _currentIndex = (_currentIndex + 1) % _messages.length;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_awesome_mosaic_rounded, size: 72, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 24),
          const Text(
            'AutoRoomzio',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 1.2),
          ),
          const SizedBox(height: 8),
          Text(
            'Vos réservations, en pilote automatique',
            style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 48),
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            child: Text(
              _messages[_currentIndex],
              key: ValueKey<int>(_currentIndex),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
