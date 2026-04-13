import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/attendance_model.dart';
import '../../../data/models/monthly_summary_model.dart';
import '../../../data/data_manager.dart';
import '../widgets/daily_tile.dart';
import '../widgets/monthly_card.dart';
import 'history_day_screen.dart';

class HistoryScreen extends StatefulWidget {
  final String userId;
  final String? userName; // non-null when a manager is viewing a report

  const HistoryScreen({super.key, required this.userId, this.userName});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title =
        widget.userName != null ? '${widget.userName}\'s History' : 'History';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: Text(title,
            style: AppTheme.sora(20, weight: FontWeight.w700, color: Colors.white)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.accent,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: AppTheme.sora(14, weight: FontWeight.w600),
          unselectedLabelStyle: AppTheme.sora(14),
          tabs: const [Tab(text: 'Daily'), Tab(text: 'Monthly')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _DailyTab(userId: widget.userId, userName: widget.userName),
          _MonthlyTab(userId: widget.userId),
        ],
      ),
    );
  }
}

// ─── Daily Tab ────────────────────────────────────────────────────────────────

class _DailyTab extends StatefulWidget {
  final String userId;
  final String? userName;
  const _DailyTab({required this.userId, this.userName});

  @override
  State<_DailyTab> createState() => _DailyTabState();
}

class _DailyTabState extends State<_DailyTab>
    with AutomaticKeepAliveClientMixin {
  final List<AttendanceModel> _records = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _lastDate; // pagination cursor
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  Future<void> _loadPage({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _records.clear();
        _lastDate = null;
        _hasMore = true;
        _loading = true;
        _error = null;
      });
    }

    try {
      final (records, lastDate) = await DataManager.getAttendanceHistory(
        widget.userId,
        limit: 30,
        startAfterDate: refresh ? null : _lastDate,
      );

      if (mounted) {
        setState(() {
          _records.addAll(records);
          _lastDate = lastDate;
          _hasMore = lastDate != null;
          _loading = false;
          _loadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    await _loadPage();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppTheme.error),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: AppTheme.sora(13, color: AppTheme.textSecondary)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _loadPage(refresh: true),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_records.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_today_rounded,
                size: 56, color: AppTheme.textHint),
            const SizedBox(height: 16),
            Text('No attendance records yet',
                style: AppTheme.sora(15, color: AppTheme.textSecondary)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadPage(refresh: true),
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        itemCount: _records.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == _records.length) {
            // "Load more" footer
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: _loadingMore
                    ? const CircularProgressIndicator(color: AppTheme.primary)
                    : TextButton.icon(
                        onPressed: _loadMore,
                        icon: const Icon(Icons.expand_more),
                        label: const Text('Load more'),
                      ),
              ),
            );
          }
          final record = _records[i];
          return DailyTile(
            attendance: record,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => HistoryDayScreen(
                userId: widget.userId,
                userName: widget.userName,
                attendance: record,
              ),
            )),
          );
        },
      ),
    );
  }
}

// ─── Monthly Tab ──────────────────────────────────────────────────────────────

class _MonthlyTab extends StatefulWidget {
  final String userId;
  const _MonthlyTab({required this.userId});

  @override
  State<_MonthlyTab> createState() => _MonthlyTabState();
}

class _MonthlyTabState extends State<_MonthlyTab>
    with AutomaticKeepAliveClientMixin {
  // Months that have at least one attendance record, newest first.
  List<({String monthKey, MonthlySummaryModel summary})> _activeMonths = [];
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Phase 1: show whatever is already in Hive immediately — no spinner.
    _activeMonths = DataManager.getCachedActiveMonths(widget.userId);
    _loading = false;

    // Phase 2: background — Firestore only for uncached/current month.
    DataManager.fetchUncachedMonths(widget.userId, (key, summary) {
      if (!mounted) return;
      setState(() {
        _activeMonths = _activeMonths.where((m) => m.monthKey != key).toList();
        if (summary != null && (summary.punchCount > 0 || summary.totalVisits > 0)) {
          _activeMonths = [..._activeMonths, (monthKey: key, summary: summary)]
            ..sort((a, b) => b.monthKey.compareTo(a.monthKey));
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    }

    if (_activeMonths.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bar_chart_rounded,
                size: 56, color: AppTheme.textHint),
            const SizedBox(height: 16),
            Text('No monthly data yet',
                style: AppTheme.sora(15, color: AppTheme.textSecondary)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: _activeMonths.length,
      itemBuilder: (_, i) => MonthlyCard(
        userId: widget.userId,
        monthKey: _activeMonths[i].monthKey,
        initialSummary: _activeMonths[i].summary,
      ),
    );
  }
}
