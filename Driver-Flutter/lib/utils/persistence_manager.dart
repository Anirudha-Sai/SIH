import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PersistenceManager {
  static Timer? _heartbeatTimer;
  static const int _heartbeatInterval = 60; // seconds
  static bool _isServiceInitialized = false;

  /// Starts a heartbeat timer to periodically check if the service is running
  /// and restart it if needed
  static void startHeartbeat() {
    if (Platform.isAndroid) {
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(
        Duration(seconds: _heartbeatInterval),
        (timer) async {
          try {
            // Check if the service is running
            final service = FlutterBackgroundService();
            // Send a ping to the service to check if it's alive
            service.invoke('ping');
            _isServiceInitialized = true;
          } catch (e) {
            // If there's an error, try to restart the service
            print('PersistenceManager: Service not responding, attempting restart: $e');
            await _restartService();
          }
        },
      );
    }
  }

  /// Stops the heartbeat timer
  static void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Restarts the background service
  static Future<void> _restartService() async {
    try {
      final service = FlutterBackgroundService();
      await service.startService();
      _isServiceInitialized = true;
      
      // After restarting, send a restartService command to reinitialize the service
      await Future.delayed(Duration(seconds: 2));
      service.invoke('restartService');
    } catch (e) {
      // Log error but don't throw as this is a recovery mechanism
      print('PersistenceManager: Error restarting service: $e');
    }
  }

  /// Initializes the service if it hasn't been initialized yet
  /// This is useful for crash recovery
  static Future<void> initializeServiceIfNotRunning() async {
    if (!_isServiceInitialized) {
      try {
        final service = FlutterBackgroundService();
        await service.startService();
        _isServiceInitialized = true;
        print('PersistenceManager: Service initialized after crash/restart');
      } catch (e) {
        print('PersistenceManager: Error initializing service: $e');
      }
    }
  }

  /// Sets up periodic alarms to ensure the service stays alive
  /// This is especially useful for Android 6.0+ with Doze mode
  static Future<void> setupPeriodicAlarms() async {
    if (Platform.isAndroid) {
      try {
        // Request alarm permissions if needed
        final status = await Permission.scheduleExactAlarm.status;
        if (status.isDenied || status.isPermanentlyDenied) {
          await Permission.scheduleExactAlarm.request();
        }
      } catch (e) {
        print('PersistenceManager: Error setting up periodic alarms: $e');
      }
    }
  }

  /// Requests auto-start permissions for various Android manufacturers
  static Future<void> requestAutoStartPermissions() async {
    if (Platform.isAndroid) {
      try {
        // Try to open auto-start settings for various manufacturers
        final intent = AndroidIntent(
          action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
          data: 'package:com.punjab.nextstop', // Replace with your actual package name
        );
        await intent.launch();
      } catch (e) {
        print('PersistenceManager: Error requesting auto-start permissions: $e');
      }
    }
  }

  /// Saves the current state to SharedPreferences
  static Future<void> saveState(Map<String, dynamic> state) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (var entry in state.entries) {
        if (entry.value is String) {
          await prefs.setString(entry.key, entry.value as String);
        } else if (entry.value is int) {
          await prefs.setInt(entry.key, entry.value as int);
        } else if (entry.value is double) {
          await prefs.setDouble(entry.key, entry.value as double);
        } else if (entry.value is bool) {
          await prefs.setBool(entry.key, entry.value as bool);
        }
      }
    } catch (e) {
      print('PersistenceManager: Error saving state: $e');
    }
  }

  /// Restores the state from SharedPreferences
  static Future<Map<String, dynamic>> restoreState(List<String> keys) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final Map<String, dynamic> state = {};
      
      for (var key in keys) {
        if (prefs.containsKey(key)) {
          // Try to get the value as different types
          final stringValue = prefs.getString(key);
          if (stringValue != null) {
            state[key] = stringValue;
            continue;
          }
          
          final intValue = prefs.getInt(key);
          if (intValue != null) {
            state[key] = intValue;
            continue;
          }
          
          final doubleValue = prefs.getDouble(key);
          if (doubleValue != null) {
            state[key] = doubleValue;
            continue;
          }
          
          final boolValue = prefs.getBool(key);
          if (boolValue != null) {
            state[key] = boolValue;
            continue;
          }
        }
      }
      
      return state;
    } catch (e) {
      print('PersistenceManager: Error restoring state: $e');
      return {};
    }
  }
}
