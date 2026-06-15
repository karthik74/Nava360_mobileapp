/// Shape mirrors the backend's `AuthResponse`.
class AuthUser {
  final String token;
  final String tokenType;
  final int userId;
  final String username;
  final String email;
  final String role; // ADMIN | HR | EMPLOYEE
  final int? employeeId;

  /// Linked employee's name (from the login response) — lets the UI show the
  /// real name immediately without an extra /api/employees call.
  final String? firstName;
  final String? lastName;

  /// All dynamic role names the user holds (e.g. {"HR", "RM"}).
  final Set<String> roles;

  /// Flattened permission names — drives permission-based UI gating
  /// (e.g. show the requisition feature when this contains REQUISITION_CREATE).
  final Set<String> permissions;

  /// Branch IDs this user is scoped to. Empty = no branch restriction
  /// (can see/select all branches).
  final Set<int> branchIds;

  const AuthUser({
    required this.token,
    required this.tokenType,
    required this.userId,
    required this.username,
    required this.email,
    required this.role,
    required this.employeeId,
    this.firstName,
    this.lastName,
    this.roles = const {},
    this.permissions = const {},
    this.branchIds = const {},
  });

  static Set<String> _stringSet(dynamic v) {
    if (v is List) {
      return v.map((e) => e.toString()).toSet();
    }
    return const {};
  }

  static Set<int> _intSet(dynamic v) {
    if (v is List) {
      return v
          .map((e) => e is num ? e.toInt() : int.tryParse(e.toString()))
          .whereType<int>()
          .toSet();
    }
    return const {};
  }

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
        token: j['token'] as String,
        tokenType: (j['tokenType'] as String?) ?? 'Bearer',
        userId: (j['userId'] as num).toInt(),
        username: j['username'] as String,
        email: j['email'] as String,
        role: j['role'] as String,
        employeeId: (j['employeeId'] as num?)?.toInt(),
        firstName: j['firstName'] as String?,
        lastName: j['lastName'] as String?,
        roles: _stringSet(j['roles']),
        permissions: _stringSet(j['permissions']),
        branchIds: _intSet(j['branchIds']),
      );

  Map<String, dynamic> toJson() => {
        'token': token,
        'tokenType': tokenType,
        'userId': userId,
        'username': username,
        'email': email,
        'role': role,
        'employeeId': employeeId,
        'firstName': firstName,
        'lastName': lastName,
        'roles': roles.toList(),
        'permissions': permissions.toList(),
        'branchIds': branchIds.toList(),
      };

  bool hasRole(Iterable<String> roles) =>
      this.roles.any(roles.contains) || roles.contains(role);

  /// True if the user holds the given backend permission.
  bool hasPermission(String permission) => permissions.contains(permission);

  /// Best display name: "First Last" if available, else the username.
  String get displayName {
    final full = '${firstName ?? ''} ${lastName ?? ''}'.trim();
    return full.isNotEmpty ? full : username;
  }
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
