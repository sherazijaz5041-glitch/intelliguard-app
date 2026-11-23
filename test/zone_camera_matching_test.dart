// ============================================================
// zone_camera_matching_test.dart — Tests for restricted-zone
//   camera matching logic (mirrors getActiveZonesForCamera
//   and check_restricted_zone zone-lookup in detection.py).
//
// We test the pure filtering logic using Zone model objects
// rather than hitting the database — the same logic used by
// LocalDbService.getActiveZonesForCamera() and backend
// detection.py's check_restricted_zone() zone query.
// ============================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:intelliguard/models/zone.dart';
import 'package:intelliguard/services/sync_rules.dart';

// ---------------------------------------------------------------------------
// Pure helper that mirrors LocalDbService.getActiveZonesForCamera filtering.
// ---------------------------------------------------------------------------
List<Zone> activeZonesForCamera(List<Zone> allZones, String cameraId) {
  return allZones
      .where((z) => z.status == 'Active' && z.cameras.contains(cameraId))
      .toList();
}

// ---------------------------------------------------------------------------
// Pure helper that mirrors detection.py's _is_within_restricted_window().
// ---------------------------------------------------------------------------
bool isWithinWindow(int start, int end, int nowHour) {
  if (start < end) {
    return nowHour >= start && nowHour < end;
  } else {
    // Overnight (e.g. 22 → 06)
    return nowHour >= start || nowHour < end;
  }
}

void main() {
  // ---------------------------------------------------------------------------
  // Camera → Zone matching
  // ---------------------------------------------------------------------------
  group('activeZonesForCamera — camera matching', () {
    final zones = [
      Zone(id: '1', name: 'Server Room', cameras: ['CAM-01', 'CAM-02'], startHour: 22, endHour: 6),
      Zone(id: '2', name: 'Lab', cameras: ['CAM-03'], startHour: 8, endHour: 18),
      Zone(id: '3', name: 'Inactive Zone', cameras: ['CAM-01'], startHour: 0, endHour: 23, status: 'Inactive'),
    ];

    test('camera assigned to an active zone is matched', () {
      final result = activeZonesForCamera(zones, 'CAM-01');
      expect(result.length, 1);
      expect(result.first.name, 'Server Room');
    });

    test('camera assigned to multiple active zones returns all', () {
      final extra = Zone(id: '4', name: 'Corridor', cameras: ['CAM-01'], startHour: 6, endHour: 22);
      final result = activeZonesForCamera([...zones, extra], 'CAM-01');
      expect(result.length, 2);
    });

    test('camera NOT in any zone returns empty list', () {
      final result = activeZonesForCamera(zones, 'CAM-99');
      expect(result, isEmpty);
    });

    test('inactive zone is excluded even if camera matches', () {
      // CAM-01 is in both zone 1 (Active) and zone 3 (Inactive)
      final result = activeZonesForCamera(zones, 'CAM-01');
      expect(result.any((z) => z.name == 'Inactive Zone'), isFalse);
    });

    test('camera with no zones configured returns empty', () {
      final result = activeZonesForCamera([], 'CAM-01');
      expect(result, isEmpty);
    });

    test('zone with empty cameras list never matches any camera', () {
      final emptyZone = Zone(id: '5', name: 'Empty', cameras: [], startHour: 0, endHour: 23);
      final result = activeZonesForCamera([emptyZone], 'CAM-01');
      expect(result, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Time-window logic (mirrors detection.py _is_within_restricted_window)
  // ---------------------------------------------------------------------------
  group('isWithinWindow — time window logic', () {
    // Normal (non-overnight) range: 08:00 – 18:00
    test('hour inside normal window returns true', () {
      expect(isWithinWindow(8, 18, 12), isTrue);
    });

    test('hour at start of normal window returns true', () {
      expect(isWithinWindow(8, 18, 8), isTrue);
    });

    test('hour at end of normal window returns false (exclusive end)', () {
      expect(isWithinWindow(8, 18, 18), isFalse);
    });

    test('hour before normal window returns false', () {
      expect(isWithinWindow(8, 18, 7), isFalse);
    });

    test('hour after normal window returns false', () {
      expect(isWithinWindow(8, 18, 20), isFalse);
    });

    // Overnight range: 22:00 – 06:00
    test('hour at start of overnight window returns true', () {
      expect(isWithinWindow(22, 6, 22), isTrue);
    });

    test('hour in late-night part of overnight window returns true', () {
      expect(isWithinWindow(22, 6, 23), isTrue);
    });

    test('midnight (0) is inside overnight window', () {
      expect(isWithinWindow(22, 6, 0), isTrue);
    });

    test('hour in early-morning part of overnight window returns true', () {
      expect(isWithinWindow(22, 6, 3), isTrue);
    });

    test('hour at end of overnight window (06:00) returns false', () {
      expect(isWithinWindow(22, 6, 6), isFalse);
    });

    test('hour in daytime is outside overnight window', () {
      expect(isWithinWindow(22, 6, 14), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Combining matching + time window (simulates full restricted-zone decision)
  // ---------------------------------------------------------------------------
  group('Combined: zone matched AND time window active', () {
    final zones = [
      Zone(id: '1', name: 'Server Room', cameras: ['CAM-01'], startHour: 22, endHour: 6),
    ];

    bool wouldAlert(String cameraId, int nowHour) {
      final matched = activeZonesForCamera(zones, cameraId);
      if (matched.isEmpty) return false;
      return matched.any((z) => isWithinWindow(z.startHour, z.endHour, nowHour));
    }

    test('assigned camera during restricted hours → would alert', () {
      expect(wouldAlert('CAM-01', 23), isTrue);
    });

    test('assigned camera outside restricted hours → no alert', () {
      expect(wouldAlert('CAM-01', 14), isFalse);
    });

    test('unassigned camera during restricted hours → no alert', () {
      expect(wouldAlert('CAM-05', 23), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Sync rules — status transitions (tying in existing logic)
  // ---------------------------------------------------------------------------
  group('selectableStatuses and isValidStatus', () {
    test('all three statuses are valid', () {
      expect(isValidStatus('Detected'), isTrue);
      expect(isValidStatus('In Progress'), isTrue);
      expect(isValidStatus('Resolved'), isTrue);
    });

    test('arbitrary string is not a valid status', () {
      expect(isValidStatus('Closed'), isFalse);
      expect(isValidStatus(''), isFalse);
    });

    test('selectableStatuses always returns all 3 options', () {
      for (final s in ['Detected', 'In Progress', 'Resolved']) {
        expect(selectableStatuses(s).length, 3);
      }
    });
  });
}
