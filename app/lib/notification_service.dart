import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static int _nextId =
      (DateTime.now().millisecondsSinceEpoch ~/ 1000) & 0x0FFFFFFF;

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  bool get _isMobilePlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> init() async {
    if (_initialized) return;

    if (!_isMobilePlatform) {
      _initialized = true;
      return;
    }

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('ic_notification');
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings();

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    try {
      await _flutterLocalNotificationsPlugin.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse details) {
          debugPrint("Notification clicked: ${details.payload}");
        },
      );
      _initialized = true;
    } on MissingPluginException {
      // Graceful no-op in headless unit tests where native plugin is absent.
      _initialized = true;
    } catch (e) {
      debugPrint("⚠️ NotificationService.init failed: $e");
    }
  }

  /// Requests notification runtime permission on Android (API 33+) and iOS if needed.
  /// Degrades safely to `false` on unsupported platforms or headless unit tests.
  Future<bool> requestPermissionIfNeeded() async {
    if (!_isMobilePlatform) return false;

    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final PermissionStatus status = await Permission.notification.status;
        if (status.isGranted) return true;
        final PermissionStatus result = await Permission.notification.request();
        return result.isGranted;
      } on MissingPluginException {
        return false;
      } catch (e) {
        debugPrint("⚠️ Permission.notification request failed: $e");
        return false;
      }
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        await init();
        final IOSFlutterLocalNotificationsPlugin? iosPlugin =
            _flutterLocalNotificationsPlugin
                .resolvePlatformSpecificImplementation<
                    IOSFlutterLocalNotificationsPlugin>();
        final bool? granted = await iosPlugin?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return granted ?? true;
      } on MissingPluginException {
        return false;
      } catch (e) {
        debugPrint("⚠️ iOS notification permission request failed: $e");
        return false;
      }
    }

    return false;
  }

  Future<void> showNotification({
    required String title,
    required String body,
  }) async {
    if (!_isMobilePlatform) return;

    await init();

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'autoroomzio_bookings',
      'Réservations AutoRoomzio',
      channelDescription:
          'Notifications quand des réservations sont effectuées en arrière-plan',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      color: Color(0xFF3B4FC8),
    );

    const DarwinNotificationDetails iosPlatformChannelSpecifics =
        DarwinNotificationDetails();

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iosPlatformChannelSpecifics,
    );

    final int notificationId = (_nextId++) & 0x7FFFFFFF;

    try {
      await _flutterLocalNotificationsPlugin.show(
        id: notificationId,
        title: title,
        body: body,
        notificationDetails: platformChannelSpecifics,
      );
    } on MissingPluginException {
      // Graceful no-op in headless unit tests.
    } catch (e) {
      debugPrint("⚠️ NotificationService.showNotification failed: $e");
    }
  }
}
