// ============================================================
// restricted_zones_screen.dart — Camera zone management
// Professional redesign: clean zone cards with time ranges,
// status indicators and consistent button styling.
// ============================================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/zone.dart';
import '../providers/auth_provider.dart';
import '../services/cloud_api.dart';
import '../services/local_db_service.dart';
import '../theme/app_theme.dart';

class RestrictedZonesScreen extends StatefulWidget {
  const RestrictedZonesScreen({super.key});
  @override
  State<RestrictedZonesScreen> createState() => _RestrictedZonesScreenState();
}

class _RestrictedZonesScreenState extends State<RestrictedZonesScreen> {
  List<Zone> _zones = [];
  List<Map<String, dynamic>> _cameras = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    LocalDbService.referenceRevision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    LocalDbService.referenceRevision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final scope = LocalDbService.requireScope();
      final zones = await LocalDbService.getZones(scope: scope);
      final cameras = await LocalDbService.getCameras(scope: scope);
      if (mounted) {
        setState(() {
          _zones = zones.map(Zone.fromJson).toList();
          _cameras = cameras;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyCloudError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([Zone? existing]) async {
    if (!context.read<AuthProvider>().isAdmin) return;
    if (_cameras.isEmpty) {
      setState(() => _error = 'Add a camera record in Account first.');
      return;
    }
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ZoneEditor(existing: existing, cameras: _cameras),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _delete(Zone zone) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Delete Zone', style: TextStyle(color: ctx.textPrimary, fontWeight: FontWeight.bold)),
        content: Text('Remove ${zone.name}? Saved events remain.',
            style: TextStyle(color: ctx.textSecondary, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.fire,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await LocalDbService.deleteZone(zone.id);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyCloudError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AuthProvider>().isAdmin;
    return Scaffold(
      backgroundColor: context.bgPrimary,
      appBar: AppBar(
        backgroundColor: context.bgCard,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(Icons.arrow_back_ios_rounded, size: 18, color: context.textPrimary),
        ),
        title: Text('Restricted Zones',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary)),
        actions: [
          if (admin)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ElevatedButton.icon(
                onPressed: _edit,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add Zone'),
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
      body: RefreshIndicator(
        color: AppColors.accentPrimary,
        backgroundColor: context.bgCard,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [

              if (_loading) const LinearProgressIndicator(color: AppColors.accentPrimary),

              if (_error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.fire.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.fire.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline_rounded, color: AppColors.fire, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.fire, fontSize: 12))),
                  ]),
                ),

              if (!_loading && _zones.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.shield_outlined, size: 48, color: context.textMuted.withValues(alpha: 0.4)),
                      const SizedBox(height: 14),
                      Text('No zones configured', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: context.textSecondary)),
                      const SizedBox(height: 6),
                      Text('Person alerts need an active zone\nfor the selected camera.',
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: context.textMuted)),
                    ]),
                  ),
                ),

              for (final zone in _zones) _ZoneCard(zone: zone, admin: admin, onEdit: () => _edit(zone), onDelete: () => _delete(zone)),
            ],
          ),
        ),
    );
  }
}

// ── Zone card ─────────────────────────────────────────────────────────────────

class _ZoneCard extends StatelessWidget {
  final Zone zone;
  final bool admin;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _ZoneCard({required this.zone, required this.admin, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isActive = zone.status == 'Active';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isActive ? AppColors.accentPrimary.withValues(alpha: 0.25) : context.borderSubtle),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Card header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: (isActive ? AppColors.restricted : context.textMuted).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(Icons.shield_rounded, size: 18, color: isActive ? AppColors.restricted : context.textMuted),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(zone.name,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: context.textPrimary),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Row(children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: isActive ? AppColors.online : AppColors.textMuted,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(zone.status, style: TextStyle(fontSize: 10, color: isActive ? AppColors.online : AppColors.textMuted, fontWeight: FontWeight.w500)),
                ]),
              ]),
            ),
            if (admin)
              PopupMenuButton<String>(
                color: context.bgCard,
                icon: Icon(Icons.more_vert_rounded, size: 18, color: context.textMuted),
                onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(children: [
                      Icon(Icons.edit_outlined, size: 16, color: ctx.textPrimary),
                      const SizedBox(width: 8),
                      Text('Edit', style: TextStyle(color: ctx.textPrimary)),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      const Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.fire),
                      const SizedBox(width: 8),
                      const Text('Delete', style: TextStyle(color: AppColors.fire)),
                    ]),
                  ),
                ],
              ),
          ]),
        ),

        // Divider
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Divider(color: context.borderSubtle, height: 1),
        ),

        // Details
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _detailRow(context, Icons.videocam_outlined, zone.cameras.join(', ')),
            const SizedBox(height: 6),
            _detailRow(context, Icons.access_time_rounded, zone.timeRangeLabel),
          ]),
        ),
      ]),
    );
  }

  Widget _detailRow(BuildContext context, IconData icon, String text) => Row(children: [
    Icon(icon, size: 13, color: context.textMuted),
    const SizedBox(width: 7),
    Expanded(child: Text(text, style: TextStyle(fontSize: 11, color: context.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis)),
  ]);
}

