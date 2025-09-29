// lib/services/background_service.dart

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';
import '../utils/battery_optimization.dart';
import '../utils/persistence_manager.dart';
import '../main.dart'; // Make sure this path is correct if main.dart is needed here for flutterLocalNotificationsPlugin

// --- Entry point for initializing the background service ---
Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      isForegroundMode: true,
      autoStart: true,
      notificationChannelId: notificationChannelId,
      initialNotificationTitle: 'Punjab Driver Service', // More descriptive
      initialNotificationContent: 'Service is running in background.', // More descriptive
      foregroundServiceNotificationId: 888,
      // 'ongoing: true' is handled within AndroidNotificationDetails for persistence
    ),
    iosConfiguration: IosConfiguration(
      onForeground: onStart,
      onBackground: onIosBackground, // Add background handler for iOS
      autoStart: true,
    ),
  );
  logToApp("BackgroundService: Initializing service...");
  await service.startService();
  logToApp("BackgroundService: Service started.");
}

/// iOS background handler
@pragma('vm:entry-point')
bool onIosBackground(ServiceInstance service) {
  WidgetsFlutterBinding.ensureInitialized();
  logToApp("BackgroundService: iOS background handler called");
  
  // Schedule a task to restart the service if needed
  Future.delayed(Duration(seconds: 5), () {
    service.invoke('restartService');
  });
  
  return true;
}

// --- Global variables to be managed by the single onStart instance ---
IO.Socket? currentSocket;
Timer? trackingTimer;
Timer? socketHealthTimer; // New timer for socket health checks
String? activeRouteId; // The route ID the currentSocket is connected with
bool isTracking = false; // Indicates if location updates are actively being sent
bool isSocketConnected = false; // Indicates if the single socket is connected
bool isStopping = false; // Flag to prevent location updates during stopping process
bool shouldAutoRestartTracking = false; // Flag to track if tracking should auto-restart after reconnection
late SharedPreferences prefs;

// --- Helper Functions (defined globally for accessibility) ---


IO.Socket _createSocket(String url, String role, String routeId) {
  logToApp("BackgroundService: Creating socket with URL: $url, role: $role, routeId: $routeId");
  final socket = IO.io(
    url,
    IO.OptionBuilder()
        .setTransports(['websocket'])
        .setQuery({'role': role, 'route_id': routeId}) // Ensure routeId is correctly passed here
        .enableReconnection()         // Enable automatic reconnection
        .setReconnectionAttempts(999) // High number for persistent reconnection
        .setReconnectionDelay(2000)   // Start retrying after 2 seconds
        .setReconnectionDelayMax(10000) // Max delay of 10 seconds
        .build(),
  );
  logToApp("BackgroundService: Socket created successfully");
  return socket;
}

void _updateNotification({required String title, required String content}) {
  flutterLocalNotificationsPlugin.show(
    888,
    title,
    content,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        notificationChannelId,
        'Punjab Driver Service',
        importance: Importance.high,
        priority: Priority.high, // High priority
        playSound: true,
        enableVibration: true,
        icon: '@mipmap/ic_launcher',
        visibility: NotificationVisibility.public, // Shows content on lock screen
        ticker: 'ticker',
        ongoing: true, // Make notification unswipeable (Correctly placed here)
        enableLights: true,
        fullScreenIntent: false, // Set to false unless you want to launch an activity when screen is off
      ),
    ),
  );
  logToApp("BackgroundService: Notification updated - Title: $title, Content: $content");
}

Future<void> _sendFinalBroadcast(IO.Socket socket, String routeId) async {
  logToApp("BackgroundService: Sending final broadcast for route: $routeId");
  try {
    Position? position = await Geolocator.getLastKnownPosition() ?? await Geolocator.getCurrentPosition(timeLimit: const Duration(seconds: 5));
    logToApp("BackgroundService: Calling emit() for final broadcast with event type: location_update, socket ID: ${socket.id}");
    socket.emit("final_update", {
      "route_id": routeId, "latitude": position?.latitude, "longitude": position?.longitude, "socket_id": socket.id,
      "role": "Driver", "heading": position?.heading, "status": "stopped", "timestamp": DateTime.now().millisecondsSinceEpoch,
    });
    await Future.delayed(const Duration(milliseconds: 500));
    logToApp("BackgroundService: Final broadcast sent successfully for route: $routeId.");
  } catch (e) { 
      //logToApp("BackgroundService: Error sending final broadcast for route $routeId: $e"); 
    }
}

