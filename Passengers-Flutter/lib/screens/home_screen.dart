import 'dart:async';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import '../models/bus_location.dart';
import '../utils/local_storage.dart';
import '../utils/jwt_utils.dart';
import '../widgets/tracking_card.dart';
import '../widgets/login_modal.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final WebSocketService _webSocketService = WebSocketService();
  final MapController _mapController = MapController();
  
  List<String> _routes = [];
  String? _selectedRoute;
  String? _userName;
  
  bool _isTrackingCardVisible = false;
  bool _isConnected = false;
  bool _isLoggedIn = false;
  
  BusLocation? _latestBusLocation;
  String _distanceTimeText = '';
  String _lastUpdatedText = '';
  
  final Set<String> _activeRoutes = {};
  
  // Map markers
  final List<Marker> _markers = [];
  final LatLng _fixedLocation = const LatLng(17.5,78.6);
  
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }
  
  @override
  void dispose() {
    _webSocketService.closeConnection();
    super.dispose();
  }
  
  Future<void> _initializeApp() async {
    // Load routes
    _routes = await ApiService.getAllRoutes();
    
    // Load saved route
    final savedRoute = await LocalStorage.getSelectedRoute();
    if (savedRoute != null && _routes.contains(savedRoute)) {
      setState(() {
        _selectedRoute = savedRoute;
      });
    }
    
    // Check if user is logged in
    final user = await LocalStorage.getUser();
    if (user != null) {
      setState(() {
        _isLoggedIn = true;
        _userName = user.familyName;
      });
    }
    
    // Initialize WebSocket
    _initializeWebSocket();
  }
  
  void _initializeWebSocket() {
    _webSocketService.onConnect = () {
      setState(() {
        _isConnected = true;
      });
      
      // Subscribe to selected route if available
      if (_selectedRoute != null) {
        _webSocketService.subscribeToRoute(_selectedRoute!);
      }
    };
    
    _webSocketService.onDisconnect = () {
      setState(() {
        _isConnected = false;
        _activeRoutes.clear();
      });
      
      // Show a message to the user
      // if (mounted) {
      //   ScaffoldMessenger.of(context).showSnackBar(
      //     const SnackBar(content: Text('Disconnected from server. Some features may not work.')),
      //   );
      // }
    };
    
    _webSocketService.onError = (error) {
      print('WebSocket error: $error');
      setState(() {
        _isConnected = false;
      });
      
      // Show a message to the user
      // if (mounted) {
      //   ScaffoldMessenger.of(context).showSnackBar(
      //     const SnackBar(content: Text('Connection error. Some features may not work.')),
      //   );
      // }
    };
    
    _webSocketService.onLocationUpdate = (location) {
      _handleLocationUpdate(location);
    };
    
    _webSocketService.onAllConnectionsUpdate = (connections) {
      setState(() {
        _activeRoutes.clear();
        for (var conn in connections) {
          if (conn['status'] == 'tracking_active') {
            _activeRoutes.add(conn['route_id']);
          }
        }
      });
    };
    
    // Initialize WebSocket connection
    _webSocketService.initWebSocket(routeId: _selectedRoute);
  }
  
  void _handleLocationUpdate(BusLocation location) {
    if (location.routeId != _selectedRoute) return;
    
    setState(() {
      _latestBusLocation = location;
    });
    
    // Update marker on map
    _updateBusMarker(location);
    
    // Update route info
    _updateRouteInfo();
  }
  
  void _updateBusMarker(BusLocation location) {
    setState(() {
      _markers.clear();
      
      // Add fixed marker
      _markers.add(
        Marker(
          point: _fixedLocation,
          width: 80,
          height: 80,
          child: const Icon(
            Icons.flag,
            color: Colors.red,
            size: 40,
          ),
        ),
      );
      
      // Add bus marker if location is available
      if (location.status == 'tracking_active') {
        _markers.add(
          Marker(
            point: LatLng(location.latitude, location.longitude),
            width: 80,
            height: 80,
            child: const Icon(
              Icons.directions_bus,
              color: Colors.blue,
              size: 40,
            ),
          ),
        );
        
        // Auto-center map on first update
        _mapController.move(LatLng(location.latitude, location.longitude), 13);
      }
    });
  }
  
  void _updateRouteInfo() async {
    final user = await LocalStorage.getUser();
    String userName = '';
    
    if (user != null) {
      userName = user.familyName;
    }
    
    setState(() {
      _userName = userName;
    });
  }
  
  void _onRouteChanged(String? newValue) {
    if (newValue == null) return;
    
    // Unsubscribe from previous route
    if (_selectedRoute != null) {
      _webSocketService.unsubscribeFromRoute(_selectedRoute!);
    }
    
    setState(() {
      _selectedRoute = newValue;
    });
    
    // Save selected route
    LocalStorage.saveSelectedRoute(newValue);
    
    // Subscribe to new route
    _webSocketService.subscribeToRoute(newValue);
    
    // Update route info
    _updateRouteInfo();
    
    // Hide distance/time info
    setState(() {
      _distanceTimeText = '';
      _lastUpdatedText = '';
    });
    
    // Remove previous markers
    setState(() {
      _markers.clear();
      _markers.add(
        Marker(
          point: _fixedLocation,
          width: 80,
          height: 80,
          child: const Icon(
            Icons.flag,
            color: Colors.red,
            size: 40,
          ),
        ),
      );
    });
  }
  
  void _showTrackingCard() {
    setState(() {
      _isTrackingCardVisible = true;
    });
  }
  
  void _hideTrackingCard() {
    setState(() {
      _isTrackingCardVisible = false;
    });
  }
  
  Future<void> _findDistance() async {
    if (_latestBusLocation == null) return;
    
    try {
      // In a real app, you would get the user's location here
      // For now, we'll just show a placeholder
      setState(() {
        _distanceTimeText = '📏 Distance: 0.1km | ⏳ ETA: 0min 30sec';
        _lastUpdatedText = 'Last updated: ${DateTime.now().toLocal().toString().split('.')[0]}';
      });
    } catch (e) {
      print('Error calculating distance: $e');
    }
  }
  
  void _recenterMap() {
    if (_latestBusLocation != null) {
      _mapController.move(
        LatLng(_latestBusLocation!.latitude, _latestBusLocation!.longitude),
        13,
      );
    } else {
      _mapController.move(
        _fixedLocation,
        10,
      );
    }
  }
  
  void _handleLogin() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return const LoginModal();
      },
    );
  }
  
  void _handleLogout() {
    // Perform logout
    LocalStorage.removeUser();
    setState(() {
      _isLoggedIn = false;
      _userName = '';
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Flutter Map
          SizedBox(
            width: double.infinity,
            height: MediaQuery.of(context).size.height,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _fixedLocation,
                initialZoom: 10,
                maxZoom: 18,
                minZoom: 10,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.bus_tracking_app',
                ),
                MarkerLayer(
                  markers: _markers,
                ),
              ],
            ),
          ),
          
          // Route info
          Positioned(
            top: 40,
            left: MediaQuery.of(context).size.width * 0.3,
            width: MediaQuery.of(context).size.width * 0.4,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                _selectedRoute != null 
                    ? 'Hello ${_userName ?? ''}👋\nTracking ${_selectedRoute!.split(' (')[0]} ${_latestBusLocation?.status == 'tracking_active' ? '🟢' : '🔴'}'
                    : 'Hello ${_userName ?? ''}👋\nNo Route Being Tracked 🔴',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  height: 1.3,
                ),
              ),
            ),
          ),
          
          // Login/Logout button
          Positioned(
            top: 40,
            right: 20,
            child: ElevatedButton(
              onPressed: _isLoggedIn ? _handleLogout : _handleLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isLoggedIn ? Colors.red : Colors.green,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
                padding: const EdgeInsets.all(0),
                minimumSize: const Size(60, 50),
              ),
              child: Text(
                _isLoggedIn ? 'Logout' : 'Login',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          
          // Tracking card
          if (_isTrackingCardVisible)
            Positioned(
              bottom: 80,
              left: 20,
              right: 20,
              child: TrackingCard(
                routes: _routes,
                activeRoutes: _activeRoutes,
                selectedRoute: _selectedRoute,
                onRouteChanged: _onRouteChanged,
                onFindDistance: _findDistance,
                onHideCard: _hideTrackingCard,
                distanceTimeText: _distanceTimeText,
                lastUpdatedText: _lastUpdatedText,
              ),
            ),
          
          // Floating recenter button
          Positioned(
            bottom: 80,
            right: 20,
            child: FloatingActionButton(
              onPressed: _recenterMap,
              backgroundColor: Colors.white,
              child: const Text(
                '⟲',
                style: TextStyle(
                  fontSize: 20,
                  color: Colors.blue,
                ),
              ),
            ),
          ),
        ],
      ),
      // Show tracking card toggle button when card is hidden
      floatingActionButton: !_isTrackingCardVisible
          ? FloatingActionButton(
              onPressed: _showTrackingCard,
              backgroundColor: Colors.blue,
              child: const Icon(
                Icons.directions_bus,
                color: Colors.white,
              ),
            )
          : null,
    );
  }
}
