import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'api_service.dart';
import 'background_task.dart';
import 'notification_service.dart';
import 'offline_state_manager.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'storage_service.dart';
import 'widgets/offline_ribbon.dart';

// Global root navigator key for global redirection (e.g. session expiration)
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

// Global theme notifiers
final ValueNotifier<ThemeMode> themeNotifier =
    ValueNotifier<ThemeMode>(ThemeMode.system);
final ValueNotifier<int> themeColorNotifier = ValueNotifier<int>(0);
final ValueNotifier<int> fontNotifier = ValueNotifier<int>(0);
final ValueNotifier<double> uiScaleNotifier = ValueNotifier<double>(1.0);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Register global session expiration handler
  RoomzApiService.onSessionExpired = () {
    rootNavigatorKey.currentState?.pushAndRemoveUntil<void>(
      MaterialPageRoute<void>(
        builder: (_) => const LoginScreen(ignoreUrlToken: true),
        settings: const RouteSettings(name: '/'),
      ),
      (Route<dynamic> route) => false,
    );
  };

  await NotificationService().init();

  final StorageService storage = StorageService();

  // Workmanager is Android-only
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await Workmanager().initialize(callbackDispatcher);

    // Ensure the periodic task is scheduled across reboots without killing
    // an already scheduled or currently running worker.
    final bool automationEnabled = await storage.getAutomationEnabled();
    if (automationEnabled) {
      final Map<String, int> autoTimeMap = await storage.getAutomationTime();
      final DateTime now = DateTime.now();
      DateTime targetDate = DateTime(
        now.year,
        now.month,
        now.day,
        autoTimeMap['hour'] ?? 8,
        autoTimeMap['minute'] ?? 0,
      );
      if (targetDate.isBefore(now)) {
        targetDate = targetDate.add(const Duration(days: 1));
      }
      final Duration delay = targetDate.difference(now);
      await Workmanager().registerPeriodicTask(
        '1',
        'autoReservationTask',
        frequency: const Duration(hours: 24),
        initialDelay: delay,
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        constraints: Constraints(networkType: NetworkType.connected),
      );
    }
  }

  final int modeIndex = await storage.getThemeModeIndex();
  themeNotifier.value = modeIndex == 1
      ? ThemeMode.light
      : (modeIndex == 2 ? ThemeMode.dark : ThemeMode.system);

  final int colorIndex = await storage.getThemeColorIndex();
  themeColorNotifier.value = colorIndex;

  final int fontIndex = await storage.getFontFamilyIndex();
  fontNotifier.value = fontIndex;

  final double scaleVal = await storage.getUiScale();
  uiScaleNotifier.value = scaleVal;

  runApp(const MyApp());
}

ThemeData _buildAppTheme(ColorScheme scheme, String fontKey) {
  final String fontFamily = switch (fontKey) {
    'poppins' => 'Poppins',
    'firaCode' => 'FiraCode',
    _ => 'Roboto',
  };
  final ThemeData baseTheme = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: fontFamily,
  );
  return baseTheme.copyWith(
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
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: themeColorNotifier,
      builder: (BuildContext context, int colorIndex, Widget? _) {
        const List<Color> colors = <Color>[
          Colors.lightBlue,
          Colors.green,
          Colors.deepPurple,
          Colors.orange,
          Colors.red,
        ];
        final Color seedColor = colors[colorIndex % colors.length];
        final ColorScheme lightScheme = ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        );
        final ColorScheme darkScheme = ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
        );

        return ValueListenableBuilder<ThemeMode>(
          valueListenable: themeNotifier,
          builder: (BuildContext context, ThemeMode mode, Widget? _) {
            return ValueListenableBuilder<int>(
              valueListenable: fontNotifier,
              builder: (BuildContext context, int fontIndex, Widget? _) {
                final String fontKey = switch (fontIndex) {
                  1 => 'poppins',
                  2 => 'firaCode',
                  _ => 'roboto',
                };

                return ValueListenableBuilder<double>(
                  valueListenable: uiScaleNotifier,
                  builder: (BuildContext context, double uiScale, Widget? _) {
                    return MaterialApp(
                      navigatorKey: rootNavigatorKey,
                      title: 'AutoRoomzio',
                      themeMode: mode,
                      builder: (BuildContext context, Widget? child) {
                        final MediaQueryData mediaQuery = MediaQuery.of(context);
                        final double targetScale =
                            (mediaQuery.textScaler.scale(1.0) * uiScale)
                                .clamp(0.75, 1.35);
                        return MediaQuery(
                          data: mediaQuery.copyWith(
                            textScaler: TextScaler.linear(targetScale),
                          ),
                          child: ValueListenableBuilder<bool>(
                            valueListenable:
                                OfflineStateManager.instance.isOfflineNotifier,
                            builder:
                                (BuildContext context, bool isOffline, Widget? _) {
                              return Column(
                                children: <Widget>[
                                  Expanded(
                                    child: child ?? const SizedBox.shrink(),
                                  ),
                                  if (isOffline)
                                    const SafeArea(
                                      top: false,
                                      child: OfflineRibbon(),
                                    ),
                                ],
                              );
                            },
                          ),
                        );
                      },
                      scrollBehavior: const MaterialScrollBehavior().copyWith(
                        dragDevices: const <PointerDeviceKind>{
                          PointerDeviceKind.mouse,
                          PointerDeviceKind.touch,
                          PointerDeviceKind.stylus,
                          PointerDeviceKind.trackpad,
                        },
                      ),
                      theme: _buildAppTheme(lightScheme, fontKey),
                      darkTheme: _buildAppTheme(darkScheme, fontKey),
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
