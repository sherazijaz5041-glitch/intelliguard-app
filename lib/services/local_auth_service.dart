// ============================================================
// local_auth_service.dart - Local, on-device account system.
// No cloud auth (this build is fully offline by design), but real
// enough to be worth doing properly: passwords are never stored in
// plaintext — only a salted SHA-256 hash, via SharedPreferences.
// ============================================================
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalAuthService {
  static const _kUsernameKey = 'auth_username';
  static const _kPasswordHashKey = 'auth_password_hash';
  static const _kSaltKey = 'auth_salt';

  /// Whether a local account has ever been created on this device.
  static Future<bool> hasAccount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_kUsernameKey) && prefs.containsKey(_kPasswordHashKey);
  }

  static Future<String?> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kUsernameKey);
  }

  static String _randomSalt([int length = 16]) {
    final rand = Random.secure();
    final bytes = List<int>.generate(length, (_) => rand.nextInt(256));
    return base64UrlEncode(bytes);
  }

  static String _hash(String password, String salt) {
    return sha256.convert(utf8.encode('$salt:$password')).toString();
  }

  /// First-time setup: creates the one local account this device will use.
  static Future<void> createAccount({required String username, required String password}) async {
    final prefs = await SharedPreferences.getInstance();
    final salt = _randomSalt();
    await prefs.setString(_kUsernameKey, username);
    await prefs.setString(_kSaltKey, salt);
    await prefs.setString(_kPasswordHashKey, _hash(password, salt));
  }

  /// Returns true if [username] + [password] match the stored account.
  static Future<bool> verifyLogin({required String username, required String password}) async {
    final prefs = await SharedPreferences.getInstance();
    final storedUsername = prefs.getString(_kUsernameKey);
    final salt = prefs.getString(_kSaltKey);
    final storedHash = prefs.getString(_kPasswordHashKey);
    if (storedUsername == null || salt == null || storedHash == null) return false;
    if (storedUsername != username) return false;
    return _hash(password, salt) == storedHash;
  }

  /// Verifies [currentPassword], then updates username and/or password.
  /// Pass null for newUsername/newPassword to leave that field unchanged.
  /// Returns false if currentPassword doesn't match (nothing is changed).
  static Future<bool> updateAccount({
    required String currentPassword,
    String? newUsername,
    String? newPassword,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final storedUsername = prefs.getString(_kUsernameKey);
    final salt = prefs.getString(_kSaltKey);
    final storedHash = prefs.getString(_kPasswordHashKey);
    if (storedUsername == null || salt == null || storedHash == null) return false;
    if (_hash(currentPassword, salt) != storedHash) return false;

    if (newUsername != null && newUsername.trim().isNotEmpty) {
      await prefs.setString(_kUsernameKey, newUsername.trim());
    }
    if (newPassword != null && newPassword.isNotEmpty) {
      final newSalt = _randomSalt();
      await prefs.setString(_kSaltKey, newSalt);
      await prefs.setString(_kPasswordHashKey, _hash(newPassword, newSalt));
    }
    return true;
  }
}
