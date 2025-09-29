import 'dart:io' show Platform;
import 'package:permission_handler/permission_handler.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';

class BatteryOptimization {
  /// Checks if battery optimization is enabled for the app
  static Future<bool> isBatteryOptimizationEnabled() async {
    if (Platform.isAndroid) {
      final status = await Permission.ignoreBatteryOptimizations.status;
      return status == PermissionStatus.denied ||
          status == PermissionStatus.permanentlyDenied;
    }
    return false;
  }

  /// Requests to ignore battery optimizations
  static Future<bool> requestIgnoreBatteryOptimizations() async {
    if (Platform.isAndroid) {
      final status = await Permission.ignoreBatteryOptimizations.request();
      return status.isGranted;
    }
    return false;
  }

  /// Opens battery optimization settings for the app
  static Future<void> openBatteryOptimizationSettings() async {
    if (Platform.isAndroid) {
      final AndroidIntent intent = AndroidIntent(
        action: 'android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
        data: 'package:com.punjab.nextstop', // Replace with your actual package name
      );
      await intent.launch();
    }
  }

  /// Opens auto-start settings for various manufacturers
  static Future<void> openAutoStartSettings() async {
    if (Platform.isAndroid) {
      final AndroidIntent intent = AndroidIntent(
        action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
        data: 'package:com.punjab.nextstop', // Replace with your actual package name
      );
      await intent.launch();
    }
  }

  /// Requests all necessary permissions for background execution
  static Future<bool> requestAllPermissions() async {
    if (Platform.isAndroid) {
      // Request location permissions
      final locationStatus = await [
        Permission.location,
        Permission.locationWhenInUse,
        Permission.locationAlways,
      ].request();
      
      // Request ignore battery optimizations
      final batteryStatus = await Permission.ignoreBatteryOptimizations.request();
      
      // Check if all permissions are granted
      final allLocationGranted = locationStatus.values.every((status) => status.isGranted);
      final batteryGranted = batteryStatus.isGranted;
      
      return allLocationGranted && batteryGranted;
    } else if (Platform.isIOS) {
      // For iOS, request location permissions
      final status = await [
        Permission.locationWhenInUse,
        Permission.locationAlways,
      ].request();
      
      return status.values.every((status) => status.isGranted);
    }
    return false;
  }
}
