// ============================================================
// alerts_provider.dart - Global alerts state (ChangeNotifier)
// Polls the local SQLite database and retains notification history
// for every stored event. Concurrent refreshes share one operation.
// ============================================================
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_event.dart';
import '../services/local_db_service.dart';
import '../services/notification_service.dart';
import '../services/sync_rules.dart';

typedef AlertEventLoader = Future<List<Map<String, dynamic>>> Function();
typedef AlertNotification = Future<void> Function({
  required int id,
  required String title,
  required String body,
});
typedef AlertStatusUpdater = Future<bool> Function(String, String, {bool forceSet});

class AlertsProvider extends ChangeNotifier {
  static const _defaultHistoryKey = 'intelliguard_known_event_ids';
  static const pollInterval = Duration(seconds: 3);

  // Defaults use the real services; tests can supply controlled async work.
  AlertsProvider({AlertEventLoader? loadEvents, AlertNotification? showNotification,
    String historyKey = _defaultHistoryKey, AlertStatusUpdater? updateStatus})
      : _loadEvents = loadEvents ?? (() => LocalDbService.getAllEvents()),
        _showNotification = showNotification ?? NotificationService.showAlert,
        _historyKey = historyKey,
        _updateStatus = updateStatus ?? ((id, status, {bool forceSet = false}) => LocalDbService.updateEventStatus(id, status, forceSet: forceSet));

  final String _historyKey;
  final AlertStatusUpdater _updateStatus;
  final AlertEventLoader _loadEvents;
  final AlertNotification _showNotification;

  List<AppEvent> alerts = [];
  bool loading = true;
  AppEvent? latestAlert;

  Set<String> _knownIds = {};
  bool _isFirstFetch = true;
  bool _knownIdsLoaded = false;
  bool _disposed = false;
  Future<void>? _fetchFuture;
  Timer? _timer;

  Future<void> start() async {
    if (_disposed) return;
    await fetchLatestEvents();
    if (_disposed) return;
    _timer ??= Timer.periodic(pollInterval, (_) => fetchLatestEvents());
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  Future<void> _loadKnownIds() async {
    if (_knownIdsLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_historyKey);
    if (saved != null) {
      try {
        _knownIds = (jsonDecode(saved) as List).map((id) => id.toString()).toSet();
        // A saved empty list is a valid baseline. A first new event must
        // still notify after restarting an app whose database was empty.
        _isFirstFetch = false;
      } catch (error) {
        _knownIds = {};
        _isFirstFetch = true;
        debugPrint('[AlertsProvider] Invalid notification history: $error');
      }
    }
    _knownIdsLoaded = true;
  }

  Future<void> _saveKnownIds() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(_historyKey, jsonEncode(_knownIds.toList()));
    if (!saved) throw StateError('Could not persist notification history');
  }

  Future<void> fetchLatestEvents({bool force = false}) {
    if (_disposed) return Future<void>.value();
    if (force) {
      return _fetchFuture = (_fetchFuture ?? Future<void>.value()).then((_) async {
        if (_disposed) return;
        await _fetchOnce();
      }).whenComplete(() {
        _fetchFuture = null;
      });
    }
    return _fetchFuture ??= _fetchOnce().whenComplete(() {
      _fetchFuture = null;
    });
  }

  Future<void> _fetchOnce() async {
    try {
      await _loadKnownIds();
      if (_disposed) return;
      final rows = await _loadEvents();
      if (_disposed) return;
      alerts = rows.map(AppEvent.fromJson).toList();
      // Imported history is visible in reports, but never announces old incidents.
      _knownIds.addAll(rows.where((r) => r['notify'] == false).map((r) => r['id'].toString()));
      final incomingIds = alerts.map((event) => event.id).toSet();

      if (_isFirstFetch) {
        _knownIds = incomingIds;
        _isFirstFetch = false;
        await _saveKnownIds();
        return;
      }

      final newEvents = alerts.where((event) => !_knownIds.contains(event.id)).toList()
        ..sort((a, b) => a.time.compareTo(b.time));
      for (final event in newEvents) {
        if (_disposed) return;
        final camera = event.cameraId.isNotEmpty ? ' \u2014 ${event.cameraId}' : '';
        final location = event.location.isNotEmpty ? ' (${event.location})' : '';
        await _showNotification(
          id: int.parse(event.id),
          title: '\u26a0\ufe0f ${event.type} Detected',
          body: '${event.type}$camera$location',
        );
        // Record each successful delivery before attempting the next event.
        // If a later notification fails, completed events are not replayed.
        latestAlert = event;
        _knownIds.add(event.id);
        await _saveKnownIds();
      }

      // Forget only deleted events. A size cap would repeatedly rediscover
      // forgotten IDs because the database query returns all stored events.
      _knownIds.retainAll(incomingIds);
      await _saveKnownIds();
    } catch (error) {
      debugPrint('[AlertsProvider] Fetch/notification failed: $error');
    } finally {
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> toggleAlertStatus(String id) async {
    if (_disposed) return;
    final matching = alerts.where((a) => a.id == id);
    if (matching.isEmpty) return;
    final next = nextEventStatus(matching.first.status);
    if (next == null) return;
    final index = alerts.indexWhere((a) => a.id == id);
    if (index != -1) {
      alerts[index] = alerts[index].copyWith(status: next);
      notifyListeners();
    }
    await _updateStatus(id, next);
    if (!_disposed) await fetchLatestEvents(force: true);
  }

  /// Sets the alert to any valid status (allows going back, e.g. Resolved -> Detected).
  Future<void> setAlertStatus(String id, String status) async {
    if (_disposed) return;
    if (!isValidStatus(status)) return;
    final index = alerts.indexWhere((a) => a.id == id);
    if (index != -1) {
      alerts[index] = alerts[index].copyWith(status: status);
      notifyListeners();
    }
    await _updateStatus(id, status, forceSet: true);
    if (!_disposed) await fetchLatestEvents(force: true);
  }
}
