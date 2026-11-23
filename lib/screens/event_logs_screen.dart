// ============================================================
// event_logs_screen.dart — System event history
// Professional redesign: search, filter chips, grouped timeline,
// and bidirectional status dropdown on each event card.
// ============================================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_event.dart';
import '../providers/alerts_provider.dart';
import '../services/cloud_api.dart';
import '../services/sync_rules.dart';
import '../theme/app_theme.dart';
import 'incident_details_screen.dart';

const _kFilterTabs = ['All', 'Fire / Smoke', 'Violence', 'Zone Breach'];

String _localDateStr(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '$y-$m-$dd';
}

Map<String, List<AppEvent>> _groupByDate(List<AppEvent> logs) {
  final now = DateTime.now();
  final todayStr = _localDateStr(now);
  final yesterdayStr = _localDateStr(now.subtract(const Duration(days: 1)));

  final groups = {'TODAY': <AppEvent>[], 'YESTERDAY': <AppEvent>[], 'OLDER': <AppEvent>[]};
  for (final log in logs) {
    final prefix = log.datePrefix;
    if (prefix.length < 10 || prefix == todayStr) {
      groups['TODAY']!.add(log);
    } else if (prefix == yesterdayStr) {
      groups['YESTERDAY']!.add(log);
    } else {
      groups['OLDER']!.add(log);
    }
  }
  for (final list in groups.values) {
    list.sort((a, b) => b.time.compareTo(a.time));
  }
  return groups;
}

class EventLogsScreen extends StatefulWidget {
  const EventLogsScreen({super.key});

  @override
  State<EventLogsScreen> createState() => _EventLogsScreenState();
}

class _EventLogsScreenState extends State<EventLogsScreen> {
  String _activeTab = 'All';
  String _search = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alertsProvider = context.watch<AlertsProvider>();
    final filtered = alertsProvider.alerts.where((log) {
      final s = _search.toLowerCase();
      final matchesSearch = s.isEmpty ||
          log.type.toLowerCase().contains(s) ||
          log.cameraId.toLowerCase().contains(s) ||
          log.location.toLowerCase().contains(s);

      bool matchesTab = true;
      if (_activeTab == 'Fire / Smoke') {
        matchesTab = log.type.toLowerCase().contains('fire') || log.type.toLowerCase().contains('smoke');
      } else if (_activeTab == 'Violence') {
        matchesTab = log.type.toLowerCase().contains('violence');
      } else if (_activeTab == 'Zone Breach') {
        matchesTab = log.type.toLowerCase().contains('restricted');
      }
      return matchesSearch && matchesTab;
    }).toList();

    final grouped = _groupByDate(filtered);

    return Scaffold(
      backgroundColor: context.bgPrimary,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.accentPrimary,
          backgroundColor: context.bgCard,
          onRefresh: () => alertsProvider.fetchLatestEvents(),
          child: CustomScrollView(
            slivers: [
              // ── Header ──────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('EVENT LOGS', style: TextStyle(fontSize: 10, color: AppColors.accentPrimary, letterSpacing: 2, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text('Security History', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: context.textPrimary)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: context.bgCard,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: context.borderSubtle),
                        ),
                        child: Text('${filtered.length} events',
                            style: TextStyle(fontSize: 11, color: context.textSecondary, fontWeight: FontWeight.w500)),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Search ──────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: context.bgCard,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: context.borderSubtle),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _search = v),
                      style: TextStyle(color: context.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        prefixIcon: Icon(Icons.search_rounded, size: 18, color: context.textMuted),
                        hintText: 'Search camera, type, location…',
                        hintStyle: TextStyle(color: context.textMuted, fontSize: 13),
                        suffixIcon: _search.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.close_rounded, size: 16, color: context.textMuted),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _search = '');
                                })
                            : null,
                      ),
                    ),
                  ),
                ),
              ),

              // ── Filter chips ─────────────────────────────────────────
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 52,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    itemCount: _kFilterTabs.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final tab = _kFilterTabs[i];
                      final active = tab == _activeTab;
                      return GestureDetector(
                        onTap: () => setState(() => _activeTab = tab),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                          decoration: BoxDecoration(
                            color: active ? AppColors.accentPrimary.withValues(alpha: 0.15) : context.bgCard,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: active ? AppColors.accentPrimary : context.borderDefault,
                              width: active ? 1.5 : 1,
                            ),
                          ),
                          child: Text(tab,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: active ? AppColors.accentPrimary : context.textSecondary,
                                  fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // ── Content ──────────────────────────────────────────────
              if (alertsProvider.loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator(color: AppColors.accentPrimary)),
                )
              else if (filtered.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off_rounded, size: 40, color: AppColors.textMuted.withValues(alpha: 0.5)),
                        const SizedBox(height: 12),
                        const Text('No events match your criteria.',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      for (final groupKey in ['TODAY', 'YESTERDAY', 'OLDER'])
                        if (grouped[groupKey]!.isNotEmpty)
                          _buildGroup(context, groupKey, grouped[groupKey]!, alertsProvider),
                    ]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroup(BuildContext context, String label, List<AppEvent> logs, AlertsProvider provider) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: context.textMuted, letterSpacing: 1.5)),
            const SizedBox(width: 10),
            Expanded(child: Divider(color: context.borderSubtle, height: 1)),
          ]),
          const SizedBox(height: 12),
          for (final log in logs)
            _LogCard(
              alert: log,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => IncidentDetailsScreen(event: log)),
                );
              },
              onStatusChanged: (newStatus) async {
                try {
                  await provider.setAlertStatus(log.id, newStatus);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(friendlyCloudError(e)), backgroundColor: AppColors.fire),
                    );
                  }
                }
              },
            ),
        ],
      ),
    );
  }
}

