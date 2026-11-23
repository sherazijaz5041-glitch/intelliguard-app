import 'package:crypto/crypto.dart';
import 'dart:convert';

class SupabaseConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://jebqrrejydqajbzqvuuc.supabase.co',
  );
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_aVcN95H1Efnn3WRGQdgPVQ_VbKrOC32',
  );
  static String get projectKey => sha256.convert(utf8.encode(url)).toString().substring(0, 24);

  static String? validate() {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return 'Supabase configuration is missing. Build using your supabase_config.json file.';
    }
    if (!publishableKey.startsWith('sb_publishable_')) {
      return 'Use a Supabase publishable key. Secret and service-role keys are not accepted.';
    }
    return null;
  }
}
