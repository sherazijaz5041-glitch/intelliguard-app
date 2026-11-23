import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'cloud_api.dart';
import 'local_db_service.dart';

class CloudSyncService extends ChangeNotifier {
  final LocalDbScope scope;
  final Future<bool> Function() verifyAccess;
  CloudSyncService(this.scope, this.verifyAccess);
  Timer? _timer;
  Future<void>? _flight;
  bool _stopped = false;
  bool syncing = false;
  bool online = false;
  int pendingCount = 0;
  int blockedCount = 0;
  String? lastError;
  DateTime? lastSuccess;

  void _notify() { if (!_stopped) notifyListeners(); }
  Future<void> start() async {
    await sync();
    if (!_stopped) _timer ??= Timer.periodic(const Duration(seconds: 15), (_) => sync());
  }
  Future<void> sync() {
    if (_stopped || !scope.active) return Future<void>.value();
    return _flight ??= _run().whenComplete(() => _flight = null);
  }
  Future<void> _run() async {
    syncing = true; _notify();
    try {
      online = await verifyAccess();
      scope.checkActive();
      if (!online) { lastError = 'Offline. Pending events stay on this phone.'; return; }
      lastError = null;
      for (var batch = 0; batch < 5 && !_stopped; batch++) {
        final rows = await LocalDbService.pending(scope);
        for (final row in rows) {
          if (_stopped) return;
          scope.checkActive();
          final id = row['sync_id'] as String;
          try {
            if (row['upload_required'] == 1) {
              await CloudApi.call(scope, 'ig_record_event', params: {
                'p_id': id, 'p_event_type': row['event_type'], 'p_confidence': row['confidence'],
                'p_camera_id': row['camera_id'], 'p_location': row['location'],
                'p_occurred_at': row['occurred_at'], 'p_historical': row['historical'] == 1,
              });
              await LocalDbService.markUploaded(scope, id);
            }
            if (row['status_dirty'] == 1) {
              final remote = await CloudApi.call(scope, 'ig_advance_event',
                params: {'p_id': id, 'p_status': row['status']});
              await LocalDbService.acknowledgeStatus(scope, id, remote as String);
            }
          } catch (e) {
            if (!scope.active || _stopped) return;
            final permanent = e is PostgrestException &&
              ['23514', '23505', '42501', 'P0002', '22P02'].contains(e.code);
            await LocalDbService.markFailure(scope, row, friendlyCloudError(e), permanent: permanent);
            lastError = friendlyCloudError(e);
            if (isConnectionFailure(e)) { online = false; return; }
          }
        }
        if (rows.length < 100) break;
      }
      if (_stopped) return;
      await CloudApi.refreshReferences(scope);
      // Full, keyset-paged reconciliation is deliberate for this small FYP.
      // Starting a new scan each cycle also finds late commits/backdated events.
      String? cursor;
      while (!_stopped) {
        final result = await CloudApi.call(scope, 'ig_event_page',
          params: {'p_after_id': cursor, 'p_limit': 250});
        final rows = result as List;
        await LocalDbService.mergeRemote(scope, rows);
        if (rows.length < 250) break;
        cursor = (rows.last as Map)['id'] as String;
      }
      if (!_stopped) {
        await LocalDbService.markInitialSnapshot(scope);
        lastSuccess = DateTime.now();
      }
    } catch (e) {
      if (!_stopped) { online = false; lastError = friendlyCloudError(e); }
    } finally {
      if (!_stopped && scope.active) {
        try {
          final counts = await LocalDbService.queueCounts(scope);
          pendingCount = counts['pending']!; blockedCount = counts['blocked']!;
        } catch (_) { /* A sign-out may have closed the scope. */ }
      }
      syncing = false; _notify();
    }
  }
  Future<void> retryFailed() async {
    if (_flight != null) await _flight;
    await LocalDbService.retryFailures(scope); await sync();
  }
  @override
  void dispose() {
    _stopped = true; _timer?.cancel(); super.dispose();
  }
}
