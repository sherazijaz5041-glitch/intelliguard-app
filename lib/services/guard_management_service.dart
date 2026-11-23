import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class GuardManagementService {
  GuardManagementService._();

  static const _guardsKey = 'ig_campus_guards_roster_v1';
  static const _activitiesKey = 'ig_admin_activity_log_v1';

  static final List<Map<String, dynamic>> _defaultGuards = [];

  static final List<Map<String, dynamic>> _defaultActivities = [
    {
      'title': 'AI Engine Initialized',
      'details': 'TFLite models loaded for Fire, Smoke, and Violence detection.',
      'type': 'ai',
      'time': 'System start',
    },
  ];

  static Future<List<Map<String, dynamic>>> getGuards() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_guardsKey);
    if (raw == null) return []; // No seed — start fresh from Supabase
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveGuards(List<Map<String, dynamic>> guards) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_guardsKey, jsonEncode(guards));
  }

  static Future<void> addGuard({
    required String name,
    required String email,
    required String role,
    String shift = 'Day Shift',
    String phone = '',
    String badge = '',
  }) async {
    final guards = await getGuards();
    final cleanEmail = email.trim().toLowerCase();
    guards.removeWhere((g) => (g['email'] as String).toLowerCase() == cleanEmail);
    guards.insert(0, {
      'name': name.trim(),
      'email': cleanEmail,
      'role': role,
      'shift': shift,
      'phone': phone.trim(),
      'badge': badge.trim().isNotEmpty ? badge.trim() : 'SEC-${100 + guards.length}',
      'active': true,
      'joined': DateTime.now().toLocal().toString().split(' ').first,
    });
    await saveGuards(guards);
    await logActivity('Guard Added', 'Added $name ($role) with badge ${badge.trim().isNotEmpty ? badge : 'assigned'}.', type: 'guard');
  }

  static Future<void> updateGuard(String email, {String? role, bool? active, String? shift}) async {
    final guards = await getGuards();
    final cleanEmail = email.trim().toLowerCase();
    for (final g in guards) {
      if ((g['email'] as String).toLowerCase() == cleanEmail) {
        if (role != null) g['role'] = role;
        if (active != null) g['active'] = active;
        if (shift != null) g['shift'] = shift;
        break;
      }
    }
    await saveGuards(guards);
    await logActivity('Guard Status Changed', 'Updated profile/status for $cleanEmail.', type: 'guard');
  }

  static Future<void> removeGuard(String email) async {
    final guards = await getGuards();
    final cleanEmail = email.trim().toLowerCase();
    guards.removeWhere((g) => (g['email'] as String).toLowerCase() == cleanEmail);
    await saveGuards(guards);
    await logActivity('Guard Removed', 'Removed account for $cleanEmail.', type: 'guard');
  }

  static Future<List<Map<String, dynamic>>> getActivities() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_activitiesKey);
    if (raw == null) {
      await prefs.setString(_activitiesKey, jsonEncode(_defaultActivities));
      return List<Map<String, dynamic>>.from(_defaultActivities);
    }
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return List<Map<String, dynamic>>.from(_defaultActivities);
    }
  }

  static Future<void> logActivity(String title, String details, {String type = 'general'}) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getActivities();
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    list.insert(0, {
      'title': title,
      'details': details,
      'type': type,
      'time': 'Just now ($timeStr)',
    });
    if (list.length > 50) list.removeRange(50, list.length);
    await prefs.setString(_activitiesKey, jsonEncode(list));
  }
}
