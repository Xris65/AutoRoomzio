import 'dart:io';
import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'background_task.dart';
import 'storage_service.dart';
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
        final colors = [Colors.lightBlue, Colors.green, Colors.deepPurple, Colors.orange, Colors.red];
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
              home: const HomeScreen(),
            );
          },
        );
      },
    );
  }
}