// Function to periodically check socket health and reconnect if needed
Future<void> _startSocketHealthCheck(ServiceInstance serviceRef) async {
  // Cancel any existing socket health timer
  socketHealthTimer?.cancel();
  
  // Start a new timer that checks socket health every 30 seconds
  socketHealthTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
    logToApp("BackgroundService: Performing socket health check. Current state - connected: ${currentSocket?.connected ?? false}, isSocketConnected: $isSocketConnected, activeRouteId: $activeRouteId");
    
    // Check if we have a route selected
    final String? storedRouteId = prefs.getString('selectedRoute');
    logToApp("BackgroundService: Route from SharedPreferences in health check: $storedRouteId");
    
    // Only attempt to reconnect if a route is selected
    if (storedRouteId != null) {
      // Always ensure we have a route to use
      final String routeToUse = storedRouteId;
      
      // If socket is not connected or connection state is inconsistent, reconnect
      if (currentSocket == null || !currentSocket!.connected || !isSocketConnected) {
        logToApp("BackgroundService: Socket health check detected disconnection. Attempting to reconnect for route: $routeToUse");
        await _connectPersistentSocket(serviceRef, routeToUse);
        logToApp("BackgroundService: Socket reconnection attempt completed for route: $routeToUse");
      }
    } else {
      logToApp("BackgroundService: No route selected. Skipping socket health check reconnection.");
    }
  });
  
  logToApp("BackgroundService: Started socket health check timer.");
}

// Function to create and manage a persistent socket connection
Future<void> _connectPersistentSocket(ServiceInstance serviceRef, String routeIdToConnect) async {
  // If socket exists, destroy it first to ensure clean connection
  if (currentSocket != null) {
    try {
      currentSocket!.offAny();
      currentSocket!.disconnect();
      currentSocket!.close();
      currentSocket!.destroy();
      currentSocket = null;
    } catch (e) {
      logToApp("SOCKET: Error destroying old socket: $e");
    }
  }

  // Update the global activeRouteId
  activeRouteId = routeIdToConnect;
  // Create a new socket instance
  currentSocket = _createSocket(websocketUrl, "Driver", routeIdToConnect);
  currentSocket!.onConnect((_) async {
    isSocketConnected = true;
    serviceRef.invoke('updateUI', {'isTracking': isTracking, 'status':'Connected', 'isAdminConnected': true, 'socketId': currentSocket!.id});
    _updateNotification(title: "Service Connected", content: "Ready to start Tracking for: $activeRouteId.");
    currentSocket!.emit('connected', {'route_id': activeRouteId ?? 'default', 'socket_id': currentSocket!.id, 'role': 'Driver', 'driver_name': prefs.getString('driverName') ?? 'Unknown Driver'});
    
    // Check if we need to auto-restart tracking after reconnection
    if (shouldAutoRestartTracking && activeRouteId != null) {
      logToApp("BackgroundService: Auto-restarting tracking after socket reconnection for route: $activeRouteId");
      await _startTrackingLogic(serviceRef);
      shouldAutoRestartTracking = false; // Reset the flag after restarting
    }
  });

  currentSocket!.onConnectError((error) async {
    isSocketConnected = false;
    serviceRef.invoke('updateUI', {'isTracking': isTracking, 'status': 'Connection Error', 'isAdminConnected': false, 'socketId': currentSocket?.id});
    _updateNotification(title: "Connection Error", content: "Retrying connection...");
  });

  currentSocket!.onDisconnect((_) async {
    isSocketConnected = false;
    // Remember if tracking was active before disconnection
    if (isTracking) {
      shouldAutoRestartTracking = true;
      logToApp("BackgroundService: Tracking was active before disconnection. Will auto-restart after reconnection.");
    }
    serviceRef.invoke('updateUI', {'isTracking': isTracking, 'status': 'Disconnected', 'isAdminConnected': false, 'socketId': currentSocket?.id});
    _updateNotification(title: "Service Disconnected", content: "Attempting to reconnect.");
  });

  currentSocket!.onError((error) async {
    serviceRef.invoke('updateUI', {'isAdminConnected': false, 'status': 'Socket Error', 'isTracking': isTracking, 'socketId': currentSocket?.id});
  });

  currentSocket!.on('server_start', (_) async {
    _startTrackingLogic(serviceRef); // Server commands to start tracking
  });

  currentSocket!.on('admin_start', (data) async {
    await _startTrackingLogic(serviceRef); // Start tracking
  });

  currentSocket!.on('server_stop', (data) async {
    isStopping = true; // Set stopping flag to prevent location updates
    await _stopTrackingLogic(serviceRef); // Stop tracking, keep socket connected
    _updateNotification(title: "Service Connected", content: "Ready to start Tracking for: $activeRouteId.");
    serviceRef.invoke('updateUI', {'isTracking': false, 'status': 'Stopped', 'isAdminConnected': isSocketConnected});
    // Note: isStopping flag is reset in _stopTrackingLogic after final broadcast
  });

  currentSocket!.on('admin_stop', (data) async {
    isStopping = true; // Set stopping flag to prevent location updates
    await _stopTrackingLogic(serviceRef); // Stop tracking, keep socket connected
    _updateNotification(title: "Service Connected", content: "Ready to start Tracking for: $activeRouteId.");
    serviceRef.invoke('updateUI', {'isTracking': false, 'status': 'Stopped', 'isAdminConnected': isSocketConnected});
    // Note: isStopping flag is reset in _stopTrackingLogic after final broadcast
  });

  logToApp("SOCKET: Calling connect() for socket with ID: ${currentSocket?.id} and route: $activeRouteId");
  currentSocket!.connect();
  logToApp("SOCKET: Persistent socket connect() called for route: $activeRouteId");
}

