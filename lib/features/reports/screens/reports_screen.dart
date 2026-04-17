import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/local/local_storage_service.dart';
import '../../../data/models/tracking_model.dart';
import '../../../data/data_manager.dart';
import '../../../data/repositories/firestore_repository.dart';
import '../../history/screens/history_screen.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  List<_ReportEntry> _reports = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFromCache();
    _refreshFromFirestore();
  }

  /// Recursively flattens the nested reports JSON into a flat list.
  /// Structure: { userId: { 'name': '...', 'reports': { ... } } }
  List<_ReportEntry> _flatten(Map<String, dynamic> reports) {
    final list = <_ReportEntry>[];
    for (final entry in reports.entries) {
      final data = Map<String, dynamic>.from(entry.value as Map);
      final name = data['name'] as String? ?? '';
      list.add(_ReportEntry(userId: entry.key, name: name));
      final sub = Map<String, dynamic>.from(data['reports'] as Map? ?? {});
      if (sub.isNotEmpty) list.addAll(_flatten(sub));
    }
    return list;
  }

  /// Phase 1: show from cache immediately.
  Future<void> _loadFromCache() async {
    final currentUser = LocalStorageService.getUser();
    if (currentUser == null) {
      if (mounted) setState(() { _loading = false; _error = 'Not logged in'; });
      return;
    }
    final entries = _flatten(currentUser.reports);
    await _populateAttendance(entries);
  }

  /// Phase 2: fetch updated user doc (single read) to pick up new reports,
  /// save to cache, then silently refresh the list.
  Future<void> _refreshFromFirestore() async {
    try {
      final currentUser = LocalStorageService.getUser();
      if (currentUser == null) return;

      final fresh = await FirestoreRepository().getUserById(currentUser.id);
      if (fresh == null || !mounted) return;

      await LocalStorageService.saveUser(fresh);
      final entries = _flatten(fresh.reports);
      await _populateAttendance(entries);
    } catch (_) {
      // Silent fail — cached list stays visible.
    }
  }

  /// Fetches today's tracking session for each entry and updates the list.
  Future<void> _populateAttendance(List<_ReportEntry> entries) async {
    final today = AppUtils.todayKey();
    final withTracking = await Future.wait(
      entries.map((e) async {
        TrackingModel? t;
        try { t = await DataManager.getTrackingForToday(e.userId, today); } catch (_) {}
        return _ReportEntry(userId: e.userId, name: e.name, attendance: t);
      }),
    );
    withTracking.sort((a, b) => a.name.compareTo(b.name));
    if (mounted) setState(() { _reports = withTracking; _loading = false; });
  }

  /// Pull-to-refresh re-runs the Firestore fetch.
  Future<void> _onRefresh() => _refreshFromFirestore();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('My Team')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _error != null
              ? Center(child: Text(_error!, style: AppTheme.sora(14, color: AppTheme.error)))
              : _reports.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      onRefresh: _onRefresh,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _reports.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 72),
                        itemBuilder: (_, i) => _buildTile(_reports[i]),
                      ),
                    ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.people_outline, size: 60, color: AppTheme.textHint),
            const SizedBox(height: 16),
            Text('No team members yet',
                style: AppTheme.sora(16, color: AppTheme.textSecondary)),
            const SizedBox(height: 8),
            Text(
              'Team members who set you as their manager will appear here.',
              textAlign: TextAlign.center,
              style: AppTheme.sora(13, color: AppTheme.textHint),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTile(_ReportEntry entry) {
    final isActive = entry.attendance?.isPunchedIn == true &&
        entry.attendance?.isPunchedOut == false;
    final isPunchedOut = entry.attendance?.isPunchedOut == true;

    final String status;
    final Color statusColor;
    if (isActive) {
      status = 'At work';
      statusColor = AppTheme.punchIn;
    } else if (isPunchedOut) {
      status = 'Punched out';
      statusColor = AppTheme.textSecondary;
    } else {
      status = 'Not in';
      statusColor = AppTheme.textHint;
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: AppTheme.primary.withOpacity(0.12),
        child: Text(
          AppUtils.getInitials(entry.name),
          style: AppTheme.sora(15, weight: FontWeight.w700, color: AppTheme.primary),
        ),
      ),
      title: Text(entry.name, style: AppTheme.sora(14, weight: FontWeight.w600)),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: statusColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: statusColor.withOpacity(0.3)),
        ),
        child: Text(status,
            style: AppTheme.sora(11, weight: FontWeight.w600, color: statusColor)),
      ),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => HistoryScreen(userId: entry.userId, userName: entry.name),
      )),
    );
  }
}

class _ReportEntry {
  final String userId;
  final String name;
  final TrackingModel? attendance;
  _ReportEntry({required this.userId, required this.name, this.attendance});
}
