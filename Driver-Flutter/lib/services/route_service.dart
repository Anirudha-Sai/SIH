// lib/services/route_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class RouteService {
  static const String ROUTES_API_URL = "https://dev-bus.vjstartup.com/get-all-routes";
  static const String CACHE_KEY = "cached_routes";
  static const String LAST_FETCH_KEY = "last_routes_fetch";

  // Default routes to use as fallback
  static final List<String> defaultRoutes = [
  'Route-18 (Amritsar to Pathankot)', 
  'Route-18 (Pathankot to Amritsar)', 
  'Route-29 (Chandigarh to Amritsar)', 
  'Route-29 (Amritsar to Chandigarh)', 
  'Route-47 (Ludhiana to Jalandhar)', 
  'Route-47 (Jalandhar to Ludhiana)', 
  'Route-68 (Mohali to Patiala)', 
  'Route-68 (Patiala to Mohali)', 
  'Route-101 (Bathinda to Ferozepur)', 
  'Route-101 (Ferozepur to Bathinda)', 
  'Route-110 (Hoshiarpur to nangal)', 
  'Route-110 (Nangal to Hoshiarpur)', 
  'Route-204 (Jalandhar to Kapurthala)', 
  'Route-204 (Kapurthala to Jalandhar)', 
  'Route-225 (Moga to Faridkot)', 
  'Route-225 (Faridkot to Moga)'
];


  // Get routes - either from cache or by fetching
  Future<List<String>> getRoutes() async {
    // First try to get from cache if it's not time to refresh
    if (!await _shouldRefreshCache()) {
      final cachedRoutes = await _getRoutesFromCache();
      if (cachedRoutes.isNotEmpty) {
        return defaultRoutes; //change to cachedRoutes to return cached routes
      }
    }

    // If we need to refresh or cache is empty, try to fetch
    try {
      final fetchedRoutes = await _fetchRoutes();
      if (fetchedRoutes.isNotEmpty) {
        await _cacheRoutes(fetchedRoutes);
        return fetchedRoutes;
      }
    } catch (e) {
      print("Error fetching routes: $e");
    }

    // If fetch fails, return cached routes (if exist)
    final cachedRoutes = await _getRoutesFromCache();
    if (cachedRoutes.isNotEmpty) {
      return defaultRoutes; //change to cachedRoutes to return cached routes
    }

    // Last resort: return default routes
    return defaultRoutes;
  }

  // Check if cache needs to be refreshed (after 24 hours)
  Future<bool> _shouldRefreshCache() async {
    final prefs = await SharedPreferences.getInstance();
    final lastFetchTime = prefs.getInt(LAST_FETCH_KEY) ?? 0;
    final currentTime = DateTime.now().millisecondsSinceEpoch;
    
    // Return true if 24 hours have passed since last fetch
    return (currentTime - lastFetchTime) > (24 * 60 * 60 * 1000);
  }

  // Get cached routes
  Future<List<String>> _getRoutesFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final routesJson = prefs.getString(CACHE_KEY);
    
    if (routesJson == null) {
      return [];
    }
    
    try {
      final List<dynamic> decodedRoutes = jsonDecode(routesJson);
      return decodedRoutes.map((route) => route.toString()).toList();
    } catch (e) {
      print("Error parsing cached routes: $e");
      return [];
    }
  }

  // Save routes to cache
  Future<void> _cacheRoutes(List<String> routes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(CACHE_KEY, jsonEncode(routes));
    await prefs.setInt(LAST_FETCH_KEY, DateTime.now().millisecondsSinceEpoch);
  }

  // Fetch routes from API
  Future<List<String>> _fetchRoutes() async {
    try {
      final response = await http.get(Uri.parse(ROUTES_API_URL));
      
      if (response.statusCode == 200) {
        final List<dynamic> routesData = jsonDecode(response.body);
        return routesData.map((route) => route.toString()).toList();
      } else {
        print("Failed to fetch routes: ${response.statusCode}");
        return [];
      }
    } catch (e) {
      print("Exception during routes fetch: $e");
      rethrow;
    }
  }

  // Force a refresh of routes from API
  Future<List<String>> refreshRoutes() async {
    try {
      final fetchedRoutes = await _fetchRoutes();
      if (fetchedRoutes.isNotEmpty) {
        await _cacheRoutes(fetchedRoutes);
        return fetchedRoutes;
      }
    } catch (e) {
      print("Error refreshing routes: $e");
    }
    
    return await getRoutes();
  }
}