// Function to start location tracking (starts timer)
Future<void> _startTrackingLogic(ServiceInstance serviceRef) async {
  // If already tracking, just return
  if (isTracking && trackingTimer != null && trackingTimer!.isActive) {
    logToApp("BackgroundService: Tracking already active. Skipping start tracking logic.");
    return;
  }
  
  // Check if socket is connected
  if (currentSocket == null || !currentSocket!.connected) {
    logToApp("BackgroundService: Cannot start tracking: Socket not connected.");
    serviceRef.invoke('updateUI', {'isTracking': false, 'status': 'Disconnected', 'isAdminConnected': false});
    _updateNotification(title: "Tracking Failed", content: "Socket not connected.");
    return;
  }

  isTracking = true;
  WakelockPlus.enable();
  _updateNotification(title: "Tracking Active", content: "Live on Route: ${activeRouteId ?? 'N/A'}");
  serviceRef.invoke('updateUI', {'isTracking': true, 'status': 'Connected', 'isAdminConnected': true, 'socketId': currentSocket?.id});
  logToApp("BackgroundService: Starting tracking timer.");

  // Ensure old timer is cancelled before starting a new one
  trackingTimer?.cancel();

  trackingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
    // Check immediately if we should stop tracking
    if (currentSocket == null || !currentSocket!.connected || !isTracking || isStopping) {
      logToApp("BackgroundService: Tracking timer stopped: socket disconnected, not tracking, or stopping.");
      timer.cancel();
      return;
    }
    
    try {
      Position position = await Geolocator.getCurrentPosition(forceAndroidLocationManager: true, timeLimit: const Duration(seconds: 10));
      
      // Check again after getting position if we should still send the update
      if (!isTracking || isStopping) {
        logToApp("BackgroundService: Skipping location update - tracking stopped during position fetch.");
        timer.cancel();
        return;
      }
      
      logToApp("BackgroundService: Emitting location. Route: ${activeRouteId ?? 'N/A'}. Lat=${position.latitude}, Lng=${position.longitude}, Status=${"tracking_active"}");
      final String eventType = "location_update";
      logToApp("BackgroundService: Emitting $eventType for route: ${activeRouteId ?? 'default'}");
      logToApp("BackgroundService: Calling emit() with event type: $eventType, socket ID: ${currentSocket!.id}");
      currentSocket!.emit(eventType, {
        "route_id": activeRouteId ?? "default", // Always use current route
        "latitude": position.latitude,
        "longitude": position.longitude,
        "socket_id": currentSocket!.id,
        "role": "Driver",
        "heading": position.heading,
        "status":"tracking_active",
        "timestamp": DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      logToApp("BackgroundService: Error getting or sending location: $e");
      // Consider more aggressive handling here, e.g., stopping tracking if errors persist
    }
  });
}

