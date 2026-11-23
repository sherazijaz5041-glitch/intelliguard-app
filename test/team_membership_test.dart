// ============================================================
// team_membership_test.dart — Unit tests for TeamMembership model
// Tests: isAdmin role, offline window, fromJson parsing, toJson.
// ============================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:intelliguard/models/team_membership.dart';

TeamMembership makeMember({String role = 'guard', DateTime? verifiedAt}) => TeamMembership(
      userId: 'user-123',
      orgId: 'org-abc',
      organization: 'Campus Security',
      role: role,
      timezone: 'Asia/Karachi',
      verifiedAt: verifiedAt ?? DateTime.utc(2026, 11, 1, 10, 0, 0),
    );

void main() {
  // ---------------------------------------------------------------------------
  // isAdmin
  // ---------------------------------------------------------------------------
  group('TeamMembership.isAdmin', () {
    test('admin role returns true', () {
      expect(makeMember(role: 'admin').isAdmin, isTrue);
    });

    test('guard role returns false', () {
      expect(makeMember(role: 'guard').isAdmin, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // allowsOfflineAt
  // ---------------------------------------------------------------------------
  group('TeamMembership.allowsOfflineAt', () {
    final base = DateTime.utc(2026, 11, 1, 10, 0, 0);
    final member = makeMember(verifiedAt: base);

    test('allows offline access within 24 hours', () {
      expect(member.allowsOfflineAt(base.add(const Duration(hours: 23))), isTrue);
    });

    test('allows offline at exactly 24 hours', () {
      expect(member.allowsOfflineAt(base.add(const Duration(hours: 24))), isTrue);
    });

    test('denies offline access after 24 hours', () {
      expect(member.allowsOfflineAt(base.add(const Duration(hours: 24, seconds: 1))), isFalse);
    });

    test('denies offline access for a time before verification', () {
      expect(member.allowsOfflineAt(base.subtract(const Duration(seconds: 1))), isFalse);
    });

    test('allows offline access exactly at verification time', () {
      expect(member.allowsOfflineAt(base), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // fromJson
  // ---------------------------------------------------------------------------
  group('TeamMembership.fromJson', () {
    final validJson = {
      'user_id': 'user-456',
      'org_id': 'org-xyz',
      'organization': 'University',
      'role': 'admin',
      'timezone': 'Asia/Karachi',
      'verified_at': '2026-11-01T10:00:00.000Z',
    };

    test('parses all fields correctly', () {
      final m = TeamMembership.fromJson(validJson);
      expect(m.userId, 'user-456');
      expect(m.orgId, 'org-xyz');
      expect(m.organization, 'University');
      expect(m.role, 'admin');
      expect(m.timezone, 'Asia/Karachi');
    });

    test('verifiedAt parameter overrides json verified_at', () {
      final override = DateTime.utc(2026, 6, 1);
      final m = TeamMembership.fromJson(validJson, verifiedAt: override);
      expect(m.verifiedAt, override);
    });

    test('throws FormatException for unknown role', () {
      final bad = Map<String, dynamic>.from(validJson)..['role'] = 'superuser';
      expect(() => TeamMembership.fromJson(bad), throwsFormatException);
    });

    test('timezone defaults to Asia/Karachi when missing', () {
      final noTz = Map<String, dynamic>.from(validJson)..remove('timezone');
      final m = TeamMembership.fromJson(noTz);
      expect(m.timezone, 'Asia/Karachi');
    });
  });

  // ---------------------------------------------------------------------------
  // toJson round-trip
  // ---------------------------------------------------------------------------
  group('TeamMembership.toJson', () {
    test('round-trip preserves all fields', () {
      final m = makeMember(role: 'admin');
      final json = m.toJson();
      expect(json['user_id'], m.userId);
      expect(json['org_id'], m.orgId);
      expect(json['organization'], m.organization);
      expect(json['role'], 'admin');
      expect(json['timezone'], m.timezone);
      expect(json['verified_at'], isA<String>());
    });
  });
}
