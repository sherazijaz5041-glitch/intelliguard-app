import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/team_membership.dart';

class SecureSessionStorage extends LocalStorage {
  static const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true));
  static Future<void> _sessionWrites = Future<void>.value();
  static Future<void> _writeSession(Future<void> Function() action) {
    final result = _sessionWrites.then((_) => action());
    _sessionWrites = result.catchError((Object _) {});
    return result;
  }
  String get _key => 'ig_${SupabaseConfig.projectKey}_session';
  static String _memberKey(String userId) => 'ig_${SupabaseConfig.projectKey}_member_$userId';

  @override
  Future<void> initialize() async {}
  @override
  Future<String?> accessToken() async {
    await _sessionWrites;
    return storage.read(key: _key);
  }
  @override
  Future<bool> hasAccessToken() async {
    await _sessionWrites;
    return storage.containsKey(key: _key);
  }
  @override
  Future<void> persistSession(String persistSessionString) => _writeSession(
    () => storage.write(key: _key, value: persistSessionString));
  @override
  Future<void> removePersistedSession() => _writeSession(() => storage.delete(key: _key));

  static Future<void> saveMembership(TeamMembership member) => storage.write(
    key: _memberKey(member.userId), value: jsonEncode(member.toJson()));
  static Future<void> forgetMembership(String userId) => storage.delete(key: _memberKey(userId));
  static Future<TeamMembership?> readMembership(String userId) async {
    final value = await storage.read(key: _memberKey(userId));
    if (value == null) return null;
    try {
      final member = TeamMembership.fromJson(Map<String, dynamic>.from(jsonDecode(value) as Map));
      return member.userId == userId && member.allowsOfflineAt(DateTime.now()) ? member : null;
    } on FormatException { return null; }
      on TypeError { return null; }
  }
}
