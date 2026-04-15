import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/data_manager.dart';
import '../../../data/models/monthly_summary_model.dart';

class MonthlyCard extends StatefulWidget {
  final String userId;
  final String monthKey; // 'YYYY-MM'
  /// Pre-loaded by the parent tab. For past months this avoids a second
  /// Firestore round-trip; for the current month a background refresh still runs.
  final MonthlySummaryModel? initialSummary;

  const MonthlyCard({
    super.key,
    required this.userId,
    required this.monthKey,
    this.initialSummary,
  });

  @override
  State<MonthlyCard> createState() => _MonthlyCardState();
}

class _MonthlyCardState extends State<MonthlyCard> {
  MonthlySummaryModel? _summary;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Show pre-loaded summary immediately (no blank card on first render).
    if (widget.initialSummary != null) {
      _summary = widget.initialSummary;
    }
    _load();
  }

  Future<void> _load() async {
    final isCurrentMonth = widget.monthKey == DataManager.currentMonthKey;

    // Past months are sealed — the initialSummary is already the final value.
    if (!isCurrentMonth && _summary != null) {
      setState(() => _loading = false);
      return;
    }

    setState(() { _loading = true; _error = null; });

    // Current month: refresh in background so live data is always shown.
    try {
      final fresh = await DataManager.getMonthlySummary(
          widget.userId, widget.monthKey);
      if (mounted) setState(() { _summary = fresh; _loading = false; });
    } catch (e) {
      if (mounted) setState(() {
        _loading = false;
        if (_summary == null) _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = DateFormat('MMMM yyyy')
        .format(DateTime.parse('${widget.monthKey}-01'));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(label,
                        style: AppTheme.sora(13,
                            weight: FontWeight.w700,
                            color: AppTheme.primary)),
                  ),
                  if (widget.monthKey == DataManager.currentMonthKey) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('Current',
                          style: AppTheme.sora(10,
                              weight: FontWeight.w600,
                              color: AppTheme.accent)),
                    ),
                  ],
                  const Spacer(),
                  if (_loading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.primary),
                    ),
                ],
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Text('Failed to load',
                    style: AppTheme.sora(12, color: AppTheme.error)),
              ] else if (_summary != null) ...[
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 14),
                // Row 1: punch count, hours, distance
                Row(
                  children: [
                    _stat(Icons.fingerprint_rounded, 'Days In',
                        '${_summary!.punchCount}'),
                    _stat(Icons.access_time_rounded, 'Hours',
                        '${_summary!.totalHours}h ${_summary!.totalMinutes}m'),
                    _stat(Icons.route_rounded, 'Distance',
                        '${_summary!.totalDistanceKm} km'),
                  ],
                ),
                const SizedBox(height: 14),
                // Row 2: visits, expense
                Row(
                  children: [
                    _stat(Icons.storefront_rounded, 'Visits',
                        '${_summary!.totalVisits}'),
                    _stat(Icons.receipt_rounded, 'Expense',
                        '₹${_summary!.totalExpense}'),
                    const Expanded(child: SizedBox()),
                  ],
                ),
              ] else if (!_loading) ...[
                const SizedBox(height: 12),
                Text('No data',
                    style:
                        AppTheme.sora(12, color: AppTheme.textSecondary)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(IconData icon, String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: AppTheme.textHint),
              const SizedBox(width: 4),
              Text(label,
                  style: AppTheme.sora(10, color: AppTheme.textSecondary)),
            ],
          ),
          const SizedBox(height: 3),
          Text(value,
              style:
                  AppTheme.sora(15, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}
