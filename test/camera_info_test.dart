// ============================================================
// camera_info_test.dart — Unit tests for CameraInfo model
// Tests: fromJson parsing and all field defaults.
// ============================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:intelliguard/models/camera_info.dart';

void main() {
  group('CameraInfo.fromJson — normal input', () {
    final json = {
      'id': 'CAM-01',
      'name': 'Main Entrance',
      'location': 'Gate A',
      'status': 'Online',
    };

    late CameraInfo cam;
    setUp(() => cam = CameraInfo.fromJson(json));

    test('id is set', () => expect(cam.id, 'CAM-01'));
    test('name is set', () => expect(cam.name, 'Main Entrance'));
    test('location is set', () => expect(cam.location, 'Gate A'));
    test('status is set', () => expect(cam.status, 'Online'));
  });

  group('CameraInfo.fromJson — defaults', () {
    test('id defaults to empty string', () {
      final c = CameraInfo.fromJson({});
      expect(c.id, '');
    });

    test('name defaults to empty string', () {
      final c = CameraInfo.fromJson({});
      expect(c.name, '');
    });

    test('location defaults to Campus', () {
      final c = CameraInfo.fromJson({});
      expect(c.location, 'Campus');
    });

    test('status defaults to Online', () {
      final c = CameraInfo.fromJson({});
      expect(c.status, 'Online');
    });

    test('numeric id is converted to string', () {
      final c = CameraInfo.fromJson({'id': 3});
      expect(c.id, '3');
    });
  });
}
