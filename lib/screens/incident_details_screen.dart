// ============================================================
// incident_details_screen.dart — Full incident detail view
// Shows all metadata for a single event (read-only).
// Status is changed from the Event Logs list card directly.
// Full Light/Dark theme support.
// ============================================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_event.dart';
import '../providers/alerts_provider.dart';
import '../theme/app_theme.dart';

class IncidentDetailsScreen extends StatelessWidget {
  final AppEvent event;
  const IncidentDetailsScreen({super.key, required this.event});

  static IconData _typeIcon(String type) {
    final t = type.toLowerCase();
    if (t.contains('fire')) return Icons.local_fire_department_rounded;
    if (t.contains('smoke')) return Icons.blur_on_rounded;
    if (t.contains('violence')) return Icons.warning_amber_rounded;
    if (t.contains('restricted')) return Icons.block_rounded;
    return Icons.warning_amber_rounded;
  }

  static Color _typeColor(String type) {
    final t = type.toLowerCase();
    if (t.contains('fire')) return AppColors.fire;
    if (t.contains('smoke')) return AppColors.smoke;
    if (t.contains('violence')) return AppColors.violence;
    if (t.contains('restricted')) return AppColors.restricted;
    return AppColors.textMuted;
  }

  static ({Color color, Color bg, String label}) _statusBadge(String status) {
    switch (status) {
      case 'Resolved':
        return (color: AppColors.online, bg: AppColors.online.withValues(alpha: 0.12), label: 'Resolved');
      case 'In Progress':
        return (color: AppColors.warning, bg: AppColors.warning.withValues(alpha: 0.12), label: 'In Progress');
      default:
        return (color: AppColors.fire, bg: AppColors.fire.withValues(alpha: 0.12), label: 'Detected');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Always read the latest version of this event from the provider (live status updates),
    // falling back to the passed-in event if the provider doesn't have it yet.
    AppEvent e = event;
    try {
      final live = context.watch<AlertsProvider>()
          .alerts
          .where((a) => a.id == event.id)
          .firstOrNull;
      if (live != null) e = live;
    } catch (_) {
      // Provider not in scope (e.g. navigated from outside MainShell) — use widget.event
    }

    final color = _typeColor(e.type);
    final badge = _statusBadge(e.status);

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
        title: Text(
          'Incident Details',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: badge.bg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: badge.color.withValues(alpha: 0.3)),
              ),
              child: Text(
                badge.label,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: badge.color),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Event type hero card ──────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(_typeIcon(e.type), color: color, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.type,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: context.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: context.bgCard,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: context.borderSubtle),
                              ),
                              child: Text(
                                e.cameraId,
                                style: const TextStyle(
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
                                e.location.isNotEmpty ? e.location : 'Campus Area',
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
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Details card ─────────────────────────────────────────
            _detailCard(context, 'Incident Details', [
              _detailRow(context, Icons.videocam_outlined, 'Camera ID', e.cameraId),
              _detailRow(context, Icons.location_on_outlined, 'Location',
                  e.location.isNotEmpty ? e.location : 'Unknown Location'),
              _detailRow(context, Icons.access_time_rounded, 'Timestamp',
                  e.time.isNotEmpty ? e.time : '—'),
              _detailRow(context, Icons.speed_rounded, 'Confidence Score',
                  '${(e.confidence * 100).toStringAsFixed(1)}%'),
            ]),

            const SizedBox(height: 16),

            // ── Status card ──────────────────────────────────────────
            _detailCard(context, 'Response & Status', [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: badge.color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 10),
                        Text('Current Status',
                            style: TextStyle(fontSize: 13, color: context.textSecondary)),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: badge.bg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: badge.color.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        badge.label,
                        style: TextStyle(
                            fontSize: 12, color: badge.color, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ]),

            const SizedBox(height: 12),

            // ── Hint ─────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: context.bgCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.borderSubtle),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 15, color: context.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'To change the status, tap the status badge on the incident card in Event Logs.',
                      style: TextStyle(fontSize: 11, color: context.textMuted, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Back button ──────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Go Back'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.textSecondary,
                  side: BorderSide(color: context.borderDefault),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailCard(BuildContext context, String title, List<Widget> rows) {
    return Container(
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Text(
              title,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.textMuted,
                  letterSpacing: 0.5),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Divider(color: context.borderSubtle, height: 1),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Column(children: rows),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(BuildContext context, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: context.textMuted),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(fontSize: 13, color: context.textSecondary)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                  fontSize: 13, color: context.textPrimary, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
