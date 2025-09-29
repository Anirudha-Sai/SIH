class BusLocation {
  final String routeId;
  final double latitude;
  final double longitude;
  final String status; // tracking_active or stopped
  final DateTime timestamp;

  BusLocation({
    required this.routeId,
    required this.latitude,
    required this.longitude,
    required this.status,
    required this.timestamp,
  });

  factory BusLocation.fromJson(Map<String, dynamic> json) {
    return BusLocation(
      routeId: json['route_id'] ?? '',
      latitude: json['latitude']?.toDouble() ?? 0.0,
      longitude: json['longitude']?.toDouble() ?? 0.0,
      status: json['status'] ?? 'stopped',
      timestamp: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'route_id': routeId,
      'latitude': latitude,
      'longitude': longitude,
      'status': status,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
