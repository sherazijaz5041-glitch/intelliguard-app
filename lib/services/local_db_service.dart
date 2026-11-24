import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../config/supabase_config.dart';
import '../models/team_membership.dart';
import 'cloud_api.dart';
import 'secure_session_storage.dart';
import 'sync_rules.dart';

class LocalDbScope {
  final Database db;
  final String storageKey;
  TeamMembership member;
  bool active = true;
  LocalDbScope(this.db, this.storageKey, this.member);
  void checkActive() {
    if (!active || !identical(LocalDbService.activeScope, this)) {
      throw StateError('Account changed. Open this screen again.');
    }
    if (!member.allowsOfflineAt(DateTime.now())) {
      throw StateError('Connect to the internet to verify your access.');
    }
  }
}

class LocalDbService {
  static LocalDbScope? activeScope;
  static final revision = ValueNotifier<int>(0);
  static final referenceRevision = ValueNotifier<int>(0);
  static const _uuid = Uuid();

  // Separate account/organization caches. The original DB is never modified.
  static Future<LocalDbScope> openScope(TeamMembership member) async {
    final key = sha256.convert(utf8.encode('${SupabaseConfig.url}|${member.userId}|${member.orgId}')).toString();
    final db = await openDatabase(join(await getDatabasesPath(), 'intelliguard_cloud_$key.db'),
      version: 1, onCreate: (db, version) async {
        for (final statement in schema) { await db.execute(statement); }
      });
    return LocalDbScope(db, key, member);
  }
  static Future<bool> hasInitialSnapshot(LocalDbScope s) async {
    s.checkActive();
    return (await s.db.query('sync_meta', where: 'key = ?', whereArgs: ['initial_snapshot'])).isNotEmpty;
  }
  static Future<void> markInitialSnapshot(LocalDbScope s) async {
    s.checkActive();
    await s.db.insert('sync_meta', {'key': 'initial_snapshot', 'value': '1'}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  static const schema = <String>[
    '''CREATE TABLE sync_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)''',
    '''CREATE TABLE events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sync_id TEXT NOT NULL UNIQUE,
      event_type TEXT NOT NULL, confidence REAL NOT NULL,
      camera_id TEXT NOT NULL, location TEXT NOT NULL, occurred_at TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'Detected', historical INTEGER NOT NULL DEFAULT 0,
      upload_required INTEGER NOT NULL DEFAULT 0, status_dirty INTEGER NOT NULL DEFAULT 0,
      attempts INTEGER NOT NULL DEFAULT 0, retry_after TEXT,
      blocked INTEGER NOT NULL DEFAULT 0, sync_error TEXT
    )''',
    '''CREATE TABLE cameras (id TEXT PRIMARY KEY, name TEXT NOT NULL,
      location TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'Unknown')''',
    '''CREATE TABLE zones (id TEXT PRIMARY KEY, name TEXT NOT NULL, cameras TEXT NOT NULL,
      start_hour INTEGER NOT NULL, end_hour INTEGER NOT NULL, status TEXT NOT NULL)''',
    '''CREATE INDEX events_pending_idx ON events(upload_required, status_dirty, blocked)''',
  ];
  static LocalDbScope requireScope([LocalDbScope? expected]) {
    final scope = expected ?? activeScope;
    if (scope == null) throw StateError('Sign in to access your organization.');
    scope.checkActive(); return scope;
  }
  static void changed(LocalDbScope scope) {
    if (scope.active && identical(activeScope, scope)) revision.value++;
  }
  static void deactivate() { activeScope?.active = false; activeScope = null; }
  static String _localTime(String utc) {
    final n = DateTime.parse(utc).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)} ${two(n.hour)}:${two(n.minute)}:${two(n.second)}';
  }
  static Future<List<Map<String, dynamic>>> getCameras({LocalDbScope? scope}) async {
    final s = requireScope(scope);
    var rows = await s.db.query('cameras', orderBy: 'id');
    if (rows.isEmpty) {
      await s.db.insert('cameras', {'id': 'CAM-01', 'name': 'Main Entrance Gate', 'location': 'North Gate / Block A', 'status': 'Active'},
          conflictAlgorithm: ConflictAlgorithm.ignore);
      await s.db.insert('cameras', {'id': 'CAM-02', 'name': 'Corridor & Hallway', 'location': 'Science Complex 1st Floor', 'status': 'Active'},
          conflictAlgorithm: ConflictAlgorithm.ignore);
      await s.db.insert('cameras', {'id': 'CAM-03', 'name': 'Perimeter Fence', 'location': 'Rear Parking Zone', 'status': 'Active'},
          conflictAlgorithm: ConflictAlgorithm.ignore);
      rows = await s.db.query('cameras', orderBy: 'id');
    }
    s.checkActive(); return rows;
  }
  static Future<int> insertEvent({required String eventType, required double confidence,
      required String cameraId, required String location, LocalDbScope? scope}) async {
    final s = requireScope(scope);
    if (!confidence.isFinite || confidence < 0 || confidence > 1) throw ArgumentError('Invalid confidence');
    final id = await s.db.transaction((txn) async {
      s.checkActive();
      // Event and upload flag commit together. A network request is never needed here.
      return txn.insert('events', {'sync_id': _uuid.v4(), 'event_type': eventType,
        'confidence': confidence, 'camera_id': cameraId, 'location': location,
        'occurred_at': DateTime.now().toUtc().toIso8601String(), 'upload_required': 1});
    });
    changed(s); return id;
  }
  static Future<List<Map<String, dynamic>>> getAllEvents({String? filterType,
      String? filterStatus, LocalDbScope? scope}) async {
    final s = requireScope(scope); final clauses = <String>[]; final args = <Object?>[];
    if (filterType != null && filterType.isNotEmpty) { clauses.add('event_type = ?'); args.add(filterType); }
    if (filterStatus != null && filterStatus.isNotEmpty) { clauses.add('status = ?'); args.add(filterStatus); }
    final rows = await s.db.query('events', where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args, orderBy: 'occurred_at DESC, id DESC');
    s.checkActive();
    return rows.map((r) => <String, dynamic>{'id': r['id'].toString(), 'type': r['event_type'],
      'confidence': r['confidence'], 'cameraId': r['camera_id'], 'location': r['location'],
      'time': _localTime(r['occurred_at'] as String), 'status': r['status'],
      'notify': r['historical'] != 1}).toList();
  }
  static Future<bool> updateEventStatus(String eventId, String newStatus, {LocalDbScope? scope, bool forceSet = false}) async {
    final s = requireScope(scope);
    final changedRow = await s.db.transaction((txn) async {
      s.checkActive();
      final idInt = int.tryParse(eventId);
      List<Map<String, Object?>> rows;
      if (idInt != null) {
        rows = await txn.query('events', where: 'id = ?', whereArgs: [idInt]);
      } else {
        rows = await txn.query('events', where: 'sync_id = ?', whereArgs: [eventId]);
      }
      if (rows.isEmpty) {
        rows = await txn.query('events', where: 'sync_id = ?', whereArgs: [eventId]);
      }
      if (rows.isEmpty) return false;
      final row = rows.first;
      final rowId = row['id'];
      final previous = row['status'] as String;
      // forceSet=true: user explicitly picked a status — write it directly (allows Resolved→Detected).
      // forceSet=false (sync/auto): use merge so remote status never goes backward.
      final merged = forceSet ? newStatus : mergeEventStatus(previous, newStatus);
      if (merged == previous) return true;
      await txn.update('events', {'status': merged, 'status_dirty': 1,
        'retry_after': null, 'sync_error': null, 'blocked': 0},
        where: 'id = ?', whereArgs: [rowId]);
      return true;
    });
    changed(s); return changedRow;
  }

