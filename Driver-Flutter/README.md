# Punjab Driver App - Enhanced Background Persistence

This document describes the enhancements made to ensure the Punjab Driver app stays alive and active in the background, never being closed by other apps, processes, or the OS.

## Enhancements Made

### 1. Android Manifest Enhancements
- Added additional permissions for better background execution
- Enhanced foreground service configuration
- Added battery optimization exemption requests
- Configured auto-start permissions for various manufacturers

### 2. iOS Background Modes Configuration
- Added location, fetch, and processing background modes
- Updated location usage descriptions

### 3. Battery Optimization Handling
- Created `BatteryOptimization` utility class to handle battery optimization requests
- Added automatic permission requests for ignoring battery optimizations
- Implemented methods to open battery optimization settings

### 4. Additional Persistence Mechanisms
- Created `PersistenceManager` utility class with:
  - Heartbeat timer to periodically check service status
  - Periodic alarm setup for Android Doze mode compatibility
  - Auto-start permission requests
  - State saving and restoration utilities

### 5. Background Service Improvements
- Integrated battery optimization handling in the background service
- Added persistence manager initialization
- Enhanced error handling and recovery mechanisms

## Testing Instructions

### Android Testing
1. Install the app on an Android device
2. Grant all requested permissions, especially battery optimization exemptions
3. Select a route and start tracking
4. Minimize the app and check if the notification remains visible
5. Force stop other apps and check if the service continues running
6. Restart the device and verify the service auto-starts
   - After restart, the app should automatically reconnect to the socket
   - If a route was previously selected and tracking was active, it should resume automatically
7. Test with battery saver mode enabled
8. Test with app in "Recent Apps" being swiped away
   - The app should come back to recent apps automatically
9. Force crash the app and verify it restarts automatically
   - The service should restart and reconnect to the socket

### iOS Testing
1. Install the app on an iOS device
2. Grant all requested location permissions
3. Select a route and start tracking
4. Minimize the app and check if location updates continue
5. Test with app in background for extended periods
6. Restart the device and verify the service behavior
   - After restart, the app should automatically reconnect to the socket
   - If a route was previously selected and tracking was active, it should resume automatically
7. Force terminate the app and verify it restarts when background processing is triggered

## Expected Behavior

- The app should continue running in the background even when:
  - Other apps are force stopped
  - The device is restarted
  - Battery saver mode is enabled
  - The app is swiped away from recent apps
  - The screen is turned off

- A persistent notification should always be visible indicating the service is running

## Troubleshooting

### If the app stops running in background:

1. Check that all permissions are granted, especially battery optimization exemptions
2. Verify the app is not being killed by a task killer app
3. Check device-specific battery optimization settings
4. For Android 6.0+, ensure the app is whitelisted from Doze mode restrictions
5. For various Android manufacturers (Xiaomi, Huawei, etc.), check auto-start settings

### Device-Specific Considerations:

- **Xiaomi/Redmi**: Go to Settings > Permissions > Auto-start and enable for this app
- **Huawei**: Go to Settings > Apps > Special access > Ignore battery optimization
- **Samsung**: Go to Settings > Device maintenance > Battery > Unmonitored apps
- **OnePlus**: Go to Settings > Battery > Battery optimization > Don't optimize

## Dependencies

All necessary dependencies are included in the `pubspec.yaml` file:
- `flutter_background_service` for background execution
- `permission_handler` for permission management
- `android_intent_plus` for Android-specific intents
- `wakelock_plus` for keeping the CPU awake
- `flutter_local_notifications` for persistent notifications
- `shared_preferences` for state persistence

## Implementation Details

The implementation follows Flutter best practices for background execution while ensuring maximum compatibility with both Android and iOS platforms. The solution uses a combination of:

1. Foreground services with persistent notifications
2. Battery optimization exemptions
3. Periodic health checks and automatic recovery
4. Platform-specific configurations for different manufacturers
5. Proper error handling and logging

## Limitations

While these enhancements significantly improve background persistence, some limitations may still exist due to:

1. Device manufacturer customizations that may override app settings
2. Aggressive battery saving features in newer Android versions
3. iOS background execution time limits
4. User actions that explicitly force stop the app

In such cases, users may need to manually adjust device settings to allow the app to run in the background.
