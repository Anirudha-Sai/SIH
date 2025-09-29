import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';

class LocalStorage {
  static const String _selectedRouteKey = 'busApplicationSelectedRouteByStudent';
  static const String _userKey = 'user';
  
  // Save selected route
  static Future<void> saveSelectedRoute(String route) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedRouteKey, route);
  }
  
  // Get selected route
  static Future<String?> getSelectedRoute() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_selectedRouteKey);
  }
  
  // Remove selected route
  static Future<void> removeSelectedRoute() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_selectedRouteKey);
  }
  
  // Save user data
  static Future<void> saveUser(User user) async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = jsonEncode(user.toJson());
    await prefs.setString(_userKey, userJson);
  }
  
  // Get user data
  static Future<User?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(_userKey);
    
    if (userJson != null) {
      try {
        final userMap = jsonDecode(userJson);
        return User.fromJson(userMap);
      } catch (e) {
        print('Error decoding user data: $e');
        return null;
      }
    }
    
    return null;
  }
  
  // Remove user data
  static Future<void> removeUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
  }
  
  // Clear all data
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
