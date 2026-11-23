import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:intelliguard/models/team_membership.dart';
import 'package:intelliguard/services/local_db_service.dart';
import 'package:intelliguard/services/sync_rules.dart';

class _UnusedDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TeamMembership member(String user, DateTime time) => TeamMembership(userId: user,
  orgId: 'organization', organization: 'Campus', role: 'guard',
  timezone: 'Asia/Karachi', verifiedAt: time);

void main() {
  test('late offline acknowledgment does not reopen a resolved event', () {
    expect(mergeEventStatus('Resolved', 'In Progress'), 'Resolved');
    expect(mergeEventStatus('In Progress', 'Resolved'), 'Resolved');
  });
  test('status retries and arrival ordering produce the same outcome', () {
    for (final a in eventStatuses) {
      expect(mergeEventStatus(a, a), a);
      for (final b in eventStatuses) {
        expect(mergeEventStatus(a, b), mergeEventStatus(b, a));
      }
    }
  });
  test('resolved is terminal and unknown status is rejected', () {
    expect(nextEventStatus('Detected'), 'In Progress');
    expect(nextEventStatus('In Progress'), 'Resolved');
    expect(nextEventStatus('Resolved'), isNull);
    expect(() => mergeEventStatus('Resolved', 'invalid'), throwsArgumentError);
  });
  test('offline authorization expires after a fixed 24 hours', () {
    final time = DateTime.utc(2026, 10, 14, 8);
    final m = member('a', time);
    expect(m.allowsOfflineAt(time.add(const Duration(hours: 23))), isTrue);
    expect(m.allowsOfflineAt(time.add(const Duration(hours: 24, seconds: 1))), isFalse);
    expect(m.allowsOfflineAt(time.subtract(const Duration(seconds: 1))), isFalse);
  });
  test('serialized membership retains the original verification time', () {
    final original = member('a', DateTime.utc(2026, 10, 14));
    final restored = TeamMembership.fromJson(original.toJson());
    expect(restored.verifiedAt, original.verifiedAt);
    expect(restored.isAdmin, isFalse);
    expect(() => TeamMembership.fromJson({...original.toJson(), 'role': 'owner'}), throwsFormatException);
  });
  test('an old async task cannot use a newly activated account scope', () {
    final db = _UnusedDatabase();
    final a = LocalDbScope(db, 'a-cache', member('a', DateTime.now().toUtc()));
    final b = LocalDbScope(db, 'b-cache', member('b', DateTime.now().toUtc()));
    addTearDown(LocalDbService.deactivate);
    LocalDbService.activeScope = a;
    expect(() => a.checkActive(), returnsNormally);
    LocalDbService.activeScope = b;
    expect(() => a.checkActive(), throwsStateError);
    expect(() => b.checkActive(), returnsNormally);
    LocalDbService.deactivate();
    expect(() => b.checkActive(), throwsStateError);
  });
}
