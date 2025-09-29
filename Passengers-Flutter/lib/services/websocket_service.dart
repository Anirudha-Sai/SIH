import 'dart:convert';
import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/bus_location.dart';

class WebSocketService {
  final String socketUrl = dotenv.env['SOCKET_URL'] ?? 'wss://dev-bus.vjstartup.com';
  
  io.Socket? _socket;
  String? _selectedRoute;
  String? _userRole;
  bool _isConnected = false;
  bool _shouldReconnect = true;
  Timer? _reconnectTimer;
  
  // Callbacks for handling events
  Function(BusLocation)? onLocationUpdate;
  Function(List<dynamic>)? onAllConnectionsUpdate;
  Function()? onConnect;
  Function()? onDisconnect;
  Function(String)? onError;
  
  // Create socket with improved reconnection logic
  io.Socket _createSocket(String url, String role, String routeId) {
    print('BackgroundService: Creating socket with URL: $url, role: $role, routeId: $routeId');
    final socket = io.io(
      url,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setQuery({'role': role, 'route_id': routeId})
          .enableReconnection()         // Enable automatic reconnection
          .setReconnectionAttempts(999) // High number for persistent reconnection
          .setReconnectionDelay(2000)   // Start retrying after 2 seconds
          .setReconnectionDelayMax(10000) // Max delay of 10 seconds
          .build(),
    );
    print('BackgroundService: Socket created successfully');
    return socket;
  }
  
  // Connect with persistent socket logic
  Future<void> _connectPersistentSocket(String? routeId) async {
    // If socket exists, destroy it first to ensure clean connection
    if (_socket != null) {
      try {
        _socket!.offAny();
        _socket!.disconnect();
        _socket!.close();
        _socket!.destroy();
        _socket = null;
      } catch (e) {
        print('SOCKET: Error destroying old socket: $e');
      }
    }
    
    // Create new socket with improved reconnection logic
    _socket = _createSocket(socketUrl, _userRole ?? 'Student', routeId ?? '');
    
    // Set up event listeners (keeping all existing events unchanged)
    _setupEventListeners(routeId);
    
    // Connect to the server
    _socket?.connect();
  }
  
  // Setup event listeners (keeping all existing events unchanged)
  void _setupEventListeners(String? routeId) {
    // Set up event listeners
    _socket?.onConnect((_) {
      print('Socket.IO connected');
      _isConnected = true;
      onConnect?.call();
      
      // If we have a selected route, subscribe to it
      if (routeId != null && routeId.isNotEmpty) {
        subscribeToRoute(routeId);
      }
    });
    
    _socket?.onDisconnect((_) {
      print('Socket.IO disconnected');
      _isConnected = false;
      onDisconnect?.call();
      _attemptReconnect();
    });
    
    _socket?.onError((error) {
      print('Socket.IO error: $error');
      _isConnected = false;
      onError?.call(error.toString());
      _attemptReconnect();
    });
    
    // Set up custom event listeners
    _socket?.on('location_update', (data) {
      try {
        final location = BusLocation.fromJson(data);
        onLocationUpdate?.call(location);
      } catch (e) {
        print('Error handling location_update: $e');
      }
    });
    
    _socket?.on('all_connections_update', (data) {
      try {
        onAllConnectionsUpdate?.call(data['connections'] ?? []);
      } catch (e) {
        print('Error handling all_connections_update: $e');
      }
    });
    
    _socket?.on('subscribed', (data) {
      print('Subscribed to route: ${data['route']}');
    });
    
    _socket?.on('unsubscribed', (data) {
      print('Unsubscribed from route: ${data['route']}');
    });
  }
  
  // Initialize WebSocket connection
  void initWebSocket({String? routeId, String role = 'Student'}) {
    try {
      _selectedRoute = routeId;
      _userRole = role;
      
      // Cancel any existing reconnect timer
      _reconnectTimer?.cancel();
      
      // Connect with persistent socket logic
      _connectPersistentSocket(routeId);
    } catch (e) {
      print('Error initializing Socket.IO: $e');
      _isConnected = false;
      onError?.call(e.toString());
      _attemptReconnect();
    }
  }
  
  // Attempt to reconnect with exponential backoff
  void _attemptReconnect() {
    if (!_shouldReconnect) return;
    
    // Cancel any existing reconnect timer
    _reconnectTimer?.cancel();
    
    // Try to reconnect after a delay
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      print('Attempting to reconnect Socket.IO...');
      initWebSocket(routeId: _selectedRoute, role: _userRole ?? 'Student');
    });
  }
  
  // Subscribe to a route
  void subscribeToRoute(String routeId) {
    _socket?.emit('subscribe', {
      'route_id': routeId,
    });
  }
  
  // Unsubscribe from a route
  void unsubscribeFromRoute(String routeId) {
    _socket?.emit('unsubscribe', {
      'route_id': routeId,
    });
  }

  // Close WebSocket connection
  void closeConnection() {
    _socket?.disconnect();
    _socket?.close();
    _socket = null;
  }
  
  // Check if connected
  bool get isConnected => _socket?.connected ?? false;
}
