// ============================================================
// stat_card.dart - Small metric card used on the Dashboard
// ============================================================
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class StatCard extends StatelessWidget {
  final String value;
  final String label;
  final String sublabel;
  final Color color;
  final Color dim;
  final IconData icon;

  const StatCard({
    super.key,
    required this.value,
    required this.label,
    required this.sublabel,
    required this.color,
    required this.dim,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.borderSubtle),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: dim, borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 17, color: color),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(color: color, fontSize: 30, fontWeight: FontWeight.bold, letterSpacing: -1)),
                const SizedBox(height: 4),
                // Fixed 2-line height for the label regardless of whether THIS
                // card's text actually wraps — otherwise a short label like
                // "Violence" (1 line) sits higher than "Fire / Smoke" (2 lines)
                // and the three cards visibly misalign with each other.
                SizedBox(
                  height: 32,
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.15),
                  ),
                ),
                Text(sublabel, style: TextStyle(color: context.textSecondary, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
