// ============================================================
// zone.dart - Named Restricted Zone model (GET/POST/PUT/DELETE /zones)
// ============================================================
class Zone {
  final String id;
  final String name;
  final List<String> cameras;
  final int startHour; // 0-23
  final int endHour; // 0-23
  final String status;

  Zone({
    required this.id,
    required this.name,
    required this.cameras,
    required this.startHour,
    required this.endHour,
    this.status = 'Active',
  });

  factory Zone.fromJson(Map<String, dynamic> json) {
    return Zone(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? '',
      cameras: (json['cameras'] as List?)?.map((e) => e.toString()).toList() ?? [],
      startHour: (json['start_hour'] is num) ? (json['start_hour'] as num).toInt() : 22,
      endHour: (json['end_hour'] is num) ? (json['end_hour'] as num).toInt() : 6,
      status: json['status']?.toString() ?? 'Active',
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'cameras': cameras,
        'start_hour': startHour,
        'end_hour': endHour,
      };

  /// Formats an hour (0-23) as '06:00 AM' / '10:00 PM'.
  static String hour12Label(int hour24) {
    final h = hour24.clamp(0, 23);
    final ampm = h >= 12 ? 'PM' : 'AM';
    var hour12 = h % 12;
    if (hour12 == 0) hour12 = 12;
    return '${hour12.toString().padLeft(2, '0')}:00 $ampm';
  }

  String get timeRangeLabel {
    if (startHour == endHour) return 'All Day Monitoring';
    return '${hour12Label(startHour)} \u2013 ${hour12Label(endHour)}';
  }
}
