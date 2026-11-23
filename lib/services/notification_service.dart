// ============================================================
// notification_service.dart - Local notifications for new alerts.
// Mirrors the expo-notifications logic in AlertsContext.js.
// ============================================================
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static Object? _session;
  static Future<void> _pending = Future<void>.value();

  static Future<void> beginSession(Object session) async {
    await endSession();
    _session = session;
  }
  static Future<void> endSession() async {
    _session = null;
    try { await _pending; } catch (_) {}
    if (_initialized) await _plugin.cancelAll();
  }
  static Future<void> showForSession(Object session, {required int id, required String title, required String body}) {
    final delivery = _pending.then((_) async {
      if (!identical(_session, session)) throw StateError('Notification session ended');
      await _show(id: id, title: title, body: body);
    });
    _pending = delivery.catchError((Object _) {});
    return delivery;
  }

  static Future<void> init() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);
    await _plugin.initialize(initSettings);

    // Android 13+ needs a runtime notification permission request.
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: false, sound: true);

    _initialized = true;
  }

  static Future<void> showAlert({required int id, required String title, required String body}) {
    final session = _session;
    if (session == null) return Future<void>.error(StateError('No notification session'));
    return showForSession(session, id: id, title: title, body: body);
  }
  static Future<void> _show({required int id, required String title, required String body}) async {
    const androidDetails = AndroidNotificationDetails(
      'intelliguard_alerts',
      'Security Alerts',
      channelDescription: 'Real-time fire, violence and zone-breach alerts',
      importance: Importance.max,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    // SQLite event IDs distinguish alerts even when they arrive in one second.
    await _plugin.show(id, title, body, details);
  }
}
