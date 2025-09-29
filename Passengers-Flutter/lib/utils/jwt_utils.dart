import 'dart:convert';

class JwtUtils {
  // Decode a JWT token
  static Map<String, dynamic> decodeJwt(String token) {
    try {
      // Check if token has the correct format
      final parts = token.split('.');
      if (parts.length != 3) {
        return {};
      }
      
      // Decode the payload (second part)
      final payload = parts[1];
      
      // Add padding if needed
      final normalized = base64.normalize(payload);
      
      // Decode from base64
      final decoded = utf8.decode(base64.decode(normalized));
      
      // Parse JSON
      return jsonDecode(decoded);
    } catch (e) {
      print('Error decoding JWT: $e');
      return {};
    }
  }
  
  // Get user name from JWT token
  static String getUserNameFromJwt(String token) {
    final payload = decodeJwt(token);
    return payload['family_name'] ?? payload['name'] ?? '';
  }
  
  // Get user email from JWT token
  static String getUserEmailFromJwt(String token) {
    final payload = decodeJwt(token);
    return payload['email'] ?? '';
  }
  
  // Get roll number from JWT token
  static String getRollNoFromJwt(String token) {
    final payload = decodeJwt(token);
    return payload['roll_no'] ?? '';
  }
  
  // Check if token is valid
  static bool isTokenValid(String token) {
    try {
      final payload = decodeJwt(token);
      if (payload.isEmpty) return false;
      
      // Check if token has expired
      final exp = payload['exp'];
      if (exp == null) return true; // No expiration time
      
      final expirationTime = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      return expirationTime.isAfter(DateTime.now());
    } catch (e) {
      return false;
    }
  }
}
