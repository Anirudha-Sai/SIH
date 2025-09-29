import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionsHelper {
  static Future<void> checkAndRequestPermissions() async {
    await Permission.notification.request();
    await Permission.location.request();
    await Permission.locationAlways.request();
    await Permission.ignoreBatteryOptimizations.request();
  }

  static void showBackgroundPermissionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Enable Background Location"),
        content: const Text("To ensure the bus can be tracked at all times, please set location permission to 'Allow all the time' in the app settings."),
        actions: [
          TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.pop(dialogContext),
          ),
          TextButton(
            child: const Text("Open Settings"),
            onPressed: () {
              Navigator.pop(dialogContext);
              openAppSettings();
            },
          ),
        ],
      ),
    );
  }
}
