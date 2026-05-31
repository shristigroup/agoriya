import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/csv_export_service.dart';

class ExportBottomSheet extends StatefulWidget {
  final List<CsvMemberRef> members;

  const ExportBottomSheet({super.key, required this.members});

  @override
  State<ExportBottomSheet> createState() => _ExportBottomSheetState();
}

class _ExportBottomSheetState extends State<ExportBottomSheet> {
  late DateTime _selectedMonth;
  bool _loading = false;

  static final _monthFmt = DateFormat('MMMM yyyy');

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
  }

  bool get _canGoForward {
    final now = DateTime.now();
    return _selectedMonth.year < now.year ||
        (_selectedMonth.year == now.year && _selectedMonth.month < now.month);
  }

  void _prevMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    });
  }

  void _nextMonth() {
    if (!_canGoForward) return;
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    });
  }

  Future<void> _export() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final monthKey = DateFormat('yyyy-MM').format(_selectedMonth);
      await CsvExportService.exportMonthlyReport(widget.members, monthKey);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Could not generate export. Please try again.'),
        backgroundColor: AppTheme.error,
      ));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            Text('Export Team Report',
                style: AppTheme.sora(18, weight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              'Download a day-wise CSV of punch times and distance for all ${widget.members.length} members.',
              style: AppTheme.sora(13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 24),

            // Month selector
            Text('Month', style: AppTheme.sora(12, color: AppTheme.textHint, weight: FontWeight.w600)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.divider),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    color: AppTheme.textSecondary,
                    onPressed: _prevMonth,
                  ),
                  Expanded(
                    child: Text(
                      _monthFmt.format(_selectedMonth),
                      textAlign: TextAlign.center,
                      style: AppTheme.sora(15, weight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    color: _canGoForward ? AppTheme.textSecondary : AppTheme.textHint,
                    onPressed: _canGoForward ? _nextMonth : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Export button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                onPressed: _loading ? null : _export,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.download_outlined, size: 20),
                label: Text(
                  _loading ? 'Generating…' : 'Export CSV',
                  style: AppTheme.sora(15, weight: FontWeight.w600, color: Colors.white),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
