import 'dart:io';
import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'background_task.dart';
import 'storage_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

// Global theme notifiers
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);
final ValueNotifier<int> themeColorNotifier = ValueNotifier(0);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Workmanager is Android-only
  if (Platform.isAndroid) {
    Workmanager().initialize(callbackDispatcher);
  }

  // Load saved theme
  final isDark = await StorageService().getDarkMode();
  if (isDark != null) {
    themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
  }
  
  final colorIndex = await StorageService().getThemeColorIndex();
  themeColorNotifier.value = colorIndex;

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: themeColorNotifier,
      builder: (context, colorIndex, _) {
        final colors = [Colors.lightBlue, Colors.green, Colors.deepPurple, Colors.orange];
        final seedColor = colors[colorIndex % colors.length];

        return ValueListenableBuilder<ThemeMode>(
          valueListenable: themeNotifier,
          builder: (context, ThemeMode mode, _) {
            return MaterialApp(
              title: 'AutoRoomzio',
              themeMode: mode,
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(seedColor: seedColor),
                useMaterial3: true,
                appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
                cardTheme: CardThemeData(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
                ),
                elevatedButtonTheme: ElevatedButtonThemeData(
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              darkTheme: ThemeData(
                colorScheme: ColorScheme.fromSeed(seedColor: seedColor, brightness: Brightness.dark),
                useMaterial3: true,
                appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
                cardTheme: CardThemeData(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
                ),
                elevatedButtonTheme: ElevatedButtonThemeData(
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              home: const _Splash(),
            );
          },
        );
      },
    );
  }
}

/// Checks for an existing session and routes accordingly.
class _Splash extends StatefulWidget {
  const _Splash();

  @override
  State<_Splash> createState() => _SplashState();
}

class _SplashState extends State<_Splash> {
  @override
  void initState() {
    super.initState();
    _route();
  }

  Future<void> _route() async {
    final storage = StorageService();
    final token = await storage.getRefreshToken();
    
    // Add a slight delay so the splash screen is actually visible
    await Future.delayed(const Duration(milliseconds: 800));

    if (!mounted) return;

    if (token != null && token.isNotEmpty) {
      // Already logged in — go straight to home
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
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
          ],
        ),
      ),
    );
  }
}
