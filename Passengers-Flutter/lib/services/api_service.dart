import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiService {
  static final String baseUrl = dotenv.env['BASE_URL'] ?? 'https://dev-auth.vjstartup.com';
  static final String socketUrl ='wss://dev-bus.vjstartup.com';
  static final String apiKey = dotenv.env['API_KEY'] ?? '';
  static final String clientId = dotenv.env['CLIENT_ID'] ?? '';
  
  // Get TomTom API key
  static Future<String> getTomTomApiKey() async {
    return apiKey;
  }

  // Get Google Client ID
  static Future<String> getGoogleClientId() async {
    return clientId;
  }

  // Get all routes
  static Future<List<String>> getAllRoutes() async {
    try {
      final routesString = dotenv.env['ALL_ROUTES'] ?? '[]';
      final routes = jsonDecode(routesString) as List;
      return routes.map((route) => route.toString()).toList();
    } catch (e) {
      print('Error fetching routes: $e');
      return [];
    }
  }

  // Google authentication
  static Future<Map<String, dynamic>?> googleAuth(String token) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/google'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': token}),
        // Note: In a real app, you'd need to handle cookies properly
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print('Google auth failed with status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error during Google authentication: $e');
      return null;
    }
  }

  // Logout
  static Future<bool> logout() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/logout'),
        // Note: In a real app, you'd need to handle cookies properly
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error during logout: $e');
      return false;
    }
  }

  // Get distance and time using TomTom API
  static Future<Map<String, dynamic>?> getDistanceTime(String origin, String destination) async {
    try {
      final apiKey = await getTomTomApiKey();
      
      // Parse coordinates
      final originCoords = origin.split(',');
      final destCoords = destination.split(',');
      
      if (originCoords.length != 2 || destCoords.length != 2) {
        print('Invalid coordinate format');
        return null;
      }
      
      // Correct the order (lat,lng) for TomTom API
      final correctedOrigin = '${originCoords[1]},${originCoords[0]}';
      final correctedDestination = '${destCoords[1]},${destCoords[0]}';
      
      final url = 'https://api.tomtom.com/routing/1/calculateRoute/'
          '$correctedOrigin:$correctedDestination/json'
          '?key=$apiKey&traffic=true&routeType=fastest';
      
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print('Distance API failed with status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error fetching distance and time: $e');
      return null;
    }
  }
}
