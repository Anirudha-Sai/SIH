// lib/main.dart

import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'screens/home_screen.dart';
import 'services/background_service.dart';
import 'utils/battery_optimization.dart';
import 'utils/persistence_manager.dart';

const notificationChannelId = 'vj_bus_driver_channel';

// --- NEW: Configured for minimal user intrusion ---
const AndroidNotificationChannel channel = AndroidNotificationChannel(
  notificationChannelId,
  'Punjab Driver Service',
  description: 'Background location tracking service.',
  importance: Importance.high,
  playSound: true,
  enableVibration: true,
);


final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
  
  // Request battery optimization permissions and set up persistence
  try {
    await BatteryOptimization.requestAllPermissions();
    await PersistenceManager.setupPeriodicAlarms();
  } catch (e) {
    dev.log("Error requesting permissions", error: e);
  }
  
  try {
    await initializeService();
  } catch (e, stacktrace) {
    dev.log("Error during service initialization", error: e, stackTrace: stacktrace);
    // Try to initialize service through PersistenceManager as fallback
    try {
      await PersistenceManager.initializeServiceIfNotRunning();
    } catch (fallbackError) {
      dev.log("Error during fallback service initialization", error: fallbackError);
    }
  }
  runApp(const DriverLocationApp());
}

class DriverLocationApp extends StatelessWidget {
  const DriverLocationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Punjab Driver',
      theme: ThemeData(primarySwatch: Colors.indigo, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}