  static Future<Map<String, dynamic>> getEventSummary() async {
    final rows = await getAllEvents(); final types = <String, int>{}; final statuses = <String, int>{};
    for (final r in rows) {
      final type = r['type'] as String; final status = r['status'] as String;
      types[type] = (types[type] ?? 0) + 1; statuses[status] = (statuses[status] ?? 0) + 1;
    }
    return {'total_events': rows.length, 'by_type': types, 'by_status': statuses};
  }
  static Future<List<Map<String, dynamic>>> getZones({LocalDbScope? scope}) async {
    final s = requireScope(scope); final rows = await s.db.query('zones', orderBy: 'name, id');
    s.checkActive();
    return rows.map((r) => <String, dynamic>{...r, 'cameras': jsonDecode(r['cameras'] as String)}).toList();
  }
  static Future<List<Map<String, dynamic>>> getActiveZonesForCamera(String cameraId, {LocalDbScope? scope}) async {
    final rows = await getZones(scope: scope);
    return rows.where((r) => r['status'] == 'Active' && (r['cameras'] as List).contains(cameraId)).toList();
  }
  static Future<void> saveZone({String? id, required String name, required List<String> cameras,
      required int startHour, required int endHour, required String status}) async {
    final s = requireScope();
    await CloudApi.call(s, 'ig_save_zone', admin: true, params: {'p_id': id ?? _uuid.v4(),
      'p_name': name.trim(), 'p_cameras': cameras, 'p_start_hour': startHour,
      'p_end_hour': endHour, 'p_status': status});
    await CloudApi.refreshReferences(s);
  }
  static Future<bool> deleteZone(String id) async {
    final s = requireScope();
    await CloudApi.call(s, 'ig_remove_zone', admin: true, params: {'p_id': id});
    await CloudApi.refreshReferences(s); return true;
  }
  static Future<void> saveCamera(String id, String name, String location, {String status = 'Active'}) async {
    final s = requireScope();
    if (!s.member.isAdmin) throw StateError('Administrator access required.');
    final cleanId = id.trim();
    final cleanName = name.trim();
    final cleanLoc = location.trim();
    final cleanStatus = (status == 'Unknown' || status.isEmpty) ? 'Active' : status;
    // 1. Save directly to local SQLite so it ALWAYS works instantly, even offline
    await s.db.insert('cameras',
      {'id': cleanId, 'name': cleanName, 'location': cleanLoc, 'status': cleanStatus},
      conflictAlgorithm: ConflictAlgorithm.replace);
    changed(s);
    if (s.active && identical(activeScope, s)) referenceRevision.value++;
    // 2. Try to sync to cloud if configured
    try {
      await CloudApi.call(s, 'ig_save_camera', admin: true,
        params: {'p_id': cleanId, 'p_name': cleanName, 'p_location': cleanLoc});
      await CloudApi.refreshReferences(s);
    } catch (_) {}
  }
  static Future<void> removeCamera(String id) async {
    final s = requireScope();
    if (!s.member.isAdmin) throw StateError('Administrator access required.');
    final cleanId = id.trim();
    await s.db.delete('cameras', where: 'id = ?', whereArgs: [cleanId]);
    changed(s);
    if (s.active && identical(activeScope, s)) referenceRevision.value++;
    try {
      await CloudApi.call(s, 'ig_remove_camera', admin: true, params: {'p_id': cleanId});
      await CloudApi.refreshReferences(s);
    } catch (_) {}
  }
  static Future<void> replaceReferences(LocalDbScope s, Map<String, dynamic> data) async {
    s.checkActive();
    await s.db.transaction((txn) async {
      s.checkActive();
      final existingRows = await txn.query('cameras');
      final localStatusMap = <String, String>{};
      for (final row in existingRows) {
        final cid = row['id'] as String?;
        final cstat = row['status'] as String?;
        if (cid != null && cstat != null && cstat != 'Unknown' && cstat.isNotEmpty) {
          localStatusMap[cid] = cstat;
        }
      }
      await txn.delete('cameras'); await txn.delete('zones');
      for (final raw in data['cameras'] as List) {
        final r = Map<String, dynamic>.from(raw as Map);
        if (r['org_id'] != s.member.orgId) throw StateError('Organization mismatch');
        final cid = r['id']?.toString() ?? '';
        final remoteStatus = r['status']?.toString();
        // If remote status is 'Unknown' (default in Supabase schema), preserve local status or use 'Active'
        final resolvedStatus = (remoteStatus != null && remoteStatus != 'Unknown' && remoteStatus.isNotEmpty)
            ? (remoteStatus == 'Online' ? 'Active' : remoteStatus)
            : (localStatusMap[cid] ?? 'Active');
        await txn.insert('cameras', {'id': cid, 'name': r['name'], 'location': r['location'], 'status': resolvedStatus});
      }
      for (final raw in data['zones'] as List) {
        final r = Map<String, dynamic>.from(raw as Map);
        if (r['org_id'] != s.member.orgId) throw StateError('Organization mismatch');
        await txn.insert('zones', {'id': r['id'], 'name': r['name'], 'cameras': jsonEncode(r['cameras']),
          'start_hour': r['start_hour'], 'end_hour': r['end_hour'], 'status': r['status']});
      }
    });
    changed(s);
    if (s.active && identical(activeScope, s)) referenceRevision.value++;
  }
  static Future<List<Map<String, Object?>>> pending(LocalDbScope s) {
    s.checkActive();
    return s.db.query('events', where: '(upload_required = 1 OR status_dirty = 1) AND blocked = 0 '
      'AND (retry_after IS NULL OR retry_after <= ?)', whereArgs: [DateTime.now().toUtc().toIso8601String()],
      orderBy: 'id', limit: 100);
  }
  static Future<void> markUploaded(LocalDbScope s, String id) async {
    s.checkActive();
    await s.db.update('events', {'upload_required': 0, 'attempts': 0, 'sync_error': null,
      'retry_after': null, 'blocked': 0}, where: 'sync_id = ?', whereArgs: [id]);
  }
  static Future<void> acknowledgeStatus(LocalDbScope s, String id, String remote) async {
    s.checkActive();
    await s.db.transaction((txn) async {
      s.checkActive();
      final rows = await txn.query('events', where: 'sync_id = ?', whereArgs: [id]);
      if (rows.isEmpty) return;
      final current = rows.single['status'] as String;
      final isDirty = (rows.single['status_dirty'] as int?) == 1;
      // Do not overwrite user-modified status with remote status if still dirty
      final merged = isDirty ? current : mergeEventStatus(current, remote);
      await txn.update('events', {'status': merged, 'status_dirty': merged == remote ? 0 : 1,
        'attempts': 0, 'sync_error': null, 'retry_after': null, 'blocked': 0},
        where: 'sync_id = ?', whereArgs: [id]);
    });
    changed(s);
  }
  static Future<void> markFailure(LocalDbScope s, Map<String, Object?> row, String error, {required bool permanent}) async {
    s.checkActive();
    final attempts = (row['attempts'] as int) + 1;
    final seconds = (5 * (1 << attempts.clamp(0, 6).toInt())).clamp(5, 300).toInt();
    await s.db.update('events', {'attempts': attempts, 'sync_error': error, 'blocked': permanent ? 1 : 0,
      'retry_after': DateTime.now().toUtc().add(Duration(seconds: seconds)).toIso8601String()},
      where: 'sync_id = ?', whereArgs: [row['sync_id']]);
  }
  static Future<void> retryFailures(LocalDbScope s) async {
    s.checkActive(); await s.db.update('events', {'blocked': 0, 'retry_after': null, 'attempts': 0});
  }
  static Future<Map<String, int>> queueCounts(LocalDbScope s) async {
    s.checkActive();
    final rows = await s.db.rawQuery('SELECT count(*) AS pending, coalesce(sum(blocked), 0) AS blocked '
      'FROM events WHERE upload_required = 1 OR status_dirty = 1');
    return {'pending': (rows.single['pending'] as num).toInt(), 'blocked': (rows.single['blocked'] as num).toInt()};
  }
  static Future<List<Map<String, Object?>>> failedRows(LocalDbScope s) {
    s.checkActive(); return s.db.query('events', columns: ['id','event_type','sync_error'],
      where: 'sync_error IS NOT NULL', orderBy: 'id', limit: 20);
  }
  static Future<void> mergeRemote(LocalDbScope s, List<dynamic> records) async {
    s.checkActive();
    await s.db.transaction((txn) async {
      s.checkActive();
      for (final raw in records) {
        final r = Map<String, dynamic>.from(raw as Map);
        if (r['org_id'] != s.member.orgId) throw StateError('Organization mismatch');
        final existing = await txn.query('events', where: 'sync_id = ?', whereArgs: [r['id']]);
        final remoteStatus = r['status'] as String;
        final existingStatus = existing.isEmpty ? remoteStatus : (existing.single['status'] as String);
        final isDirty = existing.isNotEmpty && (existing.single['status_dirty'] as int?) == 1;
        final status = isDirty ? existingStatus : (existing.isEmpty ? remoteStatus : mergeEventStatus(existingStatus, remoteStatus));
        final values = <String, Object?>{'sync_id': r['id'], 'event_type': r['event_type'],
          'confidence': r['confidence'], 'camera_id': r['camera_id'], 'location': r['location'],
          'occurred_at': DateTime.parse(r['occurred_at'] as String).toUtc().toIso8601String(),
          'status': status, 'historical': r['historical'] == true ? 1 : 0,
          'upload_required': 0, 'status_dirty': isDirty ? 1 : (status == remoteStatus ? 0 : 1),
          if (status == remoteStatus && !isDirty) ...{
            'attempts': 0, 'sync_error': null, 'retry_after': null, 'blocked': 0,
          }};
        if (existing.isEmpty) { await txn.insert('events', values); }
        else { await txn.update('events', values, where: 'sync_id = ?', whereArgs: [r['id']]); }
      }
    });
    changed(s);
  }
  static Future<int> legacyCount() async {
    final file = join(await getDatabasesPath(), 'intelliguard_local.db');
    if (!await File(file).exists()) return 0;
    final legacy = await openDatabase(file, readOnly: true, singleInstance: false);
    try { return Sqflite.firstIntValue(await legacy.rawQuery('SELECT count(*) FROM events')) ?? 0; }
    finally { await legacy.close(); }
  }
  /// Explicit admin action. Original rows and local credentials remain untouched.
  static Future<int> importLegacyEvents() async {
    final s = requireScope();
    if (!s.member.isAdmin) throw StateError('Administrator access required.');
    await CloudApi.call(s, 'ig_list_members', admin: true);
    const bindingKey = 'ig_legacy_import_binding';
    final binding = '${SupabaseConfig.projectKey}|${s.member.orgId}';
    final previous = await SecureSessionStorage.storage.read(key: bindingKey);
    if (previous != null && previous != binding) throw StateError('Old history is already assigned to another organization.');
    final file = join(await getDatabasesPath(), 'intelliguard_local.db');
    if (!await File(file).exists()) return 0;
    final legacy = await openDatabase(file, readOnly: true, singleInstance: false);
    try {
      final rows = await legacy.query('events', orderBy: 'id');
      final deviceKey = await SecureSessionStorage.storage.read(key: 'ig_legacy_source_id') ?? _uuid.v4();
      await SecureSessionStorage.storage.write(key: 'ig_legacy_source_id', value: deviceKey);
      await SecureSessionStorage.storage.write(key: bindingKey, value: binding);
      var added = 0;
      await s.db.transaction((txn) async {
        s.checkActive();
        for (final r in rows) {
          final syncId = _uuid.v5(Uuid.NAMESPACE_URL, '$deviceKey/legacy/${r['id']}');
          if ((await txn.query('events', columns: ['id'], where: 'sync_id = ?', whereArgs: [syncId])).isNotEmpty) continue;
          final status = eventStatuses.contains(r['status']) ? r['status'] as String : 'Detected';
          await txn.insert('events', {'sync_id': syncId, 'event_type': r['event_type'],
            'confidence': r['confidence'], 'camera_id': r['camera_id'], 'location': r['location'],
            'occurred_at': DateTime.parse(r['timestamp'] as String).toUtc().toIso8601String(),
            'status': status, 'historical': 1, 'upload_required': 1, 'status_dirty': status == 'Detected' ? 0 : 1});
          added++;
        }
      });
      changed(s); return added;
    } finally { await legacy.close(); }
  }
}