// Function to stop location tracking (stops timer, keeps socket connected)
Future<void> _stopTrackingLogic(ServiceInstance serviceRef) async {
  if (!isTracking && (trackingTimer == null || !trackingTimer!.isActive)) {
    logToApp("BackgroundService: Tracking is already inactive. Skipping stop tracking logic for route: ${activeRouteId ?? 'N/A'}.");
    // Reset isStopping flag as we're not actually stopping anything
    isStopping = false;
    return;
  }

  // Immediately stop broadcasting location updates
  isTracking = false;
  trackingTimer?.cancel();
  trackingTimer = null;
  logToApp("BackgroundService: Tracking timer cancelled for route: ${activeRouteId ?? 'N/A'}.");

  // Send final broadcast with status "stopped" immediately after stopping tracking
  if (currentSocket != null && currentSocket!.connected && activeRouteId != null) {
    await _sendFinalBroadcast(currentSocket!, activeRouteId!);
  }

  WakelockPlus.disable();
  logToApp("BackgroundService: Wakelock disabled for route: ${activeRouteId ?? 'N/A'}.");

  _updateNotification(title: "Service Connected", content: "Ready to start Tracking for: $activeRouteId.");
  serviceRef.invoke('updateUI', {'isTracking': false, 'status': 'Connected', 'isAdminConnected': isSocketConnected});
  logToApp("BackgroundService: Tracking stopped, UI updated for route: ${activeRouteId ?? 'N/A'}.");
  
  // Reset isStopping flag after final broadcast is sent
  isStopping = false;
}


