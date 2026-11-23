// ============================================================
// app_event_test.dart — Unit tests for AppEvent model
// Tests: JSON parsing, field defaults, normalizeEventType,
//        copyWith, timeOfDay getter, datePrefix getter.
// ============================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:intelliguard/models/app_event.dart';

void main() {
  // ---------------------------------------------------------------------------
  // normalizeEventType
  // ---------------------------------------------------------------------------
  group('normalizeEventType', () {
    test('null/empty input defaults to Restricted Zone', () {
      expect(normalizeEventType(null), 'Restricted Zone');
      expect(normalizeEventType(''), 'Restricted Zone');
    });

    test('class_0 and fire variants map to Fire', () {
      expect(normalizeEventType('class_0'), 'Fire');
      expect(normalizeEventType('fire'), 'Fire');
      expect(normalizeEventType('Fire'), 'Fire');
      expect(normalizeEventType('FIRE_ALERT'), 'Fire');
    });

    test('smoke variants map to Smoke', () {
      expect(normalizeEventType('smoke'), 'Smoke');
      expect(normalizeEventType('Smoke Detection'), 'Smoke');
    });

    test('class_1 and violence variants map to Violence', () {
      expect(normalizeEventType('class_1'), 'Violence');
      expect(normalizeEventType('violence'), 'Violence');
      expect(normalizeEventType('Violence Detected'), 'Violence');
    });

    test('class_3 and restricted variants map to Restricted Zone', () {
      expect(normalizeEventType('class_3'), 'Restricted Zone');
      expect(normalizeEventType('restricted'), 'Restricted Zone');
      expect(normalizeEventType('Restricted Zone'), 'Restricted Zone');
    });

    test('unknown type is returned as-is', () {
      expect(normalizeEventType('Custom Alert'), 'Custom Alert');
    });
  });

  // ---------------------------------------------------------------------------
  // AppEvent.fromJson — normal case
  // ---------------------------------------------------------------------------
  group('AppEvent.fromJson — normal input', () {
    final json = {
      'id': 42,
      'type': 'Fire',
      'cameraId': 'CAM-02',
      'location': 'Server Room',
      'time': '2026-11-15 14:30:00',
      'confidence': 0.92,
      'status': 'In Progress',
    };

    late AppEvent event;
    setUp(() => event = AppEvent.fromJson(json));

    test('id is converted to string', () => expect(event.id, '42'));
    test('type is normalized', () => expect(event.type, 'Fire'));
    test('cameraId is read from cameraId key', () => expect(event.cameraId, 'CAM-02'));
    test('location is set', () => expect(event.location, 'Server Room'));
    test('time is set', () => expect(event.time, '2026-11-15 14:30:00'));
    test('confidence is parsed as double', () => expect(event.confidence, closeTo(0.92, 0.001)));
    test('status is set', () => expect(event.status, 'In Progress'));
  });

  // ---------------------------------------------------------------------------
  // AppEvent.fromJson — fallbacks / defaults
  // ---------------------------------------------------------------------------
  group('AppEvent.fromJson — defaults and fallbacks', () {
    test('camera_id fallback used when cameraId missing', () {
      final e = AppEvent.fromJson({'id': '1', 'camera_id': 'CAM-05', 'type': 'Fire'});
      expect(e.cameraId, 'CAM-05');
    });

    test('defaults to CAM-01 when both camera keys missing', () {
      final e = AppEvent.fromJson({'id': '1', 'type': 'Fire'});
      expect(e.cameraId, 'CAM-01');
    });

    test('location defaults to Unknown Location', () {
      final e = AppEvent.fromJson({'id': '1', 'type': 'Fire'});
      expect(e.location, 'Unknown Location');
    });

    test('time falls back to timestamp key', () {
      final e = AppEvent.fromJson({'id': '1', 'type': 'Fire', 'timestamp': '2026-01-01 10:00:00'});
      expect(e.time, '2026-01-01 10:00:00');
    });

    test('time defaults to empty string when both keys missing', () {
      final e = AppEvent.fromJson({'id': '1', 'type': 'Fire'});
      expect(e.time, '');
    });

    test('confidence defaults to 1.0 for non-numeric value', () {
      final e = AppEvent.fromJson({'id': '1', 'type': 'Fire', 'confidence': 'high'});
      expect(e.confidence, 1.0);
    });

    test('status defaults to Detected', () {
      final e = AppEvent.fromJson({'id': '1', 'type': 'Fire'});
      expect(e.status, 'Detected');
    });

    test('type null normalizes to Restricted Zone', () {
      final e = AppEvent.fromJson({'id': '1'});
      expect(e.type, 'Restricted Zone');
    });
  });

  // ---------------------------------------------------------------------------
  // AppEvent.copyWith
  // ---------------------------------------------------------------------------
  group('AppEvent.copyWith', () {
    final original = AppEvent(
      id: '10',
      type: 'Smoke',
      cameraId: 'CAM-03',
      location: 'Corridor',
      time: '2026-10-01 09:00:00',
      confidence: 0.80,
      status: 'Detected',
    );

    test('copyWith changes only status', () {
      final updated = original.copyWith(status: 'Resolved');
      expect(updated.status, 'Resolved');
      expect(updated.id, original.id);
      expect(updated.type, original.type);
      expect(updated.cameraId, original.cameraId);
    });

    test('copyWith without arguments returns equivalent event', () {
      final copy = original.copyWith();
      expect(copy.status, original.status);
      expect(copy.id, original.id);
    });
  });

  // ---------------------------------------------------------------------------
  // timeOfDay getter
  // ---------------------------------------------------------------------------
  group('AppEvent.timeOfDay', () {
    test('returns HH:MM:SS part of datetime string', () {
      final e = AppEvent.fromJson({'id': '1', 'type': 'Fire', 'time': '2026-11-15 14:30:45'});
      expect(e.timeOfDay, '14:30:45');
    });

    test('returns Just now when time is empty', () {
      final e = AppEvent.fromJson({'id': '1', 'type': 'Fire'});
      expect(e.timeOfDay, 'Just now');
    });

    test('returns time as-is when no space separator', () {
      final e = AppEvent(id: '1', type: 'Fire', cameraId: 'CAM-01',
          location: 'x', time: '14:30:00', confidence: 1.0, status: 'Detected');
      expect(e.timeOfDay, '14:30:00');
    });
  });

  // ---------------------------------------------------------------------------
  // datePrefix getter
  // ---------------------------------------------------------------------------
  group('AppEvent.datePrefix', () {
    test('returns YYYY-MM-DD portion', () {
      final e = AppEvent.fromJson({'id': '1', 'type': 'Fire', 'time': '2026-11-15 14:30:00'});
      expect(e.datePrefix, '2026-11-15');
    });

    test('returns empty string when time is too short', () {
      final e = AppEvent.fromJson({'id': '1', 'type': 'Fire'});
      expect(e.datePrefix, '');
    });
  });
}
