// ============================================================
// app_event.dart - Event/Alert model
// Mirrors the shape returned by GET /events in the Flask backend
// (see IntelliGuard_backend/app.py + database.py)
// ============================================================

String normalizeEventType(String? type) {
  if (type == null || type.isEmpty) return 'Restricted Zone';
  final t = type.toLowerCase();
  if (t == 'class_0' || t.contains('fire')) return 'Fire';
  if (t.contains('smoke')) return 'Smoke';
  if (t == 'class_1' || t.contains('violence')) return 'Violence';
  if (t == 'class_3' || t.contains('restricted')) return 'Restricted Zone';
  return type;
}

class AppEvent {
  final String id;
  final String type;
  final String cameraId;
  final String location;
  final String time; // 'YYYY-MM-DD HH:MM:SS' local time from backend
  final double confidence;
  final String status; // Detected | In Progress | Resolved

  AppEvent({
    required this.id,
    required this.type,
    required this.cameraId,
    required this.location,
    required this.time,
    required this.confidence,
    required this.status,
  });

  factory AppEvent.fromJson(Map<String, dynamic> json) {
    return AppEvent(
      id: json['id'].toString(),
      type: normalizeEventType(json['type']?.toString()),
      cameraId: json['cameraId']?.toString() ?? json['camera_id']?.toString() ?? 'CAM-01',
      location: json['location']?.toString() ?? 'Unknown Location',
      time: json['time']?.toString() ?? json['timestamp']?.toString() ?? '',
      confidence: (json['confidence'] is num) ? (json['confidence'] as num).toDouble() : 1.0,
      status: json['status']?.toString() ?? 'Detected',
    );
  }

  AppEvent copyWith({String? status}) {
    return AppEvent(
      id: id,
      type: type,
      cameraId: cameraId,
      location: location,
      time: time,
      confidence: confidence,
      status: status ?? this.status,
    );
  }

  /// Just the HH:MM:SS part of `time`, or 'Just now' if unavailable.
  String get timeOfDay {
    if (time.isEmpty) return 'Just now';
    final parts = time.split(' ');
    return parts.length > 1 ? parts[1] : time;
  }

  /// The 'YYYY-MM-DD' date prefix of `time`.
  String get datePrefix => time.length >= 10 ? time.substring(0, 10) : '';
}
