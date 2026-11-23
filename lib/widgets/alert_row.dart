// ============================================================
// alert_row.dart - Shared alert list row (Dashboard "Recent Alerts")
// ============================================================
import 'package:flutter/material.dart';
import '../models/app_event.dart';
import '../theme/app_theme.dart';

String _iconFor(String type) {
  switch (type) {
    case 'Fire':
      return '\u{1F525}';
    case 'Smoke':
      return '\u{1F4A8}';
    case 'Violence':
      return '\u26A0\uFE0F';
    case 'Restricted Zone':
      return '\u26D4';
    default:
      return '\u26A0\uFE0F';
  }
}

class AlertRow extends StatelessWidget {
  final AppEvent alert;
  final VoidCallback? onTap;

  const AlertRow({super.key, required this.alert, this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = AppColors.statusStyle(alert.status);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.bgCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.borderSubtle),
        ),
        child: Row(
          children: [
            Container(width: 3, height: 36, decoration: BoxDecoration(color: status.color, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 12),
            Text(_iconFor(alert.type), style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(alert.type, style: TextStyle(fontWeight: FontWeight.w600, color: context.textPrimary, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text('${alert.cameraId} \u00b7 ${alert.location}',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: context.textSecondary, fontSize: 11)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: status.bg, borderRadius: BorderRadius.circular(20)),
                  child: Text(status.label, style: TextStyle(color: status.color, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 4),
                Text(alert.timeOfDay, style: AppTheme.mono(size: 10, color: context.textMuted)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
