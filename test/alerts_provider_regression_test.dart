import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:intelliguard/providers/alerts_provider.dart';

const historyKey = 'intelliguard_known_event_ids';

Map<String, dynamic> eventRow(int id) => {
      'id': id.toString(),
      'type': 'Fire',
      'confidence': 0.9,
      'cameraId': 'CAM-01',
      'location': 'Test camera',
      // Equal timestamps also exercise distinct IDs for a notification burst.
      'time': '2026-10-13 18:00:00',
      'status': 'Detected',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({historyKey: jsonEncode([])});
  });

  test('501 stored events do not replay on the next refresh or restart', () async {
    final rows = List.generate(501, (index) => eventRow(index + 1));
    final delivered = <int>[];
    Future<void> notify({required int id, required String title, required String body}) async {
      delivered.add(id);
    }

    final provider = AlertsProvider(loadEvents: () async => rows, showNotification: notify);
    await provider.fetchLatestEvents();
    await provider.fetchLatestEvents();
    expect(delivered.length, 501);
    expect(delivered.toSet().length, 501);
    final prefs = await SharedPreferences.getInstance();
    expect((jsonDecode(prefs.getString(historyKey)!) as List).length, 501);
    provider.dispose();

    final restarted = AlertsProvider(loadEvents: () async => rows, showNotification: notify);
    addTearDown(restarted.dispose);
    await restarted.fetchLatestEvents();
    expect(delivered.length, 501);
  });

  test('simultaneous refresh requests deliver one notification', () async {
    final started = Completer<void>();
    final rowsReady = Completer<List<Map<String, dynamic>>>();
    var loads = 0;
    final delivered = <int>[];
    final provider = AlertsProvider(
      loadEvents: () {
        loads++;
        if (!started.isCompleted) started.complete();
        return rowsReady.future;
      },
      showNotification: ({required int id, required String title, required String body}) async {
        delivered.add(id);
      },
    );
    addTearDown(provider.dispose);
    final first = provider.fetchLatestEvents();
    await started.future;
    final second = provider.fetchLatestEvents();
    final third = provider.fetchLatestEvents();
    rowsReady.complete([eventRow(1)]);
    await Future.wait([first, second, third]);
    expect(loads, 1);
    expect(delivered, [1]);
  });

  test('a later delivery failure does not replay an earlier success', () async {
    final delivered = <int>[];
    final attempts = <int>[];
    var failSecondOnce = true;
    final firstRow = eventRow(1)..['time'] = '2026-10-13 18:00:00';
    final secondRow = eventRow(2)..['time'] = '2026-10-13 18:00:01';
    final provider = AlertsProvider(
      loadEvents: () async => [firstRow, secondRow],
      showNotification: ({required int id, required String title, required String body}) async {
        attempts.add(id);
        if (id == 2 && failSecondOnce) {
          failSecondOnce = false;
          throw StateError('Simulated delivery failure');
        }
        delivered.add(id);
      },
    );
    addTearDown(provider.dispose);
    await provider.fetchLatestEvents();
    await provider.fetchLatestEvents();
    expect(delivered, [1, 2]);
    expect(attempts, [1, 2, 2]);
  });

  test('a saved empty baseline still notifies the first new event', () async {
    final delivered = <int>[];
    final provider = AlertsProvider(
      loadEvents: () async => [eventRow(1)],
      showNotification: ({required int id, required String title, required String body}) async {
        delivered.add(id);
      },
    );
    addTearDown(provider.dispose);
    await provider.fetchLatestEvents();
    expect(delivered, [1]);
  });

  test('a missing baseline suppresses existing history only on first fetch', () async {
    SharedPreferences.setMockInitialValues({});
    var rows = [eventRow(1)];
    final delivered = <int>[];
    final provider = AlertsProvider(
      loadEvents: () async => rows,
      showNotification: ({required int id, required String title, required String body}) async {
        delivered.add(id);
      },
    );
    addTearDown(provider.dispose);
    await provider.fetchLatestEvents();
    expect(delivered, isEmpty);
    rows = [eventRow(2), eventRow(1)];
    await provider.fetchLatestEvents();
    expect(delivered, [2]);
  });

  test('disposing during a database read suppresses late notifications', () async {
    final started = Completer<void>();
    final rowsReady = Completer<List<Map<String, dynamic>>>();
    final delivered = <int>[];
    final provider = AlertsProvider(
      loadEvents: () {
        started.complete();
        return rowsReady.future;
      },
      showNotification: ({required int id, required String title, required String body}) async {
        delivered.add(id);
      },
    );
    final pending = provider.fetchLatestEvents();
    await started.future;
    provider.dispose();
    rowsReady.complete([eventRow(1)]);
    await pending;
    expect(delivered, isEmpty);
    await provider.fetchLatestEvents();
    expect(delivered, isEmpty);
  });
  test('notification history is isolated between accounts', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('account-a', jsonEncode(['1']));
    await prefs.setString('account-b', jsonEncode([]));
    final deliveredA = <int>[];
    final deliveredB = <int>[];
    final a = AlertsProvider(historyKey: 'account-a', loadEvents: () async => [eventRow(1)],
      showNotification: ({required int id, required String title, required String body}) async { deliveredA.add(id); });
    final b = AlertsProvider(historyKey: 'account-b', loadEvents: () async => [eventRow(1)],
      showNotification: ({required int id, required String title, required String body}) async { deliveredB.add(id); });
    addTearDown(a.dispose); addTearDown(b.dispose);
    await a.fetchLatestEvents(); await b.fetchLatestEvents();
    expect(deliveredA, isEmpty); expect(deliveredB, [1]);
  });

  test('imported historical records do not announce old incidents', () async {
    final delivered = <int>[];
    final provider = AlertsProvider(loadEvents: () async => [
      {...eventRow(1), 'notify': false}, eventRow(2)],
      showNotification: ({required int id, required String title, required String body}) async { delivered.add(id); });
    addTearDown(provider.dispose);
    await provider.fetchLatestEvents(); await provider.fetchLatestEvents();
    expect(delivered, [2]);
  });

  test('setAlertStatus updates in-memory alert status immediately and invokes updater', () async {
    final rows = [eventRow(1)];
    final updated = <String, String>{};
    final provider = AlertsProvider(
      loadEvents: () async => rows,
      showNotification: ({required int id, required String title, required String body}) async {},
      updateStatus: (id, status, {bool forceSet = false}) async {
        updated[id] = status;
        rows[0]['status'] = status;
        return true;
      },
    );
    addTearDown(provider.dispose);
    await provider.fetchLatestEvents();
    expect(provider.alerts.first.status, 'Detected');

    await provider.setAlertStatus('1', 'In Progress');
    expect(updated['1'], 'In Progress');
    expect(provider.alerts.first.status, 'In Progress');

    await provider.setAlertStatus('1', 'Resolved');
    expect(updated['1'], 'Resolved');
    expect(provider.alerts.first.status, 'Resolved');
  });

  test('toggleAlertStatus advances status in sequence', () async {
    final rows = [eventRow(1)];
    final updated = <String, String>{};
    final provider = AlertsProvider(
      loadEvents: () async => rows,
      showNotification: ({required int id, required String title, required String body}) async {},
      updateStatus: (id, status, {bool forceSet = false}) async {
        updated[id] = status;
        rows[0]['status'] = status;
        return true;
      },
    );
    addTearDown(provider.dispose);
    await provider.fetchLatestEvents();
    expect(provider.alerts.first.status, 'Detected');

    await provider.toggleAlertStatus('1');
    expect(updated['1'], 'In Progress');
    expect(provider.alerts.first.status, 'In Progress');

    await provider.toggleAlertStatus('1');
    expect(updated['1'], 'Resolved');
    expect(provider.alerts.first.status, 'Resolved');
  });
}
