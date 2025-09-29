class User {
  final String name;
  final String email;
  final String rollNo;
  final String familyName;
  final String token;

  User({
    required this.name,
    required this.email,
    required this.rollNo,
    required this.familyName,
    required this.token,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      rollNo: json['roll_no'] ?? '',
      familyName: json['family_name'] ?? '',
      token: json['token'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'email': email,
      'roll_no': rollNo,
      'family_name': familyName,
      'token': token,
    };
  }

  // Create a User object from a JWT token payload
  factory User.fromJwtPayload(Map<String, dynamic> payload) {
    return User(
      name: payload['name'] ?? '',
      email: payload['email'] ?? '',
      rollNo: payload['roll_no'] ?? '',
      familyName: payload['family_name'] ?? '',
      token: payload['token'] ?? '',
    );
  }
}
