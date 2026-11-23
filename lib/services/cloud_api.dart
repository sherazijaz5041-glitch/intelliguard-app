import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'local_db_service.dart';

bool isConnectionFailure(Object error) => error is SocketException ||
  error is TimeoutException || error is http.ClientException ||
  error is HttpException || error is AuthRetryableFetchException;

String friendlyCloudError(Object error) {
  if (isConnectionFailure(error)) {
    if (error is TimeoutException) {
      return 'The request timed out. Supabase may be slow or your connection is unstable. Please try again.';
    }
    return 'Could not reach Supabase. Check your internet connection and try again.';
  }
  if (error is AuthException) {
    final msg = error.message.toLowerCase();
    if (msg.contains('invalid login') || msg.contains('invalid_credentials')) {
      return 'Incorrect email or password. Please check and try again.';
    }
    if (msg.contains('user already registered') || msg.contains('already_registered')) {
      return 'An account with this email already exists. Try signing in instead.';
    }
    if (msg.contains('email rate limit') || msg.contains('rate_limit')) {
      return 'Too many attempts. Please wait a minute before trying again.';
    }
    return error.message;
  }
  if (error is PostgrestException) {
    if (error.message.contains('Account must register')) {
      return 'This email must register and confirm their account in the app first, then you can approve them.';
    }
    if (error.message.contains('already has a membership')) {
      return 'This account is already a member of an organization.';
    }
    return error.message;
  }
  if (error is StateError) return error.message.toString();
  return 'The operation could not be completed. Please try again.';
}

class CloudApi {
  static SupabaseClient get client => Supabase.instance.client;

  static Future<dynamic> call(LocalDbScope scope, String function,
      {Map<String, dynamic> params = const {}, bool admin = false}) async {
    scope.checkActive();
    if (client.auth.currentUser?.id != scope.member.userId) throw StateError('Session changed.');
    if (admin && !scope.member.isAdmin) throw StateError('Administrator access required.');
    // The server checks these against auth.uid() and current membership. They
    // also prevent an old async task from writing under a newly signed-in user.
    final result = await client.rpc(function, params: {
      ...params, 'p_actor': scope.member.userId, 'p_org': scope.member.orgId,
    }).timeout(const Duration(seconds: 20));
    scope.checkActive();
    return result;
  }

  static Future<void> refreshReferences(LocalDbScope scope) async {
    final data = await call(scope, 'ig_reference_data');
    await LocalDbService.replaceReferences(scope, Map<String, dynamic>.from(data as Map));
  }
}
