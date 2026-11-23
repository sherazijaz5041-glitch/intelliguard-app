import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/team_membership.dart';
import '../services/cloud_api.dart';
import '../services/local_db_service.dart';
import '../services/notification_service.dart';
import '../services/secure_session_storage.dart';

class AuthProvider extends ChangeNotifier {
  final SupabaseClient client;
  AuthProvider(this.client);
  LocalDbScope? scope;
  bool starting = true;
  bool online = false;
  bool recovering = false;
  String? error;
  String? get username => client.auth.currentUser?.email;
  bool get isLoggedIn => scope?.active == true && !recovering;
  bool get isAdmin => scope?.member.isAdmin == true;
  bool get hasCloudSession => client.auth.currentSession != null;
  StreamSubscription<AuthState>? _authSubscription;
  Timer? _timer;
  Future<bool>? _refreshFuture;
  Future<void>? _closing;
  Future<void>? _logoutFuture;
  int _generation = 0;
  bool _disposed = false;
  bool _signingOut = false;

  void _notify() { if (!_disposed) notifyListeners(); }

  Future<void> initialize() async {
    _authSubscription = client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedOut) {
        unawaited(_clearAccess());
      }
    }, onError: (Object e, StackTrace stack) {
      // Session refresh can fail offline. Membership still has a fixed expiry.
      if (!isConnectionFailure(e)) { error = friendlyCloudError(e); _notify(); }
    });
    await refreshAccess();
    starting = false; _notify();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!recovering && hasCloudSession) unawaited(refreshAccess());
    });
  }

  Future<bool> refreshAccess() => _refreshFuture ??= _refresh().whenComplete(() => _refreshFuture = null);
  Future<bool> _refresh() async {
    await _closing;
    if (_disposed || recovering || _signingOut) return false;
    final userId = client.auth.currentUser?.id;
    if (userId == null) { await _clearAccess(); return false; }
    final generation = _generation;
    try {
      if (client.auth.currentSession?.isExpired == true) {
        await client.auth.refreshSession().timeout(const Duration(seconds: 25));
      }
      await client.auth.getUser().timeout(const Duration(seconds: 25));
      final result = await client.rpc('ig_my_membership').timeout(const Duration(seconds: 25));
      if (_disposed || generation != _generation || client.auth.currentUser?.id != userId) return false;
      if (result == null) {
        await SecureSessionStorage.forgetMembership(userId);
        error = 'An administrator needs to approve your organization access.';
        await _clearAccess(); return false;
      }
      final member = TeamMembership.fromJson(Map<String, dynamic>.from(result as Map), verifiedAt: DateTime.now().toUtc());
      if (member.userId != userId) throw StateError('Account changed. Sign in again.');
      await SecureSessionStorage.saveMembership(member);
      if (_disposed || generation != _generation || client.auth.currentUser?.id != userId) return false;
      await _activate(member, generation);
      if (_disposed || generation != _generation || client.auth.currentUser?.id != userId) return false;
      online = true; error = null; _notify(); return true;
    } catch (e) {
      if (_disposed || generation != _generation || client.auth.currentUser?.id != userId) return false;
      online = false;
      if (isConnectionFailure(e)) {
        final cached = await SecureSessionStorage.readMembership(userId);
        if (_disposed || generation != _generation || client.auth.currentUser?.id != userId) return false;
        if (cached != null) {
          await _activate(cached, generation);
          if (_disposed || generation != _generation || client.auth.currentUser?.id != userId) return false;
          error = 'Offline access. Connect within 24 hours of the last access check.';
          _notify(); return false;
        }
        error = 'Internet is required to sign in or renew your offline access.';
      } else {
        // Schema/auth/permission errors do not grant offline fallback access.
        await SecureSessionStorage.forgetMembership(userId);
        error = friendlyCloudError(e);
      }
      await _clearAccess(); return false;
    }
  }

  Future<void> _activate(TeamMembership member, int generation) async {
    if (scope?.member.userId == member.userId && scope?.member.orgId == member.orgId && scope?.active == true) {
      scope!.member = member; return;
    }
    final opened = await LocalDbService.openScope(member);
    if (_disposed || generation != _generation || client.auth.currentUser?.id != member.userId) {
      opened.active = false; await opened.db.close(); return;
    }
    // Any previous scope is invalidated before the replacement becomes visible.
    final old = scope;
    LocalDbService.deactivate();
    scope = null;
    await NotificationService.endSession();
    if (old != null) await old.db.close();
    if (_disposed || generation != _generation || client.auth.currentUser?.id != member.userId) {
      opened.active = false; await opened.db.close(); return;
    }
    LocalDbService.activeScope = opened; scope = opened;
    await NotificationService.beginSession(opened);
  }

  Future<void> _clearAccess() {
    if (_closing != null) return _closing!;
    _generation++;
    final old = scope;
    scope = null; online = false;
    LocalDbService.deactivate(); _notify();
    return _closing = (() async {
      await NotificationService.endSession();
      if (old != null) await old.db.close();
    })().whenComplete(() => _closing = null);
  }

  static String _cleanEmail(String email) =>
      email.replaceAll(RegExp(r'[\s\u200B-\u200D\uFEFF\u00A0]'), '').toLowerCase();

  Future<void> signIn(String email, String password) async {
    await _logoutFuture;
    await _closing;
    if (_refreshFuture != null) await _refreshFuture;
    error = null;
    // Retry once on transient connection failure before surfacing the error.
    try {
      await client.auth
          .signInWithPassword(email: _cleanEmail(email), password: password)
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      if (!isConnectionFailure(e)) rethrow;
      // Brief pause then one retry — covers momentary network blips.
      await Future<void>.delayed(const Duration(seconds: 2));
      await client.auth
          .signInWithPassword(email: _cleanEmail(email), password: password)
          .timeout(const Duration(seconds: 30));
    }
    await refreshAccess();
  }
  Future<bool> signUp(String email, String password) async {
    await _logoutFuture;
    // Longer timeout: Supabase free-tier may take extra time sending
    // the confirmation email via its built-in SMTP relay.
    try {
      final response = await client.auth
          .signUp(email: _cleanEmail(email), password: password)
          .timeout(const Duration(seconds: 45));
      if (response.session != null) await refreshAccess();
      return response.session == null;
    } catch (e) {
      if (!isConnectionFailure(e)) rethrow;
      // One retry after a short pause for transient failures.
      await Future<void>.delayed(const Duration(seconds: 2));
      final response = await client.auth
          .signUp(email: _cleanEmail(email), password: password)
          .timeout(const Duration(seconds: 45));
      if (response.session != null) await refreshAccess();
      return response.session == null;
    }
  }
  Future<void> confirmEmail(String email, String code) async {
    await _logoutFuture;
    await client.auth
        .verifyOTP(type: OtpType.signup, email: _cleanEmail(email), token: code.trim())
        .timeout(const Duration(seconds: 30));
    await refreshAccess();
  }
  Future<void> resendConfirmation(String email) async {
    await client.auth
        .resend(type: OtpType.signup, email: _cleanEmail(email))
        .timeout(const Duration(seconds: 40));
  }
  Future<void> sendRecovery(String email) => client.auth
      .resetPasswordForEmail(_cleanEmail(email))
      .timeout(const Duration(seconds: 25));
  Future<void> verifyRecovery(String email, String code) async {
    await _logoutFuture;
    recovering = true; _notify();
    try {
      await client.auth
          .verifyOTP(type: OtpType.recovery, email: _cleanEmail(email), token: code.trim())
          .timeout(const Duration(seconds: 25));
    } catch (_) { recovering = false; _notify(); rethrow; }
  }
  Future<void> setRecoveredPassword(String password) async {
    await client.auth
        .updateUser(UserAttributes(password: password))
        .timeout(const Duration(seconds: 25));
    recovering = false; await refreshAccess(); _notify();
  }
  Future<void> logout() {
    if (_logoutFuture != null) return _logoutFuture!;
    _signingOut = true;
    return _logoutFuture = _logout().whenComplete(() {
      _signingOut = false; _logoutFuture = null;
    });
  }
  Future<void> _logout() async {
    final userId = client.auth.currentUser?.id;
    await _clearAccess();
    if (_refreshFuture != null) await _refreshFuture;
    recovering = false;
    if (userId != null) await SecureSessionStorage.forgetMembership(userId);
    // The SDK clears its in-memory session before requesting server revocation.
    // A connection failure must not leave this device's saved session behind.
    try {
      await client.auth.signOut(scope: SignOutScope.local).timeout(const Duration(seconds: 8));
      error = null;
    } catch (e) {
      if (!isConnectionFailure(e)) rethrow;
      error = 'Signed out on this phone. Server session revocation could not be confirmed.';
    } finally {
      await SecureSessionStorage().removePersistedSession();
      _notify();
    }
  }
  @override
  void dispose() {
    _disposed = true; _timer?.cancel(); _authSubscription?.cancel();
    LocalDbService.deactivate();
    super.dispose();
  }
}
