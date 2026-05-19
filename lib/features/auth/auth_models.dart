/// Shape mirrors the backend's `AuthResponse`.
class AuthUser {
  final String token;
  final String tokenType;
  final int userId;
  final String username;
  final String email;
  final String role; // ADMIN | HR | EMPLOYEE
  final int? employeeId;

  const AuthUser({
    required this.token,
    required this.tokenType,
    required this.userId,
    required this.username,
    required this.email,
    required this.role,
    required this.employeeId,
  });

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
        token: j['token'] as String,
        tokenType: (j['tokenType'] as String?) ?? 'Bearer',
        userId: (j['userId'] as num).toInt(),
        username: j['username'] as String,
        email: j['email'] as String,
        role: j['role'] as String,
        employeeId: (j['employeeId'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'token': token,
        'tokenType': tokenType,
        'userId': userId,
        'username': username,
        'email': email,
        'role': role,
        'employeeId': employeeId,
      };

  bool hasRole(Iterable<String> roles) => roles.contains(role);
}

class LoginRequest {
  /// Backend field name is `username` but it also accepts an email.
  final String username;
  final String password;
  const LoginRequest({required this.username, required this.password});

  Map<String, dynamic> toJson() => {
        'username': username,
        'password': password,
      };
}
