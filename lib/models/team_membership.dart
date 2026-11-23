class TeamMembership {
  final String userId;
  final String orgId;
  final String organization;
  final String role;
  final String timezone;
  final DateTime verifiedAt;
  static const offlineWindow = Duration(hours: 24);

  const TeamMembership({required this.userId, required this.orgId,
    required this.organization, required this.role, required this.timezone,
    required this.verifiedAt});

  bool get isAdmin => role == 'admin';
  bool allowsOfflineAt(DateTime now) {
    final age = now.toUtc().difference(verifiedAt.toUtc());
    return !age.isNegative && age <= offlineWindow;
  }

  factory TeamMembership.fromJson(Map<String, dynamic> json, {DateTime? verifiedAt}) {
    final role = json['role'] as String;
    if (role != 'admin' && role != 'guard') throw const FormatException('Unknown role');
    return TeamMembership(userId: json['user_id'] as String, orgId: json['org_id'] as String,
      organization: json['organization'] as String, role: role,
      timezone: json['timezone'] as String? ?? 'Asia/Karachi',
      verifiedAt: verifiedAt ?? DateTime.parse(json['verified_at'] as String));
  }

  Map<String, dynamic> toJson() => {'user_id': userId, 'org_id': orgId,
    'organization': organization, 'role': role, 'timezone': timezone,
    'verified_at': verifiedAt.toUtc().toIso8601String()};
}
