// lib/screens/home_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/background_service.dart';
import '../services/route_service.dart';
import '../utils/constants.dart';
import '../utils/permissions_helper.dart';
import '../utils/logger.dart';
import 'package:send_to_background/send_to_background.dart';
import 'package:flutter/services.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool? isTracking;
  String statusMessage = "Checking...";
  String? selectedRouteId;
  String? socketId; // Add socket ID variable
  List<String> routes = [];
  bool isLoadingRoutes = true;

  bool isAdminConnected = false; // This state will be updated by the background service

  final RouteService _routeService = RouteService();
  Timer? _longPressTimer;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }


  Future<void> _initialize() async {
    logToApp("HomeScreen: Initializing...");
    await _loadPersistedState();
    _listenToBackgroundService();
    await _loadRoutes();
    await _loadSelectedRoute();
    await PermissionsHelper.checkAndRequestPermissions();

    // 🔥 Restart tracking if flag is true (if service wasn't already running with it)
    if (isTracking == true && selectedRouteId != null) {
      logToApp("HomeScreen: Auto-restarting tracking service on app relaunch...");
      final service = FlutterBackgroundService();
      // Pass the route_id when starting tracking
      service.invoke("startTracking", {'route_id': selectedRouteId});
    } else {
      logToApp("HomeScreen: Not auto-starting tracking. isTracking=$isTracking, selectedRouteId=$selectedRouteId");
    }

    if (mounted) setState(() => isLoadingRoutes = false);
    logToApp("HomeScreen: Initialization complete. isLoadingRoutes=$isLoadingRoutes");
  }


  Future<void> _loadPersistedState() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        isTracking = prefs.getBool('location_started') ?? false;
        statusMessage = isTracking! ? "Connected" : "Stopped";
        logToApp("HomeScreen: Loaded persisted state: isTracking=$isTracking, statusMessage=$statusMessage");
      });
    }
  }

  void _listenToBackgroundService() {
    FlutterBackgroundService().on('updateUI').listen((event) {
      if (mounted && event != null) {
        final bool newTrackingState = event['isTracking'] ?? isTracking!;
        final String newStatus = event['status'] ?? statusMessage;
        final bool newAdminConnectedState = event['isAdminConnected'] ?? isAdminConnected;
        final String? newSocketId = event['socketId']; // Get socket ID from event

        setState(() {
          isTracking = newTrackingState;
          statusMessage = newStatus;
          isAdminConnected = newAdminConnectedState;
          socketId = newSocketId; // Update socket ID
        });

        logToApp("Service Update received: Tracking=$newTrackingState, Status=$newStatus, AdminConnected=$newAdminConnectedState, SocketId=$newSocketId");
      } else {
        logToApp("Service Update event is null or widget not mounted.");
      }
    });
  }

  Future<void> _loadRoutes() async {
    logToApp("HomeScreen: Loading routes...");
    try {
      final loadedRoutes = await _routeService.getRoutes();
      if (mounted) setState(() => routes = loadedRoutes);
      logToApp("HomeScreen: Routes loaded: ${routes.join(', ')}");
    } catch (e) {
      logToApp("HomeScreen: Error loading routes: $e");
    }
  }

  Future<void> _loadSelectedRoute() async {
    logToApp("HomeScreen: Loading selected route...");
    final prefs = await SharedPreferences.getInstance();
    final storedRouteId = prefs.getString("selectedRoute");
    if (storedRouteId != null && routes.contains(storedRouteId)) {
      selectedRouteId = storedRouteId;
      logToApp("HomeScreen: Found stored selected route: $selectedRouteId");
    } else if (routes.isNotEmpty) {
      selectedRouteId = null;
      logToApp("HomeScreen: No valid stored route found. selectedRouteId set to null.");
    } else {
      logToApp("HomeScreen: No routes available to select.");
    }
    if (mounted) setState(() {});
  }

  Future<void> _onRouteChanged(String? newRoute) async {
    if (newRoute == null || newRoute == selectedRouteId) {
      logToApp("HomeScreen: Route change ignored. newRoute=$newRoute, selectedRouteId=$selectedRouteId");
      return;
    }

    logToApp("HomeScreen: Route change requested: $newRoute");

    if (isTracking == true) {
      logToApp("HomeScreen: Tracking is active. Stopping tracking before switching routes.");
      final service = FlutterBackgroundService();
      service.invoke("stopTracking");
      // Wait for tracking to stop
      await Future.delayed(const Duration(milliseconds: 500));
    }

    setState(() => selectedRouteId = newRoute);
    logToApp("HomeScreen: Selected route updated to: $selectedRouteId");
    
    // Notify background service about the new route selection
    logToApp("HomeScreen: Notifying background service about new route selection: $newRoute");
    
    FlutterBackgroundService().invoke("routeSelected", {'route_id': newRoute});
  }

  Future<void> _toggleTracking() async {
    logToApp("HomeScreen: _toggleTracking called. Current isTracking=$isTracking");
    final service = FlutterBackgroundService();
    if (isTracking == true) {
      logToApp("HomeScreen: Invoking stopTracking.");
      service.invoke("stopTracking");
    } else {
      if (selectedRouteId == null) {
        logToApp("HomeScreen: Cannot start tracking: No route selected.");
        // ScaffoldMessenger.of(context).showSnackBar(
        //   const SnackBar(content: Text('Please select a route first.')),
        // );
        return;
      }
      logToApp("HomeScreen: Checking and requesting permissions and battery optimizations.");
      await PermissionsHelper.checkAndRequestPermissions();
      logToApp("HomeScreen: Invoking startTracking with route_id: $selectedRouteId");
      // Pass the route_id when starting tracking
      service.invoke("startTracking", {'route_id': selectedRouteId});
    }
  }

  // Method to handle manual socket reconnection
  Future<void> _onReconnectSocket() async {
    logToApp("HomeScreen: 'Reconnect Socket' button clicked.");
    if (selectedRouteId == null) {
      // ScaffoldMessenger.of(context).showSnackBar(
      //   const SnackBar(content: Text('Please select a route first to reconnect.')),
      // );
      logToApp("HomeScreen: Cannot reconnect: No route selected.");
      return;
    }
    logToApp("HomeScreen: Invoking 'reconnectSocket' command for route: $selectedRouteId");
    // Pass the route_id when reconnecting socket
    FlutterBackgroundService().invoke("reconnectSocket", {'route_id': selectedRouteId});
    // ScaffoldMessenger.of(context).showSnackBar(
    //   SnackBar(content: Text('Attempting to reconnect socket for route: $selectedRouteId')),
    // );
  }

  Future<void> _onDisconnectSocket() async {
      if (currentSocket != null) {
      logToApp("BackgroundService: Attempting to fully destroy main socket during cleanup.");
      try {
        currentSocket!.offAny();
        currentSocket!.disconnect();
        currentSocket!.close();
        currentSocket!.destroy(); // Explicitly destroy the socket on full service shutdown
        currentSocket = null;
        logToApp("BackgroundService: Main socket completely destroyed during cleanup.");
      } catch (e) {
        logToApp("BackgroundService: Error destroying socket during cleanup: $e");
      }
    }
  }


  void _showLogsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Logs"),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: FutureBuilder<List<String>>(
            future: loadLogsFromStorage(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              
              if (snapshot.hasError) {
                return const Center(child: Text("Error loading logs"));
              }
              
              final logs = snapshot.data ?? [];
              
              return Scrollbar(
                child: ListView.builder(
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    return Text(logs[index], style: const TextStyle(fontSize: 12));
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            child: const Text("Clear Logs"),
            onPressed: () {
              clearLogsFromStorage(); // Clear logs from both memory and storage
              setState(() {}); // Refresh the UI
              Navigator.pop(context); // Close the dialog
              // ScaffoldMessenger.of(context).showSnackBar(
              //   const SnackBar(content: Text('Logs cleared successfully')),
              // );
            },
          ),
          TextButton(
            child: const Text("Close"),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Color statusColor = Colors.grey;
    if (isTracking == true) statusColor = Colors.green.shade800;
    if (isTracking == false) statusColor = Colors.red.shade800;

    return WillPopScope(
      onWillPop: () async {
        logToApp("HomeScreen: WillPopScope triggered, sending app to background.");
        SendToBackground.sendToBackground();
        return false;
      },
    child: Scaffold(
      appBar: AppBar(centerTitle: true,
      title: GestureDetector(
        onDoubleTap: _onReconnectSocket, // Calls the recc function on double tap
        child: const Text("Punjab Driver"),
      ),),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoadingRoutes)
                const CircularProgressIndicator()
              else
                DropdownButton<String?>(
                  value: selectedRouteId,
                  hint: const Text("Select a Route"),
                  isExpanded: true,
                  items: routes.map((r) {
                    return DropdownMenuItem(
                      value: r,
                      child: Text(r, style: const TextStyle(fontSize: 18)),
                    );
                  }).toList(),
                  onChanged: (isTracking == true) // Disable dropdown if tracking
                      ? null
                      : (route) {
                          logToApp("HomeScreen: Dropdown route changed to: $route");
                          _onRouteChanged(route);
                        },
                ),
              const SizedBox(height: 40),
              // Text(
              //   statusMessage,
              //   style: TextStyle(
              //     fontSize: 22,
              //     fontWeight: FontWeight.bold,
              //     color: statusColor,
              //   ),
              // ),
              Text(
                isAdminConnected ? "Connected" : "Disconnected",
                style: TextStyle(
                  fontSize: 20,
                  color: isAdminConnected ? Colors.green : Colors.red,
                ),
              ),
              if (socketId != null)
                Text(
                  "Socket ID: ${socketId!.substring(0, 8)}...",
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              const SizedBox(height: 30),
              GestureDetector(
                onTap: _toggleTracking,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    color: isTracking == true
                        ? Colors.red.shade700
                        : Colors.green.shade700,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: isTracking == null
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          isTracking == true ? "STOP" : "START",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 1),
                child: Text(
                  "Route Selected: ${selectedRouteId ?? 'Not set'}",
                  style: const TextStyle(
                    fontSize: 20,
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    )
  );}
}