// --- onStart function (main entry point for background service) ---
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
    logToApp("BackgroundService: Service set to foreground mode immediately onStart.");
  }

  prefs = await SharedPreferences.getInstance();
  logToApp("BackgroundService: SharedPreferences initialized in onStart.");

  Future.microtask(() async {
    // Add a small delay to ensure SharedPreferences are properly initialized
    await Future.delayed(const Duration(milliseconds: 200));
    
    // Request battery optimization permissions on Android
    if (service is AndroidServiceInstance) {
      try {
        final isBatteryOptEnabled = await BatteryOptimization.isBatteryOptimizationEnabled();
        logToApp("BackgroundService: Battery optimization enabled: $isBatteryOptEnabled");
        
        if (isBatteryOptEnabled) {
          // Try to request ignore battery optimizations
          final batteryRequestResult = await BatteryOptimization.requestIgnoreBatteryOptimizations();
          logToApp("BackgroundService: Battery optimization request result: $batteryRequestResult");
        }
        
        // Set up additional persistence mechanisms
        PersistenceManager.startHeartbeat();
        await PersistenceManager.setupPeriodicAlarms();
      } catch (e) {
        logToApp("BackgroundService: Error handling battery optimization: $e");
      }
    }
    
    // Always re-fetch the latest selectedRoute from preferences at the start of onStart logic
    final String? storedRouteId = prefs.getString('selectedRoute');
    logToApp("BackgroundService: Route from SharedPreferences on start: $storedRouteId");
    logToApp("BackgroundService: Current time: ${DateTime.now()}");
    final DateTime now = DateTime.now();
    final DateTime sixThirtyAM = DateTime(now.year, now.month, now.day, 6, 30);
    final DateTime elevenAM = DateTime(now.year, now.month, now.day, 11, 0);
    logToApp("BackgroundService: Time range for auto-start: $sixThirtyAM - $elevenAM");

    // Only connect socket if a route is selected
    if (storedRouteId != null) {
      logToApp("BackgroundService: Route selected. Connecting socket for route: $storedRouteId");
      await _connectPersistentSocket(service, storedRouteId);
      
      // Now, check if tracking should be active based on time
      if (now.isAfter(sixThirtyAM) && now.isBefore(elevenAM)) {
        logToApp("BackgroundService: Auto-start time conditions met. Initiating tracking logic for route: $storedRouteId.");
        await _startTrackingLogic(service);
      } else {
        logToApp("BackgroundService: Auto-start time conditions NOT met. Socket connected, but tracking is paused for route: $storedRouteId.");
        service.invoke('updateUI', {'isTracking': false, 'status': 'Connected (Paused)', 'isAdminConnected': isSocketConnected, 'socketId': currentSocket?.id});
        _updateNotification(title: "Service Connected", content: "Ready to start Tracking for: $activeRouteId.");
      }
    } else {
      logToApp("BackgroundService: No route selected on startup. Not connecting socket.");
      service.invoke('updateUI', {'isTracking': false, 'status': 'No Route Selected', 'isAdminConnected': false, 'socketId': null});
      _updateNotification(title: "No Route Selected", content: "Select a route to start tracking.");
      // Initialize socket as null
      currentSocket = null;
      isSocketConnected = false;
    }

    // Start socket health check
    _startSocketHealthCheck(service);
    
    // Listener for service restart requests (after crashes or device restarts)
    service.on('restartService').listen((event) async {
      logToApp("BackgroundService: Received restartService command.");
      
      // Re-initialize critical components
      prefs = await SharedPreferences.getInstance();
      logToApp("BackgroundService: SharedPreferences re-initialized after restart.");
      
      // Check if a route was previously selected
      final String? storedRouteId = prefs.getString('selectedRoute');
      logToApp("BackgroundService: Route from SharedPreferences after restart: $storedRouteId");
      
      if (storedRouteId != null) {
        logToApp("BackgroundService: Route found after restart. Reconnecting socket for route: $storedRouteId");
        await _connectPersistentSocket(service, storedRouteId);
        
        // Check if tracking was previously active
        final bool wasTracking = prefs.getBool('location_started') ?? false;
        logToApp("BackgroundService: Tracking state after restart: $wasTracking");
        
        if (wasTracking) {
          logToApp("BackgroundService: Resuming tracking after restart for route: $storedRouteId");
          await _startTrackingLogic(service);
        } else {
          logToApp("BackgroundService: Socket connected but tracking was not active after restart.");
          service.invoke('updateUI', {'isTracking': false, 'status': 'Connected (Paused)', 'isAdminConnected': isSocketConnected, 'socketId': currentSocket?.id});
          _updateNotification(title: "Service Connected", content: "Ready to start Tracking for: $activeRouteId.");
        }
      } else {
        logToApp("BackgroundService: No route selected after restart.");
        service.invoke('updateUI', {'isTracking': false, 'status': 'No Route Selected', 'isAdminConnected': false, 'socketId': null});
        _updateNotification(title: "No Route Selected", content: "Select a route to start tracking.");
      }
    });
    
    // Listener for when a route is selected
    service.on('routeSelected').listen((event) async {
      final routeIdFromUI = event?['route_id'] as String?;
      logToApp("BackgroundService: Received 'routeSelected' command from UI for route: $routeIdFromUI.");
      
      if (routeIdFromUI == null) {
        logToApp("BackgroundService: Cannot select route: No route provided.");
        return;
      }
      
      // Update SharedPreferences
      await prefs.setString('selectedRoute', routeIdFromUI);
      logToApp("BackgroundService: Updated SharedPreferences with route: $routeIdFromUI");
      
      // Connect socket with the new route
      logToApp("BackgroundService: Connecting socket for newly selected route: $routeIdFromUI");
      await _connectPersistentSocket(service, routeIdFromUI);
      
      // Update UI
      service.invoke('updateUI', {'isTracking': isTracking, 'status': 'Connected (Paused)', 'isAdminConnected': isSocketConnected, 'socketId': currentSocket?.id});
      _updateNotification(title: "Service Connected", content: "Ready to start Tracking for: $activeRouteId.");
      logToApp("BackgroundService: Completed route selection for route: $routeIdFromUI");
    });
    
    // Listeners for UI commands
    service.on('startTracking').listen((event) async {
      final routeIdFromUI = event?['route_id'] as String?;
      logToApp("BackgroundService: Received 'startTracking' command from UI for route: $routeIdFromUI.");
      
      // Get the route from the event if provided, otherwise from SharedPreferences
      final String? currentSelectedRouteId = prefs.getString('selectedRoute');
      final String? routeToUse = routeIdFromUI ?? currentSelectedRouteId;
      
      // Check if a route is selected
      if (routeToUse == null) {
        logToApp("BackgroundService: Cannot start tracking: No route selected.");
        service.invoke('updateUI', {'isTracking': false, 'status': 'No Route Selected', 'isAdminConnected': false, 'socketId': null});
        _updateNotification(title: "No Route Selected", content: "Select a route to start tracking.");
        return;
      }
      
      // Update active route if provided
      if (routeIdFromUI != null) {
        activeRouteId = routeIdFromUI;
        logToApp("BackgroundService: Updated activeRouteId to: $activeRouteId");
      } else {
        // If no route was provided in the event, use the one from SharedPreferences
        activeRouteId = routeToUse;
        logToApp("BackgroundService: Using route from SharedPreferences: $activeRouteId");
      }

      // Simply start tracking without creating new sockets
      logToApp("BackgroundService: UI startTracking: Starting tracking logic.");
      await _startTrackingLogic(service);
      logToApp("BackgroundService: UI startTracking: Tracking logic initiated.");
      
      // Update SharedPreferences
      await prefs.setBool('location_started', true);
      if (routeIdFromUI != null) {
        await prefs.setString('selectedRoute', routeIdFromUI);
      }
    });

    service.on('stopTracking').listen((event) async {
      logToApp("BackgroundService: Received 'stopTracking' command from UI.");
      
      // Set stopping flag to prevent location updates during stopping process
      isStopping = true;
      
      // Simply stop tracking without disconnecting socket
      logToApp("BackgroundService: UI stopTracking: Stopping tracking logic.");
      await _stopTrackingLogic(service);
      logToApp("BackgroundService: UI stopTracking: Tracking logic stopped.");
      
      // Reset stopping flag after stop logic completes
      isStopping = false;
      
      // Update SharedPreferences
      await prefs.setBool('location_started', false);
    });

    // Listener for manual socket reconnection from UI
    service.on('reconnectSocket').listen((event) async {
      logToApp("RECONNECT: Received 'reconnectSocket' command from UI.");
      
      // Get the route from the event if provided, otherwise from SharedPreferences
      final String? routeFromEvent = event?['route_id'] as String?;
      final String? currentSelectedRouteId = prefs.getString('selectedRoute');
      final String? routeToUse = routeFromEvent ?? currentSelectedRouteId;
      
      // Only reconnect if a route is selected
      if (routeToUse != null) {
        logToApp("RECONNECT: Route to use: $routeToUse (from event: $routeFromEvent, from prefs: $currentSelectedRouteId)");
        
        // Reconnect the persistent socket
        await _connectPersistentSocket(service, routeToUse);
        logToApp("RECONNECT: Manual socket reconnection attempt completed for route: $routeToUse.");
      } else {
        logToApp("RECONNECT: No route selected. Cannot reconnect socket.");
        service.invoke('updateUI', {'isTracking': false, 'status': 'No Route Selected', 'isAdminConnected': false, 'socketId': null});
        _updateNotification(title: "No Route Selected", content: "Select a route to connect.");
      }
    });
    
    // Listener for ping commands (heartbeat checks)
    service.on('ping').listen((event) async {
      logToApp("BackgroundService: Received ping command. Service is alive.");
      // Just log that we received the ping - this confirms the service is running
    });
  });
}
