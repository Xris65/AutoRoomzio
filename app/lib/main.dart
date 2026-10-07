import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:workmanager/workmanager.dart';
import 'background_task.dart';
import 'storage_service.dart';
import 'notification_service.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'api_service.dart';

import 'package:google_fonts/google_fonts.dart';

// Global root navigator key for global redirection (e.g. session expiration)
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

// Global theme notifiers
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);
final ValueNotifier<int> themeColorNotifier = ValueNotifier(0);
final ValueNotifier<int> fontNotifier = ValueNotifier(0);
final ValueNotifier<double> uiScaleNotifier = ValueNotifier<double>(1.0);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Register global session expiration handler
  RoomzApiService.onSessionExpired = () {
    rootNavigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(ignoreUrlToken: true),
        settings: const RouteSettings(name: '/'),
      ),
      (route) => false,
    );
  };
  
  await NotificationService().init();

  // Workmanager is Android-only
  if ((!kIsWeb && Platform.isAndroid)) {
    Workmanager().initialize(callbackDispatcher);

    // Re-register the periodic task on every app launch to survive reboots
    // and ensure the correct schedule time is always applied.
    final storage = StorageService();
    final automationEnabled = await storage.getAutomationEnabled();
    if (automationEnabled) {
      final autoTimeMap = await storage.getAutomationTime();
      final now = DateTime.now();
      var targetDate = DateTime(now.year, now.month, now.day,
          autoTimeMap['hour']!, autoTimeMap['minute']!);
      if (targetDate.isBefore(now)) {
        targetDate = targetDate.add(const Duration(days: 1));
      }
      final delay = targetDate.difference(now);
      Workmanager().registerPeriodicTask(
        "1",
        "autoReservationTask",
        frequency: const Duration(hours: 24),
        initialDelay: delay,
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
        constraints: Constraints(networkType: NetworkType.connected),
      );
    }
  }

  final modeIndex = await StorageService().getThemeModeIndex();
  themeNotifier.value = modeIndex == 1 ? ThemeMode.light : (modeIndex == 2 ? ThemeMode.dark : ThemeMode.system);
  
  final colorIndex = await StorageService().getThemeColorIndex();
  themeColorNotifier.value = colorIndex;

  final fontIndex = await StorageService().getFontFamilyIndex();
  fontNotifier.value = fontIndex;

  final scaleVal = await StorageService().getUiScale();
  uiScaleNotifier.value = scaleVal;

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
            return ValueListenableBuilder<int>(
              valueListenable: fontNotifier,
              builder: (context, fontIndex, _) {
                TextTheme Function([TextTheme]) getFontTheme;
                switch (fontIndex) {
                  case 1: getFontTheme = GoogleFonts.poppinsTextTheme; break;
                  case 2: getFontTheme = GoogleFonts.firaCodeTextTheme; break;
                  default: getFontTheme = GoogleFonts.robotoTextTheme; break; // Classique
                }

                return ValueListenableBuilder<double>(
                  valueListenable: uiScaleNotifier,
                  builder: (context, uiScale, _) {
                    return MaterialApp(
                      navigatorKey: rootNavigatorKey,
                      title: 'AutoRoomzio',
                      themeMode: mode,
                      builder: (context, child) {
                        final mediaQuery = MediaQuery.of(context);
                        final targetScale = (mediaQuery.textScaler.scale(1.0) * uiScale).clamp(0.75, 1.35);
                        return MediaQuery(
                          data: mediaQuery.copyWith(textScaler: TextScaler.linear(targetScale)),
                          child: child ?? const SizedBox.shrink(),
                        );
                      },
                      scrollBehavior: const MaterialScrollBehavior().copyWith(
                        dragDevices: {PointerDeviceKind.mouse, PointerDeviceKind.touch, PointerDeviceKind.stylus, PointerDeviceKind.trackpad},
                      ),
                  theme: ThemeData(
                    colorScheme: ColorScheme.fromSeed(seedColor: seedColor),
                    useMaterial3: true,
                    textTheme: getFontTheme(),
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
                    textTheme: getFontTheme(ThemeData.dark().textTheme),
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
      },
    );
  },
);
  }
}