// ── Event log card ────────────────────────────────────────────────────────────

class _LogCard extends StatelessWidget {
  final AppEvent alert;
  final VoidCallback onTap;
  final Future<void> Function(String status) onStatusChanged;
  const _LogCard({required this.alert, required this.onTap, required this.onStatusChanged});

  IconData get _icon {
    final t = alert.type.toLowerCase();
    if (t.contains('fire')) return Icons.local_fire_department_rounded;
    if (t.contains('smoke')) return Icons.blur_on_rounded;
    if (t.contains('violence')) return Icons.warning_amber_rounded;
    if (t.contains('restricted')) return Icons.block_rounded;
    return Icons.warning_amber_rounded;
  }

  Color get _typeColor {
    final t = alert.type.toLowerCase();
    if (t.contains('fire')) return AppColors.fire;
    if (t.contains('smoke')) return AppColors.smoke;
    if (t.contains('violence')) return AppColors.violence;
    if (t.contains('restricted')) return AppColors.restricted;
    return AppColors.textMuted;
  }

  ({Color color, Color bg, String label}) get _statusStyle {
    switch (alert.status) {
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
    final badge = _statusStyle;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: context.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.borderSubtle),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Type icon
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _typeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_icon, color: _typeColor, size: 20),
              ),
              const SizedBox(width: 12),

              // Event info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(alert.type,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.textPrimary)),
                    const SizedBox(height: 3),
                    Row(children: [
                      Text(alert.cameraId,
                          style: AppTheme.mono(size: 10, color: context.textMuted, weight: FontWeight.w500)),
                      if (alert.location.isNotEmpty) ...[
                        Text('  ·  ', style: TextStyle(color: context.textMuted, fontSize: 10)),
                        Flexible(
                          child: Text(alert.location,
                              style: TextStyle(fontSize: 10, color: context.textMuted),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 3),
                    Text(alert.timeOfDay,
                        style: AppTheme.mono(size: 10, color: context.textMuted.withValues(alpha: 0.7))),
                  ],
                ),
              ),

              // Status dropdown — tapping lets user pick any status (does NOT navigate)
              GestureDetector(
                onTap: () => _showStatusSheet(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: badge.bg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: badge.color.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(badge.label,
                          style: TextStyle(
                              color: badge.color, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
                      const SizedBox(width: 4),
                      Icon(Icons.unfold_more_rounded, size: 12, color: badge.color.withValues(alpha: 0.7)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }



  void _showStatusSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text('Update Status',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: ctx.textPrimary)),
              ),
              IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: Icon(Icons.close_rounded, size: 18, color: ctx.textMuted)),
            ]),
            const SizedBox(height: 4),
            Text('${alert.type}  ·  ${alert.cameraId}',
                style: TextStyle(fontSize: 11, color: ctx.textSecondary)),
            const SizedBox(height: 20),
            for (final status in eventStatuses)
              _StatusOption(
                label: status,
                selected: alert.status == status,
                onTap: () {
                  Navigator.pop(ctx);
                  if (status != alert.status) onStatusChanged(status);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _StatusOption({required this.label, required this.selected, required this.onTap});

  Color get _color {
    switch (label) {
      case 'Resolved': return AppColors.online;
      case 'In Progress': return AppColors.warning;
      default: return AppColors.fire;
    }
  }

  IconData get _icon {
    switch (label) {
      case 'Resolved': return Icons.check_circle_rounded;
      case 'In Progress': return Icons.timelapse_rounded;
      default: return Icons.radio_button_on_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? _color.withValues(alpha: 0.12) : context.bgElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: selected ? _color.withValues(alpha: 0.5) : context.borderDefault, width: selected ? 1.5 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          splashColor: _color.withValues(alpha: 0.2),
          highlightColor: _color.withValues(alpha: 0.1),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Icon(_icon, color: _color, size: 18),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: TextStyle(color: _color, fontWeight: FontWeight.w600, fontSize: 14))),
              if (selected) Icon(Icons.check_rounded, color: _color, size: 18),
            ]),
          ),
        ),
      ),
    );
  }
}
