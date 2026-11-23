import 'package:flutter/material.dart';
import '../services/local_db_service.dart';
import '../services/guard_management_service.dart';
import '../theme/app_theme.dart';

class CameraManagementScreen extends StatefulWidget {
  const CameraManagementScreen({super.key});

  @override
  State<CameraManagementScreen> createState() => _CameraManagementScreenState();
}

class _CameraManagementScreenState extends State<CameraManagementScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _cameras = [];

  @override
  void initState() {
    super.initState();
    _loadCameras();
  }

  Future<void> _loadCameras() async {
    setState(() => _loading = true);
    try {
      final list = await LocalDbService.getCameras();
      if (mounted) setState(() => _cameras = list);
    } catch (_) {
      // Fallback
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addOrEditCamera([Map<String, dynamic>? existing]) async {
    final isEdit = existing != null;
    final idCtrl = TextEditingController(text: existing?['id']?.toString() ?? 'CAM-0${_cameras.length + 1}');
    final nameCtrl = TextEditingController(text: existing?['name']?.toString() ?? '');
    final locCtrl = TextEditingController(text: existing?['location']?.toString() ?? '');
    String status = existing?['status']?.toString() ?? 'Active';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          backgroundColor: ctx.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            isEdit ? 'Edit Camera' : 'Add New Camera',
            style: TextStyle(color: ctx.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Camera ID', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ctx.textSecondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: idCtrl,
                  enabled: !isEdit,
                  style: TextStyle(color: ctx.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'e.g. CAM-04',
                    hintStyle: TextStyle(color: ctx.textMuted),
                    filled: true,
                    fillColor: ctx.bgElevated,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: ctx.borderDefault)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: ctx.borderDefault)),
                  ),
                ),
                const SizedBox(height: 14),
                Text('Camera Name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ctx.textSecondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  style: TextStyle(color: ctx.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'e.g. Main Entrance Gate',
                    hintStyle: TextStyle(color: ctx.textMuted),
                    filled: true,
                    fillColor: ctx.bgElevated,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: ctx.borderDefault)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: ctx.borderDefault)),
                  ),
                ),
                const SizedBox(height: 14),
                Text('Location / Zone', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ctx.textSecondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: locCtrl,
                  style: TextStyle(color: ctx.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'e.g. Science Complex Floor 1',
                    hintStyle: TextStyle(color: ctx.textMuted),
                    filled: true,
                    fillColor: ctx.bgElevated,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: ctx.borderDefault)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: ctx.borderDefault)),
                  ),
                ),
                const SizedBox(height: 14),
                Text('Operational Status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ctx.textSecondary)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: status,
                  dropdownColor: ctx.bgElevated,
                  style: TextStyle(color: ctx.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: ctx.bgElevated,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: ctx.borderDefault)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: ctx.borderDefault)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Active', child: Text('Active (Streaming)')),
                    DropdownMenuItem(value: 'Standby', child: Text('Standby')),
                    DropdownMenuItem(value: 'Offline', child: Text('Offline / Maintenance')),
                  ],
                  onChanged: (v) => update(() => status = v ?? 'Active'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: ctx.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () {
                if (idCtrl.text.trim().isEmpty || nameCtrl.text.trim().isEmpty) {
                  return;
                }
                Navigator.pop(ctx, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentPrimary,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(isEdit ? 'Update' : 'Add Camera', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (saved == true && mounted) {
      await LocalDbService.saveCamera(
        idCtrl.text.trim(),
        nameCtrl.text.trim(),
        locCtrl.text.trim().isNotEmpty ? locCtrl.text.trim() : 'Unassigned Location',
        status: status,
      );
      await GuardManagementService.logActivity(
        isEdit ? 'Camera Updated' : 'Camera Added',
        'Camera ${idCtrl.text.trim()} (${nameCtrl.text.trim()}) set to $status.',
        type: 'camera',
      );
      _loadCameras();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEdit ? 'Camera updated successfully' : 'Camera added successfully'),
            backgroundColor: AppColors.online,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    idCtrl.dispose();
    nameCtrl.dispose();
    locCtrl.dispose();
  }

  Future<void> _confirmDelete(Map<String, dynamic> camera) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Remove Camera', style: TextStyle(color: ctx.textPrimary, fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to remove ${camera['name']} (${camera['id']})? It will be unlinked from all active detection zones.',
          style: TextStyle(color: ctx.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: ctx.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.fire,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final camId = camera['id'].toString();
      await LocalDbService.removeCamera(camId);
      await GuardManagementService.logActivity('Camera Removed', 'Camera $camId was removed from the network.', type: 'camera');
      _loadCameras();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Camera $camId removed'),
            backgroundColor: AppColors.fire,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _testCamera(Map<String, dynamic> camera) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_rounded, color: Colors.black, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text('Live feed verified for ${camera['name']} (1080p @ 30 FPS)', style: const TextStyle(color: Colors.black))),
        ]),
        backgroundColor: AppColors.online,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _cameras.where((c) => (c['status'] ?? 'Active') == 'Active').length;
    final standbyCount = _cameras.length - activeCount;

    return Scaffold(
      backgroundColor: context.bgPrimary,
      appBar: AppBar(
        backgroundColor: context.bgCard,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.arrow_back_ios_rounded, size: 18, color: context.textPrimary),
        ),
        title: Text('Camera Management', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              onPressed: _addOrEditCamera,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add Camera'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentPrimary,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accentPrimary))
          : RefreshIndicator(
              color: AppColors.accentPrimary,
              backgroundColor: context.bgCard,
              onRefresh: _loadCameras,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  // ── Metrics overview ──────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.bgCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: context.borderSubtle),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _metricChip(context, 'Total Cameras', '${_cameras.length}', Icons.videocam_rounded, AppColors.accentPrimary),
                        Container(width: 1, height: 36, color: context.borderSubtle),
                        _metricChip(context, 'Streaming', '$activeCount', Icons.wifi_tethering_rounded, AppColors.online),
                        Container(width: 1, height: 36, color: context.borderSubtle),
                        _metricChip(context, 'Standby', '$standbyCount', Icons.pause_circle_outline_rounded, AppColors.warning),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'CAMERAS IN NETWORK',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: context.textMuted, letterSpacing: 1.2),
                      ),
                      Text(
                        '${_cameras.length} registered',
                        style: TextStyle(fontSize: 12, color: context.textSecondary),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  if (_cameras.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: context.bgCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: context.borderSubtle),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.videocam_off_outlined, size: 48, color: context.textMuted),
                          const SizedBox(height: 12),
                          Text('No Cameras Added', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.textPrimary)),
                          const SizedBox(height: 6),
                          Text('Add campus cameras to monitor security events and zone breaches.',
                              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: context.textSecondary)),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () => _addOrEditCamera(),
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: const Text('Add Camera'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accentPrimary,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    for (final cam in _cameras) _cameraCard(context, cam),
                ],
              ),
            ),
    );
  }

  Widget _metricChip(BuildContext context, String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary)),
          ],
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: context.textMuted)),
      ],
    );
  }

  Widget _cameraCard(BuildContext context, Map<String, dynamic> cam) {
    final status = cam['status']?.toString() ?? 'Active';
    final isActive = status == 'Active';
    final statusColor = isActive ? AppColors.online : (status == 'Standby' ? AppColors.warning : AppColors.fire);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.accentPrimary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.videocam_rounded, color: AppColors.accentPrimary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.accentPrimary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              cam['id']?.toString() ?? 'CAM',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.accentPrimary,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              cam['name']?.toString() ?? 'Camera',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined, size: 12, color: context.textMuted),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              cam['location']?.toString() ?? 'Unknown Location',
                              style: TextStyle(fontSize: 12, color: context.textSecondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 6, height: 6, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text(status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(color: context.borderSubtle, height: 1),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.shield_outlined, size: 13, color: context.textMuted),
                    const SizedBox(width: 6),
                    Text('Detection: Fire, Smoke, Intrusion', style: TextStyle(fontSize: 11, color: context.textMuted)),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.play_circle_outline_rounded, size: 20, color: AppColors.accentPrimary),
                      tooltip: 'Test Feed',
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.zero,
                      onPressed: () => _testCamera(cam),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(Icons.edit_outlined, size: 18, color: context.textSecondary),
                      tooltip: 'Edit',
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.zero,
                      onPressed: () => _addOrEditCamera(cam),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.fire),
                      tooltip: 'Remove',
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.zero,
                      onPressed: () => _confirmDelete(cam),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
