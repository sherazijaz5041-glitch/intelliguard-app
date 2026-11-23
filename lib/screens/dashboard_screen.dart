// ============================================================
// dashboard_screen.dart - Live Overview (mirrors DashboardScreen.js)
// Live camera preview + periodic frame -> /predict, stat cards, recent alerts.
// ============================================================
import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/camera_info.dart';
import '../providers/alerts_provider.dart';
import '../services/local_db_service.dart';
import '../services/tflite_detection_service.dart';
import '../theme/app_theme.dart';
import '../widgets/alert_row.dart';
import '../widgets/stat_card.dart';
import 'incident_details_screen.dart';

class DashboardScreen extends StatefulWidget {
  final VoidCallback? onViewAllAlerts;
  const DashboardScreen({super.key, this.onViewAllAlerts});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  List<CameraInfo> _cameras = [];
  String _selectedCameraId = 'CAM-01';
  Timer? _clockTimer;
  Timer? _predictTimer;
  DateTime _now = DateTime.now();

  CameraController? _cameraController;
  List<CameraDescription> _availableCameras = [];
  bool _cameraPermissionDenied = false;
  bool _cameraInitializing = false;
  bool _captureInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    LocalDbService.referenceRevision.addListener(_loadCameras);
    _loadCameras();
    _initDeviceCamera();
    _startPredictionLoop();
  }

  Future<void> _loadCameras() async {
    try {
      final rows = await LocalDbService.getCameras();
      final data = rows.map(CameraInfo.fromJson).toList();
      if (!mounted) return;
      setState(() {
        _cameras = data;
        if (data.isEmpty) { _selectedCameraId = ''; }
        else if (!data.any((c) => c.id == _selectedCameraId)) { _selectedCameraId = data.first.id; }
      });
    } catch (e) { debugPrint('[Dashboard] Camera records unavailable: $e'); }
  }

  Future<void> _initDeviceCamera() async {
    if (_cameraInitializing) return; // guard against overlapping init attempts
    setState(() {
      _cameraInitializing = true;
      _cameraPermissionDenied = false;
    });
    try {
      _availableCameras = await availableCameras();
      if (!mounted) return;
      if (_availableCameras.isEmpty) {
        setState(() => _cameraInitializing = false);
        return;
      }
      final back = _availableCameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _availableCameras.first,
      );
      // Dispose any stale controller first — re-creating one while an old
      // session is still tearing down is what caused silent init failures.
      final old = _cameraController;
      _cameraController = null;
      if (old != null) {
        try {
          await old.dispose();
        } catch (_) {}
      }

      final controller = CameraController(back, ResolutionPreset.medium, enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cameraController = controller;
        _cameraInitializing = false;
      });
    } catch (e) {
      if (!mounted) return;
      final isPermissionIssue = e is CameraException &&
          (e.code.toLowerCase().contains('denied') || e.code.toLowerCase().contains('restricted'));
      setState(() {
        _cameraInitializing = false;
        _cameraPermissionDenied = isPermissionIssue;
      });
      if (!isPermissionIssue) {
        // Likely a transient "camera resource busy" error (e.g. right after a
        // dispose from a lifecycle blip) rather than a real permission denial —
        // worth one automatic retry before making the user tap anything.
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted && _cameraController == null && !_cameraInitializing) {
            _initDeviceCamera();
          }
        });
      }
    }
  }

  void _startPredictionLoop() {
    _predictTimer?.cancel();
    // Runs every 2 s. TFLiteDetectionService uses rolling-average confirmation
    // (mirrors backend detection.py) with physical flame pixel verification.
    _predictTimer = Timer.periodic(const Duration(seconds: 2), (_) => _captureAndPredict());
  }

  Future<void> _captureAndPredict() async {
    if (!mounted || _cameras.isEmpty || _captureInProgress || _predictTimer?.isActive != true) return;
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      if (!_cameraInitializing) _initDeviceCamera();
      return;
    }
    if (controller.value.isTakingPicture) return;

    // Keep metadata with the frame captured before any asynchronous work.
    final cameraId = _selectedCameraId;
    final cameraInfo = _cameras.where((c) => c.id == cameraId).firstOrNull;
    final locationName = (cameraInfo?.location ?? 'Unknown Location').split(' - ').first;
    _captureInProgress = true;
    XFile? file;
    try {
      file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      if (!mounted ||
          !identical(controller, _cameraController) ||
          _predictTimer?.isActive != true ||
          cameraId != _selectedCameraId) {
        return;
      }

      final result = await TFLiteDetectionService.instance.analyzeFrame(
        jpegBytes: bytes,
        cameraId: cameraId,
        location: locationName,
      );
      if (result.confirmedAlerts.isNotEmpty && mounted) {
        await context.read<AlertsProvider>().fetchLatestEvents();
      }
    } catch (error, stack) {
      debugPrint('[Dashboard] Capture/detection failed: $error');
      debugPrintStack(stackTrace: stack);
    } finally {
      if (file != null) {
        try {
          final f = File(file.path);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      _captureInProgress = false;
    }
  }

  @override
  void dispose() {
    LocalDbService.referenceRevision.removeListener(_loadCameras);
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    _predictTimer?.cancel();
    _predictTimer = null;
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only react to a REAL background/foreground transition. `inactive` also
    // fires for brief, harmless interruptions — a system notification banner,
    // the status bar being pulled down, a permission dialog — and disposing
    // the camera on every one of those was the root cause of the feed randomly
    // dropping to "No camera feed" shortly after an alert notification fired.
    if (state == AppLifecycleState.paused) {
      _predictTimer?.cancel();
      _predictTimer = null;
      final controller = _cameraController;
      if (controller != null && controller.value.isInitialized) {
        controller.dispose();
      }
      _cameraController = null;
    } else if (state == AppLifecycleState.resumed) {
      if (_cameraController == null && !_cameraInitializing) {
        _initDeviceCamera().then((_) {
          if (mounted && _predictTimer == null) {
            _startPredictionLoop();
          }
        });
      }
    }
  }

  String get _timeStr {
    final h = _now.hour.toString().padLeft(2, '0');
    final m = _now.minute.toString().padLeft(2, '0');
    final s = _now.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final alertsProvider = context.watch<AlertsProvider>();
    final alerts = alertsProvider.alerts;
    final cameraInfo = _cameras.where((c) => c.id == _selectedCameraId).firstOrNull;

    return Scaffold(
      backgroundColor: context.bgPrimary,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.accentPrimary,
          onRefresh: () => alertsProvider.fetchLatestEvents(),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(Icons.menu_rounded, color: context.textPrimary, size: 24),
                      tooltip: 'Navigation Menu',
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('INTELLIGUARD', style: TextStyle(fontSize: 11, color: context.textMuted, letterSpacing: 1, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 2),
                          Text('Live Overview', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: context.textPrimary, letterSpacing: -0.5)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.accentPrimary.withValues(alpha: 0.1),
                        border: Border.all(color: AppColors.borderBright),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.accentPrimary, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Text(_timeStr, style: AppTheme.mono(size: 12, color: AppColors.accentPrimary, weight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              if (_cameras.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 14, color: context.textMuted),
                      const SizedBox(width: 6),
                      Text('Add cameras in Camera Management to start detection.',
                          style: TextStyle(color: context.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
              // Live camera feed
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    height: 300,
                    width: double.infinity,
                    decoration: BoxDecoration(color: const Color(0xFF050D1A), border: Border.all(color: AppColors.borderDefault)),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_cameraController != null && _cameraController!.value.isInitialized)
                          FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: _cameraController!.value.previewSize?.height ?? 1,
                              height: _cameraController!.value.previewSize?.width ?? 1,
                              child: CameraPreview(_cameraController!),
                            ),
                          )
                        else
                          Center(
                            child: _cameraInitializing
                                ? const CircularProgressIndicator(color: AppColors.accentPrimary)
                                : Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.videocam_off_outlined, color: AppColors.textMuted, size: 32),
                                      const SizedBox(height: 8),
                                      Text(
                                        _cameraPermissionDenied ? 'Camera permission needed' : 'No camera feed',
                                        style: const TextStyle(color: AppColors.textMuted),
                                      ),
                                      const SizedBox(height: 4),
                                      TextButton(
                                        onPressed: _initDeviceCamera,
                                        child: Text(_cameraPermissionDenied ? 'Grant Camera Access' : 'Retry'),
                                      ),
                                    ],
                                  ),
                          ),
                        Positioned(
                          top: 12,
                          left: 12,
                          child: Row(
                            children: [
                              _badge('REC', Colors.red.withValues(alpha: 0.85), Colors.white, dot: true),
                              const SizedBox(width: 8),
                              _badge('AI', AppColors.accentPrimary.withValues(alpha: 0.2), AppColors.accentPrimary, border: true),
                            ],
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)])),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(cameraInfo?.location ?? 'Main Entrance', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                                    Text('$_selectedCameraId \u00b7 1080p HDR', style: AppTheme.mono(size: 11, color: Colors.white70)),
                                  ],
                                ),
                                Text(_timeStr, style: AppTheme.mono(size: 11, color: Colors.white70)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Camera tabs
              if (_cameras.isNotEmpty)
                SizedBox(
                  height: 52,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 10, 32, 10),
                    children: _cameras.map((c) {
                      final selected = c.id == _selectedCameraId;
                      // Show name if available, fall back to id. Constrain width so it never overflows.
                      final displayLabel = (c.name.isNotEmpty) ? c.name : c.id;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Tooltip(
                          message: '${c.id}  ·  ${c.location}',
                          child: GestureDetector(
                            onTap: () => setState(() => _selectedCameraId = c.id),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                              constraints: const BoxConstraints(maxWidth: 140),
                              decoration: BoxDecoration(
                                color: selected ? AppColors.accentPrimary.withValues(alpha: 0.15) : context.bgCard,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: selected ? AppColors.accentPrimary : context.borderDefault,
                                  width: selected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (selected) Container(
                                    width: 6, height: 6,
                                    margin: const EdgeInsets.only(right: 6),
                                    decoration: const BoxDecoration(color: AppColors.accentPrimary, shape: BoxShape.circle),
                                  ),
                                  Flexible(
                                    child: Text(
                                      displayLabel,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: selected ? AppColors.accentPrimary : context.textSecondary,
                                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

              const SizedBox(height: 4),

              // Stat cards
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    StatCard(
                      value: alerts.where((a) => a.type.toLowerCase().contains('fire') || a.type.toLowerCase().contains('smoke')).length.toString(),
                      label: 'Fire / Smoke',
                      sublabel: 'Alerts Today',
                      color: AppColors.fire,
                      dim: AppColors.fire.withValues(alpha: 0.15),
                      icon: Icons.local_fire_department_outlined,
                    ),
                    const SizedBox(width: 12),
                    StatCard(
                      value: alerts.where((a) => a.type.toLowerCase().contains('violence')).length.toString(),
                      label: 'Violence',
                      sublabel: 'Alerts Today',
                      color: AppColors.violence,
                      dim: AppColors.violence.withValues(alpha: 0.15),
                      icon: Icons.warning_amber_outlined,
                    ),
                    const SizedBox(width: 12),
                    StatCard(
                      value: alerts.where((a) => a.type.toLowerCase().contains('restricted')).length.toString(),
                      label: 'Zone Breaches',
                      sublabel: 'Alerts Today',
                      color: AppColors.warning,
                      dim: AppColors.warning.withValues(alpha: 0.15),
                      icon: Icons.block_outlined,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Recent alerts
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Recent Alerts', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.textPrimary)),
                        TextButton(onPressed: widget.onViewAllAlerts, child: const Text('View All', style: TextStyle(color: AppColors.accentPrimary, fontSize: 12))),
                      ],
                    ),
                    if (alertsProvider.loading)
                      const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: AppColors.accentPrimary)))
                    else if (alerts.isEmpty)
                      Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('No alerts yet.', style: TextStyle(color: context.textMuted))))
                    else
                      ...alerts.take(5).map((a) => AlertRow(
                        alert: a,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => IncidentDetailsScreen(event: a)),
                          );
                        },
                      )),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String text, Color bg, Color fg, {bool dot = false, bool border = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: border ? Border.all(color: fg.withValues(alpha: 0.5)) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(width: 6, height: 6, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
            const SizedBox(width: 5),
          ],
          Text(text, style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