// ── Zone editor bottom sheet ──────────────────────────────────────────────────

class _ZoneEditor extends StatefulWidget {
  final Zone? existing;
  final List<Map<String, dynamic>> cameras;
  const _ZoneEditor({this.existing, required this.cameras});
  @override
  State<_ZoneEditor> createState() => _ZoneEditorState();
}

class _ZoneEditorState extends State<_ZoneEditor> {
  late final TextEditingController _name;
  late final String _id;
  late Set<String> _selected;
  late int _start;
  late int _end;
  late String _status;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final z = widget.existing;
    _id = z?.id ?? const Uuid().v4();
    _name = TextEditingController(text: z?.name ?? '');
    _selected = (z?.cameras ?? <String>[]).toSet();
    _start = z?.startHour ?? 0;
    _end = z?.endHour ?? 0;
    _status = z?.status ?? 'Active';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _selected.isEmpty) {
      setState(() => _error = 'Enter a name and select at least one camera.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await LocalDbService.saveZone(
        id: _id,
        name: _name.text,
        cameras: _selected.toList(),
        startHour: _start,
        endHour: _end,
        status: _status,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyCloudError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text(widget.existing == null ? 'Add Zone' : 'Edit Zone',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary)),
            ),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(Icons.close_rounded, color: context.textMuted),
            ),
          ]),
          const SizedBox(height: 20),

          // Zone name
          TextField(
            controller: _name,
            enabled: !_busy,
            maxLength: 120,
            style: TextStyle(color: context.textPrimary),
            decoration: InputDecoration(
              labelText: 'Zone Name',
              labelStyle: TextStyle(color: context.textSecondary),
              filled: true,
              fillColor: context.bgElevated,
              counterText: '',
              prefixIcon: Icon(Icons.edit_rounded, size: 16, color: context.textMuted),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: context.borderDefault)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: context.borderDefault)),
            ),
          ),
          const SizedBox(height: 20),

          // Camera selection
          Text('Cameras', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.textSecondary, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          for (final camera in widget.cameras)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: _selected.contains(camera['id']) ? AppColors.accentPrimary.withValues(alpha: 0.08) : context.bgElevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _selected.contains(camera['id']) ? AppColors.accentPrimary.withValues(alpha: 0.4) : context.borderDefault,
                ),
              ),
              child: CheckboxListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                title: Text('${camera['id']}', style: AppTheme.mono(size: 11, color: AppColors.accentPrimary)),
                subtitle: Text('${camera['name']}', style: TextStyle(fontSize: 12, color: context.textSecondary)),
                value: _selected.contains(camera['id']),
                activeColor: AppColors.accentPrimary,
                checkColor: Colors.black,
                onChanged: _busy ? null : (v) => setState(() {
                  if (v == true) { _selected.add(camera['id'] as String); }
                  else { _selected.remove(camera['id']); }
                }),
                dense: true,
                controlAffinity: ListTileControlAffinity.trailing,
              ),
            ),

          const SizedBox(height: 16),

          // Monitoring hours
          Text('Monitoring Hours', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.textSecondary, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text('Same start/end = all day', style: TextStyle(fontSize: 10, color: context.textMuted)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _start,
                dropdownColor: context.bgElevated,
                style: TextStyle(color: context.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Start',
                  labelStyle: TextStyle(color: context.textSecondary, fontSize: 12),
                  filled: true,
                  fillColor: context.bgElevated,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: context.borderDefault)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: context.borderDefault)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                items: List.generate(24, (i) => DropdownMenuItem(value: i, child: Text(Zone.hour12Label(i)))),
                onChanged: _busy ? null : (v) => setState(() => _start = v!),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _end,
                dropdownColor: context.bgElevated,
                style: TextStyle(color: context.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'End',
                  labelStyle: TextStyle(color: context.textSecondary, fontSize: 12),
                  filled: true,
                  fillColor: context.bgElevated,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: context.borderDefault)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: context.borderDefault)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                items: List.generate(24, (i) => DropdownMenuItem(value: i, child: Text(Zone.hour12Label(i)))),
                onChanged: _busy ? null : (v) => setState(() => _end = v!),
              ),
            ),
          ]),

          const SizedBox(height: 16),

          // Active toggle
          Container(
            decoration: BoxDecoration(
              color: context.bgElevated,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.borderDefault),
            ),
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              title: Text('Active Zone', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.textPrimary)),
              subtitle: Text(_status == 'Active' ? 'Monitoring is enabled' : 'Monitoring is disabled',
                  style: TextStyle(fontSize: 11, color: _status == 'Active' ? AppColors.online : context.textMuted)),
              value: _status == 'Active',
              activeThumbColor: AppColors.accentPrimary,
              onChanged: _busy ? null : (v) => setState(() => _status = v ? 'Active' : 'Inactive'),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.fire.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.fire.withValues(alpha: 0.3)),
              ),
              child: Text(_error!, style: const TextStyle(color: AppColors.fire, fontSize: 12)),
            ),
          ],

          const SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _busy ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentPrimary,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              child: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : Text(widget.existing == null ? 'Create Zone' : 'Save Changes'),
            ),
          ),
        ]),
      ),
    );
  }
}
