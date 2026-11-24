// ============================================================
// admin_panel_screen.dart — Account & Organization management
// Features: Team/Guard management (add/edit/remove guards),
// camera management access, admin activities log, sync status,
// and full Light/Dark mode support.
// ============================================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/cloud_api.dart';
import '../services/cloud_sync_service.dart';
import '../services/guard_management_service.dart';
import '../services/local_db_service.dart';
import '../theme/app_theme.dart';
import 'camera_management_screen.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  bool _busy = false;
  String? _message;
  List<Map<String, dynamic>> _cameras = [];
  List<Map<String, dynamic>> _guards = [];
  List<Map<String, dynamic>> _activities = [];
  List<Map<String, Object?>> _failed = [];
  int _legacyCount = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _busy = true);
    try {
      final cameras = await LocalDbService.getCameras();
      final activities = await GuardManagementService.getActivities();

      LocalDbScope? scope;
      try {
        scope = LocalDbService.requireScope();
      } catch (_) {}

      List<Map<String, dynamic>> guards = [];
      List<Map<String, Object?>> failed = [];
      int legacy = 0;

      if (scope != null) {
        failed = await LocalDbService.failedRows(scope);
        legacy = await LocalDbService.legacyCount();

        // Pull real team members from Supabase (admin only).
        // Falls back to local guard list if offline or not admin.
        if (scope.member.isAdmin) {
          try {
            final raw = await CloudApi.call(scope, 'ig_list_members', admin: true);
            final rows = (raw as List).cast<Map<String, dynamic>>();
            guards = rows.map((r) => {
              'name': (r['email'] as String? ?? '').split('@').first.replaceAll('.', ' '),
              'email': r['email'] ?? '',
              'role': r['role'] ?? 'guard',
              'shift': '—',
              'phone': '',
              'badge': (r['role'] == 'admin') ? 'ADM' : 'SEC',
              'active': r['is_active'] ?? true,
              'joined': (r['joined_at'] as String? ?? '').split('T').first,
            }).toList();
          } catch (_) {
            // Offline or error — fall back to local list
            guards = await GuardManagementService.getGuards();
          }
        } else {
          guards = await GuardManagementService.getGuards();
        }
      } else {
        guards = await GuardManagementService.getGuards();
      }

      if (mounted) {
        setState(() {
          _cameras = cameras;
          _guards = guards;
          _activities = activities;
          _failed = failed;
          _legacyCount = legacy;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _message = 'Loaded local configuration');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addGuardDialog() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only administrators can add guards.'),
          backgroundColor: AppColors.fire,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final badgeCtrl = TextEditingController();
    String role = 'Patrol Guard';
    String shift = 'Day Shift (08:00 - 16:00)';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          backgroundColor: ctx.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Add Security Guard',
              style: TextStyle(color: ctx.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Full Name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ctx.textSecondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  style: TextStyle(color: ctx.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'e.g. Asad Qureshi',
                    hintStyle: TextStyle(color: ctx.textMuted),
                    filled: true,
                    fillColor: ctx.bgElevated,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: ctx.borderDefault)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: ctx.borderDefault)),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Email Address', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ctx.textSecondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: TextStyle(color: ctx.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'e.g. asad.guard@campus.edu',
                    hintStyle: TextStyle(color: ctx.textMuted),
                    filled: true,
                    fillColor: ctx.bgElevated,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: ctx.borderDefault)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: ctx.borderDefault)),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Assigned Role', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ctx.textSecondary)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: role,
                  dropdownColor: ctx.bgElevated,
                  style: TextStyle(color: ctx.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: ctx.bgElevated,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: ctx.borderDefault)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: ctx.borderDefault)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Lead Guard', child: Text('Lead Guard / Shift In-Charge')),
                    DropdownMenuItem(value: 'Patrol Guard', child: Text('Patrol Guard (Perimeter)')),
                    DropdownMenuItem(value: 'Security Admin', child: Text('Security Admin (Control Room)')),
                  ],
                  onChanged: (v) => update(() => role = v ?? 'Patrol Guard'),
                ),
                const SizedBox(height: 12),
                Text('Duty Shift', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ctx.textSecondary)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: shift,
                  dropdownColor: ctx.bgElevated,
                  style: TextStyle(color: ctx.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: ctx.bgElevated,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: ctx.borderDefault)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: ctx.borderDefault)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Morning (08:00 - 16:00)', child: Text('Morning (08:00 - 16:00)')),
                    DropdownMenuItem(value: 'Evening (16:00 - 00:00)', child: Text('Evening (16:00 - 00:00)')),
                    DropdownMenuItem(value: 'Night (00:00 - 08:00)', child: Text('Night (00:00 - 08:00)')),
                    DropdownMenuItem(value: 'Control Room (24/7)', child: Text('Control Room (24/7)')),
                  ],
                  onChanged: (v) => update(() => shift = v ?? 'Morning (08:00 - 16:00)'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Badge / ID', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ctx.textSecondary)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: badgeCtrl,
                            style: TextStyle(color: ctx.textPrimary, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'SEC-025',
                              hintStyle: TextStyle(color: ctx.textMuted),
                              filled: true,
                              fillColor: ctx.bgElevated,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: ctx.borderDefault)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: ctx.borderDefault)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Phone Number', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ctx.textSecondary)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: phoneCtrl,
                            keyboardType: TextInputType.phone,
                            style: TextStyle(color: ctx.textPrimary, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: '+92 300...',
                              hintStyle: TextStyle(color: ctx.textMuted),
                              filled: true,
                              fillColor: ctx.bgElevated,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: ctx.borderDefault)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: ctx.borderDefault)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: ctx.textSecondary)),
            ),
            SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  final email = emailCtrl.text.trim();
                  if (name.isEmpty || email.isEmpty) return;
                  // Basic email format check
                  final emailRegex = RegExp(r'^[\w\.\+\-]+@[\w\-]+\.[a-zA-Z]{2,}$');
                  if (!emailRegex.hasMatch(email)) return;
                  Navigator.pop(ctx, true);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentPrimary,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: const Text('Add Guard'),
              ),
            ),
          ],
        ),
      ),
    );

    if (saved == true && mounted) {
      final auth = context.read<AuthProvider>();
      if (!auth.isAdmin) return;
      final scope = LocalDbService.requireScope();
      if (!scope.member.isAdmin) return;

      final email = emailCtrl.text.trim();
      final name = nameCtrl.text.trim();
      // Map UI role labels to Supabase roles
      final supabaseRole = (role == 'Security Admin') ? 'admin' : 'guard';

      // 1. Try to approve in Supabase first (the guard must have already registered)
      String? cloudError;
      try {
        await CloudApi.call(scope, 'ig_approve_member', params: {
          'p_email': email,
          'p_role': supabaseRole,
        }, admin: true);
      } catch (e) {
        cloudError = friendlyCloudError(e);
      }

      if (cloudError != null && cloudError.contains('Administrator access required')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Administrator access required.'),
              backgroundColor: AppColors.fire,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // 2. Save locally if admin
      await GuardManagementService.addGuard(
        name: name,
        email: email,
        role: role,
        shift: shift,
        phone: phoneCtrl.text.trim(),
        badge: badgeCtrl.text.trim(),
      );
      _loadData();

      if (mounted) {
        if (cloudError != null) {
          // Show what went wrong — most likely the guard hasn't registered yet
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.black, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  'Saved locally. Supabase: $cloudError',
                  style: const TextStyle(color: Colors.black, fontSize: 12),
                )),
              ]),
              backgroundColor: AppColors.warning,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 6),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$name approved and added successfully'),
              backgroundColor: AppColors.online,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
    nameCtrl.dispose();
    emailCtrl.dispose();
    phoneCtrl.dispose();
    badgeCtrl.dispose();
  }

  Future<void> _toggleGuardStatus(Map<String, dynamic> guard) async {
    if (!context.read<AuthProvider>().isAdmin) return;
    final current = guard['active'] as bool? ?? true;
    await GuardManagementService.updateGuard(guard['email'] as String, active: !current);
    _loadData();
  }

  Future<void> _changeGuardRole(Map<String, dynamic> guard) async {
    if (!context.read<AuthProvider>().isAdmin) return;
    String role = guard['role'] as String? ?? 'Patrol Guard';
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          backgroundColor: ctx.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Change Guard Role', style: TextStyle(color: ctx.textPrimary, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Select security role for ${guard['name']}:', style: TextStyle(color: ctx.textSecondary, fontSize: 13)),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: role,
                dropdownColor: ctx.bgElevated,
                style: TextStyle(color: ctx.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: ctx.bgElevated,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: ctx.borderDefault)),
                ),
                items: const [
                  DropdownMenuItem(value: 'Lead Guard', child: Text('Lead Guard')),
                  DropdownMenuItem(value: 'Patrol Guard', child: Text('Patrol Guard')),
                  DropdownMenuItem(value: 'Security Admin', child: Text('Security Admin')),
                ],
                onChanged: (v) => update(() => role = v ?? role),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: TextStyle(color: ctx.textSecondary))),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentPrimary,
                foregroundColor: Colors.black,
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (saved == true && mounted) {
      await GuardManagementService.updateGuard(guard['email'] as String, role: role);
      _loadData();
    }
  }

  Future<void> _removeGuard(Map<String, dynamic> guard) async {
    if (!context.read<AuthProvider>().isAdmin) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Remove Guard', style: TextStyle(color: ctx.textPrimary, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to remove ${guard['name']} from the campus security roster?',
            style: TextStyle(color: ctx.textSecondary, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: TextStyle(color: ctx.textSecondary))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.fire, foregroundColor: Colors.white),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await GuardManagementService.removeGuard(guard['email'] as String);
      _loadData();
    }
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Sign Out', style: TextStyle(color: ctx.textPrimary, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to sign out?', style: TextStyle(color: ctx.textSecondary, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: TextStyle(color: ctx.textSecondary))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.fire, foregroundColor: Colors.white),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (yes == true && context.mounted) {
      try {
        await context.read<AuthProvider>().logout();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    CloudSyncService? sync;
    try {
      sync = context.watch<CloudSyncService>();
    } catch (_) {}

    final member = auth.scope?.member;
    final orgName = member?.organization ?? 'IntelliGuard Security';
    final userEmail = auth.username ?? member?.userId ?? 'admin@campus.edu';
    final role = member?.role ?? 'Admin';
    final activeGuards = _guards.where((g) => g['active'] == true).length;

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
        title: Text('Account & Admin', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary)),
      ),
      body: RefreshIndicator(
        color: AppColors.accentPrimary,
        backgroundColor: context.bgCard,
        onRefresh: () async {
          if (sync != null) await sync.sync();
          await _loadData();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            // ── Top profile card ─────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: context.bgCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: AppColors.accentPrimary.withValues(alpha: 0.15),
                        child: Text(
                          userEmail.substring(0, 1).toUpperCase(),
                          style: const TextStyle(color: AppColors.accentPrimary, fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(userEmail,
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: context.textPrimary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text(orgName, style: TextStyle(fontSize: 12, color: context.textSecondary)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.accentPrimary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(role.toUpperCase(),
                            style: const TextStyle(fontSize: 10, color: AppColors.accentPrimary, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: context.bgElevated,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(auth.online ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                            size: 14, color: auth.online ? AppColors.online : context.textMuted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            auth.online ? 'Online — Security sync active' : 'Offline — Operating in local secure mode',
                            style: TextStyle(fontSize: 11, color: auth.online ? AppColors.online : context.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Quick Metrics ─────────────────────────────────────────────
            Row(
              children: [
                Expanded(child: _metricCard(context, 'Active Guards', '$activeGuards', Icons.security_rounded, AppColors.online)),
                const SizedBox(width: 10),
                Expanded(child: _metricCard(context, 'Cameras', '${_cameras.length}', Icons.videocam_rounded, AppColors.accentPrimary)),
                const SizedBox(width: 10),
                Expanded(child: _metricCard(context, 'Sync Queue', '${sync?.pendingCount ?? 0}', Icons.sync_rounded, AppColors.warning)),
              ],
            ),

            const SizedBox(height: 20),

            // ── Section 1: Guard & Staff Management ───────────────────────
            _sectionHeader(context, 'CAMPUS GUARDS & PERSONNEL', Icons.shield_rounded, action: auth.isAdmin ? TextButton.icon(
              onPressed: _addGuardDialog,
              icon: const Icon(Icons.person_add_rounded, size: 14, color: AppColors.accentPrimary),
              label: const Text('Add Guard', style: TextStyle(fontSize: 12, color: AppColors.accentPrimary, fontWeight: FontWeight.bold)),
            ) : null),
            const SizedBox(height: 10),

            if (_guards.isEmpty)
              _emptySection(context, 'No security guards added', auth.isAdmin ? 'Tap Add Guard to register guards to your campus.' : 'Contact an administrator to add campus guards.', Icons.person_off_outlined)
            else
              for (final guard in _guards) _guardCard(context, guard, auth.isAdmin),

            const SizedBox(height: 20),

            // ── Section 2: Camera Network Management ─────────────────────
            _sectionHeader(context, 'SURVEILLANCE CAMERAS', Icons.videocam_outlined, action: TextButton.icon(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const CameraManagementScreen())).then((_) => _loadData());
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 14, color: AppColors.accentPrimary),
              label: const Text('Manage Cameras', style: TextStyle(fontSize: 12, color: AppColors.accentPrimary, fontWeight: FontWeight.bold)),
            )),
            const SizedBox(height: 10),

            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.bgCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.borderSubtle),
              ),
              child: Column(
                children: [
                  for (final cam in _cameras.take(3))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.accentPrimary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(cam['id']?.toString() ?? '',
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.accentPrimary)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(cam['name']?.toString() ?? '',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: context.textPrimary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                          Text(cam['location']?.toString() ?? '',
                              style: TextStyle(fontSize: 11, color: context.textMuted),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Divider(color: context.borderSubtle, height: 1),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const CameraManagementScreen())).then((_) => _loadData());
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('View All ${_cameras.length} Cameras',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.accentPrimary)),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_forward_ios_rounded, size: 10, color: AppColors.accentPrimary),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Section 3: Admin Activities & Audit Log ──────────────────
            _sectionHeader(context, 'ADMIN ACTIVITY & AUDIT LOG', Icons.history_rounded),
            const SizedBox(height: 10),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.bgCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.borderSubtle),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < _activities.take(4).length; i++) ...[
                    _activityItem(context, _activities[i]),
                    if (i < _activities.take(4).length - 1)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Divider(color: context.borderSubtle, height: 1),
                      ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Section 4: Synchronization & Maintenance ─────────────────
            _sectionHeader(context, 'SYSTEM & SYNCHRONIZATION', Icons.cloud_done_outlined),
            const SizedBox(height: 10),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.bgCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: (sync?.syncing ?? false)
                              ? AppColors.warning
                              : (sync?.online ?? false)
                                  ? AppColors.online
                                  : context.textMuted,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${sync?.pendingCount ?? 0} events pending sync',
                        style: TextStyle(fontSize: 12, color: context.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _busy || (sync?.syncing ?? false)
                          ? null
                          : () async {
                              if (sync != null) await sync.sync();
                              await _loadData();
                            },
                      icon: (sync?.syncing ?? false)
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : const Icon(Icons.sync_rounded, size: 16),
                      label: Text((sync?.syncing ?? false) ? 'Syncing...' : 'Sync Database Now'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accentPrimary,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // ── Sign Out ──────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () => _confirmLogout(context),
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text('Sign Out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.fire,
                  side: const BorderSide(color: AppColors.fire),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  minimumSize: const Size(double.infinity, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title, IconData icon, {Widget? action}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: AppColors.accentPrimary),
            const SizedBox(width: 8),
            Text(title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: context.textMuted, letterSpacing: 1.2)),
          ],
        ),
        if (action != null) action,
      ],
    );
  }

  Widget _metricCard(BuildContext context, String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.textPrimary)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10, color: context.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _emptySection(BuildContext context, String title, String subtitle, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: context.textMuted),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: context.textPrimary)),
          const SizedBox(height: 4),
          Text(subtitle, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: context.textSecondary)),
        ],
      ),
    );
  }

  Widget _guardCard(BuildContext context, Map<String, dynamic> guard, bool isAdmin) {
    final active = guard['active'] as bool? ?? true;
    final role = guard['role'] as String? ?? 'Guard';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderSubtle),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: active ? AppColors.accentPrimary.withValues(alpha: 0.12) : context.borderDefault,
            child: Text(
              (guard['name'] as String? ?? 'G').substring(0, 1).toUpperCase(),
              style: TextStyle(
                color: active ? AppColors.accentPrimary : context.textMuted,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        guard['name'] as String? ?? 'Guard',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: active ? AppColors.online.withValues(alpha: 0.12) : context.bgElevated,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        active ? 'Active' : 'Inactive',
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: active ? AppColors.online : context.textMuted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(role, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.accentPrimary)),
                    Text('  ·  ${guard['badge'] ?? ''}', style: TextStyle(fontSize: 11, color: context.textMuted)),
                  ],
                ),
                if ((guard['shift'] as String?)?.isNotEmpty ?? false)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(guard['shift'] as String, style: TextStyle(fontSize: 10, color: context.textSecondary)),
                  ),
              ],
            ),
          ),
          if (isAdmin)
            PopupMenuButton<String>(
              color: context.bgElevated,
              icon: Icon(Icons.more_vert_rounded, size: 18, color: context.textMuted),
              onSelected: (action) {
                if (action == 'toggle') _toggleGuardStatus(guard);
                if (action == 'role') _changeGuardRole(guard);
                if (action == 'remove') _removeGuard(guard);
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'role',
                  child: Row(children: [
                    Icon(Icons.edit_outlined, size: 16, color: context.textPrimary),
                    const SizedBox(width: 8),
                    Text('Change Role', style: TextStyle(color: context.textPrimary)),
                  ]),
                ),
                PopupMenuItem(
                  value: 'toggle',
                  child: Row(children: [
                    Icon(active ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded,
                        size: 16, color: active ? AppColors.warning : AppColors.online),
                    const SizedBox(width: 8),
                    Text(active ? 'Set Inactive' : 'Set Active', style: TextStyle(color: context.textPrimary)),
                  ]),
                ),
                const PopupMenuItem(
                  value: 'remove',
                  child: Row(children: [
                    Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.fire),
                    SizedBox(width: 8),
                    Text('Remove Guard', style: TextStyle(color: AppColors.fire)),
                  ]),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _activityItem(BuildContext context, Map<String, dynamic> act) {
    IconData icon = Icons.info_outline_rounded;
    Color color = AppColors.accentPrimary;
    final type = act['type']?.toString() ?? '';
    if (type == 'guard') {
      icon = Icons.person_rounded;
      color = AppColors.online;
    } else if (type == 'camera') {
      icon = Icons.videocam_rounded;
      color = AppColors.accentPrimary;
    } else if (type == 'zone') {
      icon = Icons.shield_rounded;
      color = AppColors.restricted;
    } else if (type == 'ai') {
      icon = Icons.psychology_rounded;
      color = AppColors.warning;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(act['title']?.toString() ?? '',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  Text(act['time']?.toString() ?? '', style: TextStyle(fontSize: 10, color: context.textMuted)),
                ],
              ),
              const SizedBox(height: 2),
              Text(act['details']?.toString() ?? '', style: TextStyle(fontSize: 11, color: context.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}
