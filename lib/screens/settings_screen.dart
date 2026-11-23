// ============================================================
// settings_screen.dart — Collapsible settings with working
// Light/Dark theme, functional detection controls, camera
// management navigation, and alert preferences.
// ============================================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../services/tflite_detection_service.dart';
import '../theme/app_theme.dart';
import 'admin_panel_screen.dart';
import 'camera_management_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Expanded section tracker
  String? _expanded; // null = all collapsed

  // Detection settings (read initial values from the service)
  bool _fireEnabled = TFLiteDetectionService.fireDetectionEnabled;
  bool _violenceEnabled = TFLiteDetectionService.violenceDetectionEnabled;
  bool _personEnabled = TFLiteDetectionService.personDetectionEnabled;
  double _fireThreshold = TFLiteDetectionService.fireThreshold;
  double _smokeThreshold = TFLiteDetectionService.smokeThreshold;

  // Alert preferences (UI only for now — can be persisted via SharedPreferences if needed)
  bool _pushNotifications = true;
  bool _soundAlerts = true;
  bool _vibration = true;

  void _toggle(String section) =>
      setState(() => _expanded = _expanded == section ? null : section);

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final cs = Theme.of(context).colorScheme;
    final isDark = themeProvider.mode == ThemeMode.dark;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            // ── Header ────────────────────────────────────────────────
            Text('SETTINGS',
                style: TextStyle(fontSize: 10, color: AppColors.accentPrimary,
                    letterSpacing: 2, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Configuration',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                    color: cs.onSurface)),
            const SizedBox(height: 24),

            // ── Appearance ────────────────────────────────────────────
            _buildSectionCard(
              icon: Icons.palette_outlined,
              title: 'Appearance',
              subtitle: isDark ? 'Dark mode active' : 'Light mode active',
              isExpanded: false, // appearance stays always visible as toggles
              onTap: null,
              trailing: null,
              alwaysShow: Row(children: [
                _themeChip('Light', Icons.light_mode_rounded, !isDark, () {
                  context.read<ThemeProvider>().setLight();
                }),
                const SizedBox(width: 10),
                _themeChip('Dark', Icons.dark_mode_rounded, isDark, () {
                  context.read<ThemeProvider>().setDark();
                }),
              ]),
            ),
            const SizedBox(height: 12),

            // ── Detection Settings ────────────────────────────────────
            _buildSectionCard(
              icon: Icons.tune_rounded,
              title: 'Detection Settings',
              subtitle: 'Configure AI detection types and thresholds',
              isExpanded: _expanded == 'detection',
              onTap: () => _toggle('detection'),
              trailing: null,
              expandedContent: _detectionContent(context),
            ),
            const SizedBox(height: 10),

            // ── Camera Settings ───────────────────────────────────────
            _buildSectionCard(
              icon: Icons.videocam_outlined,
              title: 'Camera Settings',
              subtitle: 'Configure camera detection parameters',
              isExpanded: _expanded == 'camera_settings',
              onTap: () => _toggle('camera_settings'),
              trailing: null,
              expandedContent: _cameraSettingsContent(context),
            ),
            const SizedBox(height: 10),

            // ── Camera Management ─────────────────────────────────────
            _buildSectionCard(
              icon: Icons.camera_alt_outlined,
              title: 'Camera Management',
              subtitle: 'Add, remove or edit cameras',
              isExpanded: false,
              onTap: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const CameraManagementScreen()));
              },
              trailing: Icon(Icons.open_in_new_rounded, size: 16,
                  color: AppColors.accentPrimary),
            ),
            const SizedBox(height: 10),

            // ── Account & Security Team (Admin) ──────────────────────
            _buildSectionCard(
              icon: Icons.manage_accounts_outlined,
              title: 'Account & Security Team',
              subtitle: 'Add/manage security guards, roles, and admin settings',
              isExpanded: false,
              onTap: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AdminPanelScreen()));
              },
              trailing: Icon(Icons.open_in_new_rounded, size: 16,
                  color: AppColors.accentPrimary),
            ),
            const SizedBox(height: 10),

            // ── Alert Settings ────────────────────────────────────────
            _buildSectionCard(
              icon: Icons.notifications_outlined,
              title: 'Alert Settings',
              subtitle: 'Push, sound and vibration preferences',
              isExpanded: _expanded == 'alerts',
              onTap: () => _toggle('alerts'),
              trailing: null,
              expandedContent: _alertsContent(context),
            ),
            const SizedBox(height: 10),

            // ── About ─────────────────────────────────────────────────
            _buildSectionCard(
              icon: Icons.info_outline_rounded,
              title: 'About IntelliGuard',
              subtitle: 'Version, account and organization info',
              isExpanded: _expanded == 'about',
              onTap: () => _toggle('about'),
              trailing: null,
              expandedContent: _aboutContent(context, auth),
            ),
            const SizedBox(height: 28),

            // ── Sign Out ──────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: () => _confirmLogout(context),
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text('Log Out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.fire,
                  side: const BorderSide(color: AppColors.fire, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Section card builder ──────────────────────────────────────────────────

  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isExpanded,
    required VoidCallback? onTap,
    required Widget? trailing,
    Widget? expandedContent,
    Widget? alwaysShow,
  }) {
    final cs = Theme.of(context).colorScheme;
    final cardColor = cs.surface;
    final borderColor = Theme.of(context).dividerColor;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row header
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.accentPrimary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 18, color: AppColors.accentPrimary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                        color: cs.onSurface)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5))),
                  ]),
                ),
                trailing ??
                    (onTap != null
                        ? AnimatedRotation(
                            turns: isExpanded ? 0.25 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: Icon(Icons.chevron_right_rounded,
                                size: 20, color: cs.onSurface.withValues(alpha: 0.4)),
                          )
                        : const SizedBox.shrink()),
              ]),
            ),
          ),

          // Always-visible content (e.g. theme buttons)
          if (alwaysShow != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: alwaysShow,
            ),

          // Expandable content
          if (expandedContent != null)
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Column(children: [
                Divider(color: Theme.of(context).dividerColor, height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: expandedContent,
                ),
              ]),
              crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 250),
            ),
        ],
      ),
    );
  }

  // ── Theme chip ────────────────────────────────────────────────────────────

  Widget _themeChip(String label, IconData icon, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.accentPrimary.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.accentPrimary : Theme.of(context).dividerColor,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 20, color: selected ? AppColors.accentPrimary
                : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
            const SizedBox(height: 5),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                color: selected ? AppColors.accentPrimary
                    : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
          ]),
        ),
      ),
    );
  }

  // ── Expanded section contents ─────────────────────────────────────────────

  Widget _detectionContent(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _detectionRow('Fire & Smoke Detection', Icons.local_fire_department_rounded,
          AppColors.fire, _fireEnabled, (v) {
        setState(() => _fireEnabled = v);
        TFLiteDetectionService.setFireDetection(enabled: v);
      }),
      if (_fireEnabled) ...[
        const SizedBox(height: 4),
        _thresholdSlider('Fire Confidence', _fireThreshold, AppColors.fire, (v) {
          setState(() => _fireThreshold = v);
          TFLiteDetectionService.setFireThreshold(v);
        }),
        _thresholdSlider('Smoke Confidence', _smokeThreshold, AppColors.smoke, (v) {
          setState(() => _smokeThreshold = v);
          TFLiteDetectionService.setSmokeThreshold(v);
        }),
      ],
      const SizedBox(height: 8),
      _detectionRow('Violence / Fighting', Icons.warning_amber_rounded,
          AppColors.violence, _violenceEnabled, (v) {
        setState(() => _violenceEnabled = v);
        TFLiteDetectionService.setViolenceDetection(enabled: v);
      }),
      const SizedBox(height: 8),
      _detectionRow('Restricted Zone (Person)', Icons.person_outlined,
          AppColors.restricted, _personEnabled, (v) {
        setState(() => _personEnabled = v);
        TFLiteDetectionService.setPersonDetection(enabled: v);
      }),
      const SizedBox(height: 4),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.accentPrimary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Icon(Icons.info_outline_rounded, size: 14, color: AppColors.accentPrimary),
          const SizedBox(width: 8),
          Flexible(
            child: Text('Changes apply immediately. Detection runs on-device using TFLite.',
                style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.6))),
          ),
        ]),
      ),
    ]);
  }

  Widget _cameraSettingsContent(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Frame Analysis', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
          color: cs.onSurface.withValues(alpha: 0.5), letterSpacing: 0.5)),
      const SizedBox(height: 10),
      _infoTile(Icons.speed_rounded, 'Detection Interval', '1 frame / sec'),
      _infoTile(Icons.crop_rounded, 'Input Resolution', '224 × 224 px'),
      _infoTile(Icons.timer_outlined, 'Alert Cooldown', '60 seconds'),
      _infoTile(Icons.layers_rounded, 'Model Engine', 'TFLite On-Device'),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.2)),
        ),
        child: Row(children: [
          Icon(Icons.settings_suggest_outlined, size: 14, color: AppColors.warning),
          const SizedBox(width: 8),
          Flexible(
            child: Text('Advanced camera parameters are configured during camera setup in Camera Management.',
                style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.6))),
          ),
        ]),
      ),
    ]);
  }

  Widget _alertsContent(BuildContext context) {
    return Column(children: [
      _switchTile('Push Notifications', 'Receive alerts when threats are detected',
          Icons.notifications_active_rounded, AppColors.accentPrimary,
          _pushNotifications, (v) => setState(() => _pushNotifications = v)),
      const SizedBox(height: 8),
      _switchTile('Sound Alerts', 'Play sound when a new incident is detected',
          Icons.volume_up_rounded, AppColors.accentPrimary,
          _soundAlerts, (v) => setState(() => _soundAlerts = v)),
      const SizedBox(height: 8),
      _switchTile('Vibration', 'Vibrate on alert',
          Icons.vibration_rounded, AppColors.accentPrimary,
          _vibration, (v) => setState(() => _vibration = v)),
    ]);
  }

  Widget _aboutContent(BuildContext context, AuthProvider auth) {
    return Column(children: [
      _infoTile(Icons.tag_rounded, 'Version', '1.0.0'),
      _infoTile(Icons.build_circle_outlined, 'Build', 'Release'),
      _infoTile(Icons.memory_rounded, 'AI Engine', 'TFLite On-Device'),
      _infoTile(Icons.person_outline_rounded, 'Account',
          auth.scope?.member.userId ?? '—'),
      _infoTile(Icons.business_outlined, 'Organization',
          auth.scope?.member.orgId ?? '—'),
      _infoTile(Icons.badge_outlined, 'Role',
          (auth.scope?.member.role ?? '').toUpperCase()),
    ]);
  }

  // ── Reusable row widgets ──────────────────────────────────────────────────

  Widget _detectionRow(String label, IconData icon, Color color, bool value,
      ValueChanged<bool> onChanged) {
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      Container(
        width: 32, height: 32,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: color, size: 16),
      ),
      const SizedBox(width: 12),
      Expanded(child: Text(label, style: TextStyle(fontSize: 13,
          fontWeight: FontWeight.w600, color: cs.onSurface))),
      Switch(
        value: value, onChanged: onChanged,
        activeThumbColor: AppColors.accentPrimary,
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppColors.accentPrimary.withValues(alpha: 0.3)
                : cs.onSurface.withValues(alpha: 0.1)),
      ),
    ]);
  }

  Widget _thresholdSlider(String label, double value, Color color,
      ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: TextStyle(fontSize: 11,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
          Text('${(value * 100).toInt()}%',
              style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
        ]),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: color,
            inactiveTrackColor: color.withValues(alpha: 0.15),
            thumbColor: color,
            overlayColor: color.withValues(alpha: 0.12),
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: Slider(value: value, min: 0.5, max: 0.99, divisions: 49,
              onChanged: onChanged),
        ),
      ]),
    );
  }

  Widget _switchTile(String title, String subtitle, IconData icon, Color color,
      bool value, ValueChanged<bool> onChanged) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
              color: cs.onSurface)),
          Text(subtitle, style: TextStyle(fontSize: 10,
              color: cs.onSurface.withValues(alpha: 0.45))),
        ])),
        Switch(
          value: value, onChanged: onChanged,
          activeThumbColor: color,
          trackColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? color.withValues(alpha: 0.3)
                  : cs.onSurface.withValues(alpha: 0.1)),
        ),
      ]),
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        Icon(icon, size: 15, color: AppColors.accentPrimary.withValues(alpha: 0.7)),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: 0.6))),
        const Spacer(),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
            color: cs.onSurface)),
      ]),
    );
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  Future<void> _confirmLogout(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
            'Are you sure you want to sign out?\nAny unsynced changes will upload when you sign back in.',
            style: TextStyle(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.fire, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (yes == true && context.mounted) {
      context.read<AuthProvider>().logout();
    }
  }
}
