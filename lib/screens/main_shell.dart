// ============================================================
// main_shell.dart — Navigation shell
// 4-tab bottom nav: Home | History | Analytics | Settings
// Drawer for Account, Admin, Cameras & Zones.
// Full Light/Dark theme support.
// ============================================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/cloud_sync_service.dart';
import '../providers/auth_provider.dart';

import 'dashboard_screen.dart';
import 'event_logs_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'admin_panel_screen.dart';
import 'camera_management_screen.dart';
import 'restricted_zones_screen.dart';
import '../theme/app_theme.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  void _goToLogs() => setState(() => _index = 1);

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    CloudSyncService? sync;
    try {
      sync = context.watch<CloudSyncService>();
    } catch (_) {}
    final auth = context.watch<AuthProvider>();

    final screens = [
      DashboardScreen(onViewAllAlerts: _goToLogs),
      const EventLogsScreen(),
      const ReportsScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: context.bgPrimary,
      // ── Drawer (Account / Admin / Cameras) ──────────────────────
      drawer: Drawer(
        backgroundColor: context.bgCard,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drawer header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                decoration: BoxDecoration(
                  color: context.bgElevated,
                  border: Border(bottom: BorderSide(color: context.borderSubtle)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.accentPrimary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.shield_rounded, color: AppColors.accentPrimary, size: 24),
                    ),
                    const SizedBox(height: 12),
                    RichText(
                      text: TextSpan(children: [
                        TextSpan(
                          text: 'Intelli',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w300, color: context.textPrimary),
                        ),
                        const TextSpan(
                          text: 'Guard',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.accentPrimary),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      auth.username ?? auth.scope?.member.organization ?? 'User',
                      style: TextStyle(fontSize: 12, color: context.textSecondary),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(
                            color: AppColors.accentPrimary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            (auth.scope?.member.role ?? 'Admin').toUpperCase(),
                            style: const TextStyle(
                              fontSize: 9,
                              color: AppColors.accentPrimary,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Divider(color: context.borderSubtle, height: 1),
              ),
              const SizedBox(height: 8),

              // Navigation items
              _drawerItem(context, Icons.grid_view_rounded, 'Dashboard', () {
                setState(() => _index = 0);
                Navigator.pop(context);
              }, selected: _index == 0),
              _drawerItem(context, Icons.description_rounded, 'Event Logs', () {
                setState(() => _index = 1);
                Navigator.pop(context);
              }, selected: _index == 1),
              _drawerItem(context, Icons.bar_chart_rounded, 'Analytics & Reports', () {
                setState(() => _index = 2);
                Navigator.pop(context);
              }, selected: _index == 2),
              _drawerItem(context, Icons.videocam_outlined, 'Camera Management', () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const CameraManagementScreen()));
              }),
              _drawerItem(context, Icons.shield_outlined, 'Restricted Zones', () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const RestrictedZonesScreen()));
              }),
              _drawerItem(context, Icons.manage_accounts_rounded,
                auth.isAdmin ? 'Account & Admin Panel' : 'Account & Security Team', () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPanelScreen()));
              }),
              _drawerItem(context, Icons.settings_rounded, 'Settings', () {
                setState(() => _index = 3);
                Navigator.pop(context);
              }, selected: _index == 3),

              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Divider(color: context.borderSubtle, height: 1),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text('IntelliGuard v1.0.0', style: TextStyle(fontSize: 10, color: context.textMuted)),
              ),
            ],
          ),
        ),
      ),

      // ── Main body ─────────────────────────────────────────────────
      body: Column(
        children: [
          Expanded(child: IndexedStack(index: _index, children: screens)),
          // Sync status bar
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: context.bgCard,
              border: Border(top: BorderSide(color: context.borderSubtle)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: (sync?.syncing ?? false)
                        ? AppColors.warning
                        : (sync?.online ?? false)
                            ? AppColors.online
                            : context.textMuted,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${(sync?.syncing ?? false) ? 'Syncing' : (sync?.online ?? false) ? 'Connected' : 'Offline'}  ·  ${sync?.pendingCount ?? 0} pending'
                  '${(sync?.blockedCount ?? 0) > 0 ? '  ·  ${sync!.blockedCount} need attention' : ''}',
                  style: TextStyle(fontSize: 10, color: context.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),

      // ── Bottom navigation bar ─────────────────────────────────────
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: context.bgCard,
          border: Border(top: BorderSide(color: context.borderSubtle)),
        ),
        child: BottomNavigationBar(
          currentIndex: _index,
          onTap: (i) => setState(() => _index = i),
          backgroundColor: context.bgCard,
          selectedItemColor: AppColors.accentPrimary,
          unselectedItemColor: context.textMuted,
          selectedFontSize: 11,
          unselectedFontSize: 10,
          iconSize: 22,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history_rounded),
              activeIcon: Icon(Icons.history_rounded),
              label: 'History',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart_outlined),
              activeIcon: Icon(Icons.bar_chart_rounded),
              label: 'Analytics',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              activeIcon: Icon(Icons.settings_rounded),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem(BuildContext context, IconData icon, String label, VoidCallback onTap, {bool selected = false}) {
    return ListTile(
      leading: Icon(icon, size: 20, color: selected ? AppColors.accentPrimary : context.textSecondary),
      title: Text(label, style: TextStyle(fontSize: 13, color: selected ? AppColors.accentPrimary : context.textPrimary, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
      dense: true,
      onTap: onTap,
      tileColor: selected ? AppColors.accentPrimary.withValues(alpha: 0.08) : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }
}
