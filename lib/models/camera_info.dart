// ============================================================
// camera_info.dart - Camera model (GET /cameras)
// ============================================================
class CameraInfo {
  final String id;
  final String name;
  final String location;
  final String status;

  CameraInfo({
    required this.id,
    required this.name,
    required this.location,
    required this.status,
  });

  factory CameraInfo.fromJson(Map<String, dynamic> json) {
    return CameraInfo(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      location: json['location']?.toString() ?? 'Campus',
      status: json['status']?.toString() ?? 'Online',
    );
  }
}
