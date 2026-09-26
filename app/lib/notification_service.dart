import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'dart:io';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    if (!Platform.isAndroid && !Platform.isIOS) {
      _initialized = true;
      return; // Skip unsupported platforms for now
    }

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (details) {
        debugPrint("Notification clicked: ${details.payload}");
      },
    );
    _initialized = true;
  }

  Future<void> showNotification({required String title, required String body}) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    
    await init();
    
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'autoroomzio_bookings',
      'Réservations AutoRoomzio',
      channelDescription: 'Notifications quand des réservations sont effectuées en arrière-plan',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      color: Color(0xFF3B4FC8), // Primary color
    );
    
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );
    
    await _flutterLocalNotificationsPlugin.show(
      id: DateTime.now().millisecond,
      title: title,
      body: body,
      notificationDetails: platformChannelSpecifics,
    );
  }
}
