import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/local/local_storage_service.dart';
import '../../../data/models/monthly_summary_model.dart';
import '../../../data/repositories/firestore_repository.dart';

class MonthlyCard extends StatefulWidget {
  final String userId;
  final String monthKey; // 'YYYY-MM'

  const MonthlyCard({
    super.key,
    required this.userId,
    required this.monthKey,
  });

  @override
  State<MonthlyCard> createState() => _MonthlyCardState();
}

class _MonthlyCardState extends State<MonthlyCard> {
  final _repo = FirestoreRepository();
  MonthlySummaryModel? _summary;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return widget.monthKey ==
        '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Current month is always recomputed (data still changing).
      // Past months: check local cache → Firestore → compute fresh.
      if (!_isCurrentMonth) {
        final cached = LocalStorageService.getMonthlySummary(
            widget.userId, widget.monthKey);
        if (cached != null) {
          if (mounted) setState(() { _summary = cached; _loading = false; });
          return;
        }

        final fromDb =
            await _repo.getMonthlySummary(widget.userId, widget.monthKey);
        if (fromDb != null) {
          await LocalStorageService.saveMonthlySummary(
              widget.userId, widget.monthKey, fromDb);
          if (mounted) setState(() { _summary = fromDb; _loading = false; });
          return;
        }
      }

      // Not in cache/Firestore (or current month) — compute from raw data.
      final summary = await _compute();
      await _repo.saveMonthlySummary(widget.userId, summary);
      if (!_isCurrentMonth) {
        await LocalStorageService.saveMonthlySummary(
            widget.userId, widget.monthKey, summary);
      }
      if (mounted) setState(() { _summary = summary; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<MonthlySummaryModel> _compute() async {
    final attendance =
        await _repo.getAttendanceForMonth(widget.userId, widget.monthKey);

    final monthStart = DateTime.parse('${widget.monthKey}-01');
    final monthEnd =
        DateTime(monthStart.year, monthStart.month + 1, 1);
    final visits = await _repo.getVisitsByDateRange(
        widget.userId, monthStart, monthEnd);

    int punchCount = 0;
    int totalMinutes = 0;
    double totalDistance = 0;
    for (final att in attendance) {
      if (att.isPunchedIn) punchCount++;
      totalMinutes += att.attendanceDuration.inMinutes;
      totalDistance += att.distance;
    }

    final totalExpense =
        visits.fold<double>(0, (s, v) => s + (v.expenseAmount ?? 0));

    return MonthlySummaryModel(
      monthKey: widget.monthKey,
      punchCount: punchCount,
      totalHours: totalMinutes ~/ 60,
      totalMinutes: totalMinutes % 60,
      totalDistanceKm: totalDistance.round(),
      totalVisits: visits.length,
      totalExpense: totalExpense.round(),
      computedAt: DateTime.now(),
    );
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
                  if (_isCurrentMonth) ...[
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
