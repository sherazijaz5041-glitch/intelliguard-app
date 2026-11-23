// ============================================================
// zone_model_test.dart — Unit tests for Zone model
// Tests: fromJson parsing, defaults, toJson round-trip,
//        hour12Label formatter, timeRangeLabel getter.
// ============================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:intelliguard/models/zone.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Zone.fromJson — normal case
  // ---------------------------------------------------------------------------
  group('Zone.fromJson — normal input', () {
    final json = {
      'id': 7,
      'name': 'Server Room',
      'cameras': ['CAM-01', 'CAM-02'],
      'start_hour': 22,
      'end_hour': 6,
      'status': 'Active',
    };

    late Zone zone;
    setUp(() => zone = Zone.fromJson(json));

    test('id is converted to string', () => expect(zone.id, '7'));
    test('name is set', () => expect(zone.name, 'Server Room'));
    test('cameras list is parsed', () => expect(zone.cameras, ['CAM-01', 'CAM-02']));
    test('startHour is set', () => expect(zone.startHour, 22));
    test('endHour is set', () => expect(zone.endHour, 6));
    test('status is set', () => expect(zone.status, 'Active'));
  });

  // ---------------------------------------------------------------------------
  // Zone.fromJson — defaults
  // ---------------------------------------------------------------------------
  group('Zone.fromJson — defaults', () {
    test('name defaults to empty string when missing', () {
      final z = Zone.fromJson({'id': '1'});
      expect(z.name, '');
    });

    test('cameras defaults to empty list when missing', () {
      final z = Zone.fromJson({'id': '1'});
      expect(z.cameras, isEmpty);
    });

    test('startHour defaults to 22 when missing', () {
      final z = Zone.fromJson({'id': '1'});
      expect(z.startHour, 22);
    });

    test('endHour defaults to 6 when missing', () {
      final z = Zone.fromJson({'id': '1'});
      expect(z.endHour, 6);
    });

    test('status defaults to Active when missing', () {
      final z = Zone.fromJson({'id': '1'});
      expect(z.status, 'Active');
    });

    test('cameras parsed from string elements', () {
      final z = Zone.fromJson({'id': '1', 'cameras': [1, 2, 3]});
      expect(z.cameras, ['1', '2', '3']);
    });
  });

  // ---------------------------------------------------------------------------
  // Zone.toJson round-trip
  // ---------------------------------------------------------------------------
  group('Zone.toJson', () {
    test('round-trip preserves cameras list', () {
      final z = Zone(id: '5', name: 'Lab', cameras: ['CAM-03'], startHour: 8, endHour: 18);
      final json = z.toJson();
      expect(json['cameras'], ['CAM-03']);
      expect(json['start_hour'], 8);
      expect(json['end_hour'], 18);
      expect(json['name'], 'Lab');
    });
  });

  // ---------------------------------------------------------------------------
  // Zone.hour12Label
  // ---------------------------------------------------------------------------
  group('Zone.hour12Label', () {
    test('midnight (0) formats as 12:00 AM', () => expect(Zone.hour12Label(0), '12:00 AM'));
    test('noon (12) formats as 12:00 PM', () => expect(Zone.hour12Label(12), '12:00 PM'));
    test('1 AM formats correctly', () => expect(Zone.hour12Label(1), '01:00 AM'));
    test('13:00 formats as 01:00 PM', () => expect(Zone.hour12Label(13), '01:00 PM'));
    test('22:00 formats as 10:00 PM', () => expect(Zone.hour12Label(22), '10:00 PM'));
    test('23:00 formats as 11:00 PM', () => expect(Zone.hour12Label(23), '11:00 PM'));
    test('6 AM formats correctly', () => expect(Zone.hour12Label(6), '06:00 AM'));
    test('value above 23 is clamped', () => expect(Zone.hour12Label(25), Zone.hour12Label(23)));
    test('negative value is clamped to 0', () => expect(Zone.hour12Label(-1), Zone.hour12Label(0)));
  });

  // ---------------------------------------------------------------------------
  // Zone.timeRangeLabel
  // ---------------------------------------------------------------------------
  group('Zone.timeRangeLabel', () {
    test('same start and end shows All Day Monitoring', () {
      final z = Zone(id: '1', name: 'z', cameras: [], startHour: 8, endHour: 8);
      expect(z.timeRangeLabel, 'All Day Monitoring');
    });

    test('normal range shows start – end label', () {
      final z = Zone(id: '1', name: 'z', cameras: [], startHour: 8, endHour: 18);
      expect(z.timeRangeLabel, contains('08:00 AM'));
      expect(z.timeRangeLabel, contains('06:00 PM'));
    });

    test('overnight range (22:00 – 06:00) formats correctly', () {
      final z = Zone(id: '1', name: 'z', cameras: [], startHour: 22, endHour: 6);
      expect(z.timeRangeLabel, contains('10:00 PM'));
      expect(z.timeRangeLabel, contains('06:00 AM'));
    });
  });
}
