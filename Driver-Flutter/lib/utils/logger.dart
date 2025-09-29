import 'package:shared_preferences/shared_preferences.dart';

// In-memory cache for logs to avoid frequent disk reads
List<String> appLogs = [];

void logToApp(String message) async {
  // // Add timestamp
  // final now = DateTime.now();
  // final timestamp = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
  // final entry = "[$timestamp] $message";
  
  // // Add to in-memory cache
  // appLogs.insert(0, entry);
  
  // // Limit in-memory cache size
  // if (appLogs.length > 500) {
  //   appLogs.removeLast();
  // }
  
  // // Also save to shared preferences for persistence across processes
  // try {
  //   final prefs = await SharedPreferences.getInstance();
  //   final List<String> storedLogs = prefs.getStringList('app_logs') ?? [];
  //   storedLogs.insert(0, entry);
    
  //   // Limit stored logs size
  //   if (storedLogs.length > 500) {
  //     storedLogs.removeRange(500, storedLogs.length);
  //   }
    
  //   await prefs.setStringList('app_logs', storedLogs);
  // } catch (e) {
  //   // If we can't save to shared preferences, just print the error
  //   print("Error saving log to SharedPreferences: $e");
  // }
  
  // // Print to console
  // print(entry);
}

// Function to load logs from shared preferences (for UI display)
Future<List<String>> loadLogsFromStorage() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('app_logs') ?? [];
  } catch (e) {
    print("Error loading logs from SharedPreferences: $e");
    return [];
  }
}

// Function to clear logs from storage
Future<void> clearLogsFromStorage() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('app_logs');
    appLogs.clear();
  } catch (e) {
    print("Error clearing logs from SharedPreferences: $e");
  }
}
