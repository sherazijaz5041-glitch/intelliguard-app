// ============================================================
// reports_screen.dart — Analytics & PDF export
// Professional redesign: clean summary cards, bar chart,
// top cameras, and a properly formatted PDF report.
// ============================================================
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../models/app_event.dart';
import '../providers/alerts_provider.dart';
import '../theme/app_theme.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  bool _exporting = false;

  // Date range filter
  String _range = '7D'; // 7D | 30D | 90D | Custom
  DateTime? _customFrom;
  DateTime? _customTo;

  List<dynamic> _filterByRange(List<dynamic> alerts) {
    final now = DateTime.now();
    DateTime? from;
    if (_range == '7D') from = now.subtract(const Duration(days: 7));
    else if (_range == '30D') from = now.subtract(const Duration(days: 30));
    else if (_range == '90D') from = now.subtract(const Duration(days: 90));
    else if (_range == 'Custom' && _customFrom != null) {
      from = _customFrom!;
    }
    if (from == null) return alerts;
    final to = (_range == 'Custom' && _customTo != null)
        ? _customTo!.add(const Duration(days: 1))
        : now.add(const Duration(days: 1));
    return alerts.where((a) {
      final t = DateTime.tryParse(a.time.replaceFirst(' ', 'T'));
      if (t == null) return false; // exclude events with unparseable timestamps
      return t.isAfter(from!) && t.isBefore(to);
    }).toList();
  }

  Future<void> _pickCustomRange(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: _customFrom != null && _customTo != null
          ? DateTimeRange(start: _customFrom!, end: _customTo!)
          : null,
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.accentPrimary,
            onPrimary: Colors.black,
            surface: AppColors.bgCard,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _customFrom = picked.start;
        _customTo = picked.end;
        _range = 'Custom';
      });
    }
  }

  Map<String, dynamic> _normalizedSummary(List<dynamic> alerts) {
    // Use normalizeEventType from app_event.dart — single source of truth.
    final normalizedByType = {'Fire': 0, 'Smoke': 0, 'Restricted Zone': 0, 'Violence': 0};
    final byStatus = <String, int>{};
    for (final a in alerts) {
      final nk = normalizeEventType(a.type as String?);
      if (normalizedByType.containsKey(nk)) {
        normalizedByType[nk] = (normalizedByType[nk] ?? 0) + 1;
      }
      byStatus[a.status as String] = (byStatus[a.status as String] ?? 0) + 1;
    }

    final totalEvents = normalizedByType.values.fold<int>(0, (a, b) => a + b);
    final detected = byStatus['Detected'] ?? 0;
    final inProgress = byStatus['In Progress'] ?? 0;
    final resolved = byStatus['Resolved'] ?? 0;

    String topType = 'N/A';
    var maxCount = 0;
    normalizedByType.forEach((k, v) {
      if (v > maxCount) { maxCount = v; topType = k; }
    });

    return {
      'totalEvents': totalEvents,
      'byType': normalizedByType,
      'activeCount': detected + inProgress,
      'resolvedCount': resolved,
      'topType': topType,
    };
  }

  // ── PDF generation ──────────────────────────────────────────────────────────

  Future<void> _exportPdf(List<dynamic> alerts) async {
    setState(() => _exporting = true);
    try {
      final doc = pw.Document();
      final now = DateTime.now();
      final dateStr = '${now.day.toString().padLeft(2, '0')}/'
          '${now.month.toString().padLeft(2, '0')}/${now.year}';
      final timeStr = '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}';

      // Build summary counts for PDF
      final Map<String, int> byType = {};
      final Map<String, int> byStatus = {};
      for (final a in alerts) {
        byType[a.type] = (byType[a.type] ?? 0) + 1;
        byStatus[a.status] = (byStatus[a.status] ?? 0) + 1;
      }

      const headerBg = PdfColor.fromInt(0xFF0F1629);
      const accentColor = PdfColor.fromInt(0xFF00C8E8);
      const darkText = PdfColor.fromInt(0xFF1A2035);
      const mutedText = PdfColor.fromInt(0xFF6B7280);
      const rowAlt = PdfColor.fromInt(0xFFF8FAFC);
      const borderColor = PdfColor.fromInt(0xFFE2E8F0);

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 32),
          header: (context) => pw.Column(children: [
            // Top banner
            pw.Container(
              decoration: const pw.BoxDecoration(color: headerBg),
              padding: const pw.EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text('INTELLIGUARD',
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                          letterSpacing: 1.5,
                        )),
                    pw.SizedBox(height: 2),
                    pw.Text('Security Event Report',
                        style: const pw.TextStyle(fontSize: 10, color: accentColor)),
                  ]),
                  pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                    pw.Text('Generated: $dateStr at $timeStr',
                        style: pw.TextStyle(fontSize: 9, color: PdfColors.grey300)),
                    pw.Text('Total records: ${alerts.length}',
                        style: pw.TextStyle(fontSize: 9, color: PdfColors.grey300)),
                  ]),
                ],
              ),
            ),
            pw.SizedBox(height: 12),
          ]),
          footer: (context) => pw.Padding(
            padding: const pw.EdgeInsets.only(top: 10),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('IntelliGuard Security System  |  Confidential',
                    style: const pw.TextStyle(fontSize: 8, color: mutedText)),
                pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
                    style: const pw.TextStyle(fontSize: 8, color: mutedText)),
              ],
            ),
          ),
          build: (context) => [
            // Summary section
            pw.Text('Summary', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: darkText)),
            pw.SizedBox(height: 8),
            pw.Row(children: [
              _pdfSummaryBox('Total Events', '${alerts.length}', accentColor),
              pw.SizedBox(width: 8),
              _pdfSummaryBox('Active', '${(byStatus['Detected'] ?? 0) + (byStatus['In Progress'] ?? 0)}', const PdfColor.fromInt(0xFFFFB800)),
              pw.SizedBox(width: 8),
              _pdfSummaryBox('Resolved', '${byStatus['Resolved'] ?? 0}', const PdfColor.fromInt(0xFF00C47A)),
            ]),
            pw.SizedBox(height: 20),

            // Event breakdown
            pw.Text('Event Breakdown by Type',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: darkText)),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: borderColor, width: 0.5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: headerBg),
                  children: [
                    _pdfCell('Type', isHeader: true),
                    _pdfCell('Count', isHeader: true),
                    _pdfCell('Proportion', isHeader: true),
                  ],
                ),
                ...byType.entries.map((e) {
                  final pct = alerts.isEmpty ? 0.0 : (e.value / alerts.length * 100);
                  return pw.TableRow(children: [
                    _pdfCell(e.key),
                    _pdfCell('${e.value}'),
                    _pdfCell('${pct.toStringAsFixed(1)}%'),
                  ]);
                }),
              ],
            ),
            pw.SizedBox(height: 20),

            // Divider
            pw.Divider(color: borderColor, thickness: 0.5),
            pw.SizedBox(height: 4),

            // Event log table
            pw.Text('Detailed Event Log',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: darkText)),
            pw.SizedBox(height: 6),
            pw.Table(
              columnWidths: {
                0: const pw.FlexColumnWidth(2),
                1: const pw.FlexColumnWidth(1.2),
                2: const pw.FlexColumnWidth(2),
                3: const pw.FlexColumnWidth(2),
                4: const pw.FlexColumnWidth(1.3),
                5: const pw.FlexColumnWidth(1),
              },
              border: pw.TableBorder.all(color: borderColor, width: 0.5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: headerBg),
                  children: [
                    _pdfCell('Event Type', isHeader: true),
                    _pdfCell('Camera', isHeader: true),
                    _pdfCell('Location', isHeader: true),
                    _pdfCell('Timestamp', isHeader: true),
                    _pdfCell('Status', isHeader: true),
                    _pdfCell('Conf.', isHeader: true),
                  ],
                ),
                ...alerts.take(200).toList().asMap().entries.map((entry) {
                  final i = entry.key;
                  final a = entry.value;
                  final conf = (a.confidence * 100).toStringAsFixed(0);
                  return pw.TableRow(
                    decoration: i.isOdd ? const pw.BoxDecoration(color: rowAlt) : null,
                    children: [
                      _pdfCell(a.type, small: true),
                      _pdfCell(a.cameraId, small: true),
                      _pdfCell(a.location, small: true),
                      _pdfCell(a.time.toString(), small: true),
                      _pdfCell(a.status, small: true),
                      _pdfCell('$conf%', small: true),
                    ],
                  );
                }),
              ],
            ),
          ],
        ),
      );

      await Printing.sharePdf(
        bytes: await doc.save(),
        filename: 'intelliguard-report-${now.millisecondsSinceEpoch}.pdf',
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  pw.Widget _pdfSummaryBox(String label, String value, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          border: pw.Border.all(color: const PdfColor.fromInt(0xFFE2E8F0), width: 0.5),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(value, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: color)),
          pw.SizedBox(height: 2),
          pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: PdfColor.fromInt(0xFF6B7280))),
        ]),
      ),
    );
  }

  pw.Widget _pdfCell(String text, {bool isHeader = false, bool small = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 9 : (small ? 8 : 9),
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: isHeader ? PdfColors.white : const PdfColor.fromInt(0xFF1A2035),
        ),
      ),
    );
  }

  // ── Flutter UI ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final alertsProvider = context.watch<AlertsProvider>();
    final allAlerts = alertsProvider.alerts;
    final alerts = _filterByRange(allAlerts);

    if (alertsProvider.loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.accentPrimary),
        ),
      );
    }

    // Compute summary locally — never mutate state inside build().
    final summary = _normalizedSummary(alerts);
    final byType = summary['byType'] as Map<String, int>;

    final Map<String, int> cameraCounts = {};
    for (final a in alerts) {
      cameraCounts[a.cameraId] = (cameraCounts[a.cameraId] ?? 0) + 1;
    }
    final topCameras = cameraCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final displayCameras = topCameras.take(4).toList();
    final maxCamCount = displayCameras.isNotEmpty ? displayCameras.first.value : 1;

    return Scaffold(
      backgroundColor: context.bgPrimary,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.accentPrimary,
          backgroundColor: context.bgCard,
          onRefresh: () async => await alertsProvider.fetchLatestEvents(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('ANALYTICS', style: TextStyle(fontSize: 10, color: AppColors.accentPrimary, letterSpacing: 2, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('Reports', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: context.textPrimary)),
                  ]),
                  ElevatedButton.icon(
                    onPressed: _exporting ? null : () => _exportPdf(alerts),
                    icon: _exporting
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : const Icon(Icons.picture_as_pdf_rounded, size: 16),
                    label: Text(_exporting ? 'Generating…' : alerts.length > 200 ? 'Export PDF (first 200)' : 'Export PDF'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accentPrimary,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Date range filter ─────────────────────────────────────────
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final r in ['7D', '30D', '90D'])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => setState(() => _range = r),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: _range == r ? AppColors.accentPrimary : context.bgCard,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _range == r ? AppColors.accentPrimary : context.borderDefault,
                                width: _range == r ? 0 : 1,
                              ),
                            ),
                            child: Text(r,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: _range == r ? Colors.black : context.textSecondary)),
                          ),
                        ),
                      ),
                    GestureDetector(
                      onTap: () => _pickCustomRange(context),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: _range == 'Custom' ? AppColors.accentPrimary : context.bgCard,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _range == 'Custom' ? AppColors.accentPrimary : context.borderDefault,
                          ),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.calendar_today_rounded,
                              size: 12,
                              color: _range == 'Custom' ? Colors.black : context.textSecondary),
                          const SizedBox(width: 6),
                          Text(
                            _range == 'Custom' && _customFrom != null
                                ? '${_customFrom!.day}/${_customFrom!.month} – ${_customTo?.day ?? '?'}/${_customTo?.month ?? '?'}'
                                : 'Custom',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _range == 'Custom' ? Colors.black : context.textSecondary),
                          ),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${alerts.length} events in selected range',
                style: TextStyle(fontSize: 11, color: context.textMuted),
              ),
              const SizedBox(height: 20),
              Row(children: [
                _summaryCard(context, 'Total Events', '${summary['totalEvents']}', AppColors.accentPrimary, Icons.analytics_rounded),
                const SizedBox(width: 12),
                _summaryCard(context, 'Active', '${summary['activeCount']}', AppColors.warning, Icons.warning_amber_rounded),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                _summaryCard(context, 'Resolved', '${summary['resolvedCount']}', AppColors.online, Icons.check_circle_rounded),
                const SizedBox(width: 12),
                _summaryCard(context, 'Top Threat', '${summary['topType']}', AppColors.fire, Icons.local_fire_department_rounded, isText: true),
              ]),

              const SizedBox(height: 24),

              // Bar chart
              _sectionHeader(context, 'Threat Distribution'),
              const SizedBox(height: 12),
              Container(
                height: 200,
                padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                decoration: BoxDecoration(
                  color: context.bgCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.borderSubtle),
                ),
                child: byType.values.every((v) => v == 0)
                    ? Center(child: Text('No event data yet', style: TextStyle(color: context.textMuted, fontSize: 13)))
                    : BarChart(
                        BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          maxY: (byType.values.reduce((a, b) => a > b ? a : b) * 1.35).clamp(1, double.infinity).toDouble(),
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            getDrawingHorizontalLine: (_) => FlLine(color: context.borderSubtle, strokeWidth: 1, dashArray: [4, 4]),
                          ),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 28,
                                getTitlesWidget: (v, _) => Text(v.toInt().toString(),
                                    style: TextStyle(color: context.textMuted, fontSize: 10)),
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (v, _) {
                                  final keys = byType.keys.toList();
                                  final i = v.toInt();
                                  if (i < 0 || i >= keys.length) return const SizedBox.shrink();
                                  final label = keys[i] == 'Restricted Zone' ? 'Zone' : keys[i];
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(label, style: TextStyle(color: context.textMuted, fontSize: 10)),
                                  );
                                },
                              ),
                            ),
                          ),
                          barGroups: byType.entries.toIndexed().map((e) {
                            final color = _typeColor(e.$2.key);
                            return BarChartGroupData(x: e.$1, barRods: [
                              BarChartRodData(
                                toY: e.$2.value.toDouble(),
                                color: color,
                                width: 24,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                              ),
                            ]);
                          }).toList(),
                        ),
                      ),
              ),

              const SizedBox(height: 24),

              // Top cameras
              _sectionHeader(context, 'Top Cameras by Alerts'),
              const SizedBox(height: 12),
              if (displayCameras.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: context.bgCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: context.borderSubtle),
                  ),
                  child: Center(
                    child: Text('No camera activity yet', style: TextStyle(color: context.textMuted, fontSize: 13)),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.bgCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: context.borderSubtle),
                  ),
                  child: Column(
                    children: displayCameras.asMap().entries.map((entry) {
                      final i = entry.key;
                      final c = entry.value;
                      final pct = maxCamCount > 0 ? (c.value / maxCamCount) : 0.0;
                      return Padding(
                        padding: EdgeInsets.only(bottom: i < displayCameras.length - 1 ? 16 : 0),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text(c.key, style: AppTheme.mono(size: 11, color: context.textPrimary, weight: FontWeight.w600)),
                            Text('${c.value} alert${c.value == 1 ? '' : 's'}',
                                style: TextStyle(fontSize: 11, color: context.textMuted)),
                          ]),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: pct,
                              minHeight: 6,
                              backgroundColor: context.bgElevated,
                              color: AppColors.accentPrimary,
                            ),
                          ),
                        ]),
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) => Text(title,
      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: context.textPrimary, letterSpacing: 0.2));

  Widget _summaryCard(BuildContext context, String label, String value, Color color, IconData icon, {bool isText = false}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.borderSubtle),
        ),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value,
                  style: TextStyle(
                      color: color,
                      fontSize: isText ? 12 : 20,
                      fontWeight: FontWeight.bold,
                      height: 1.1),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 10, color: context.textSecondary, fontWeight: FontWeight.w500)),
            ]),
          ),
        ]),
      ),
    );
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'Fire': return AppColors.fire;
      case 'Smoke': return AppColors.smoke;
      case 'Restricted Zone': return AppColors.restricted;
      case 'Violence': return AppColors.violence;
      default: return AppColors.accentPrimary;
    }
  }
}

extension _IndexedIterable<E> on Iterable<E> {
  Iterable<(int, E)> toIndexed() sync* {
    var i = 0;
    for (final e in this) { yield (i, e); i++; }
  }
}
