import 'dart:async';
import 'package:flutter/material.dart';

class FunLoadingWidget extends StatefulWidget {
  final ValueNotifier<String>? messageNotifier;

  const FunLoadingWidget({super.key, this.messageNotifier});

  @override
  State<FunLoadingWidget> createState() => _FunLoadingWidgetState();
}

class _FunLoadingWidgetState extends State<FunLoadingWidget> {
  final List<String> _messages = [
    "Démarrage d'AutoRoomzio...",
    "Connexion aux serveurs MyRoomz...",
    "Vérification des places disponibles...",
    "Préparation de votre bureau...",
    "Réchauffement de la machine à café...",
    "Ajustement de votre siège ergonomique...",
    "C'est presque prêt !",
  ];
  int _currentIndex = 0;
  Timer? _timer;
  String? _currentExternalMessage;

  @override
  void initState() {
    super.initState();
    if (widget.messageNotifier != null) {
      _currentExternalMessage = widget.messageNotifier!.value;
      widget.messageNotifier!.addListener(_onMessageChanged);
    } else {
      _timer = Timer.periodic(const Duration(milliseconds: 2500), (timer) {
        if (mounted) {
          setState(() {
            _currentIndex = (_currentIndex + 1) % _messages.length;
          });
        }
      });
    }
  }

  void _onMessageChanged() {
    if (mounted && widget.messageNotifier != null) {
      setState(() {
        _currentExternalMessage = widget.messageNotifier!.value;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.messageNotifier?.removeListener(_onMessageChanged);
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
            duration: const Duration(milliseconds: 1000),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.0, 0.2), // Slide up slightly
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: Text(
              _currentExternalMessage ?? _messages[_currentIndex],
              key: ValueKey<String>(_currentExternalMessage ?? _messages[_currentIndex]),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
