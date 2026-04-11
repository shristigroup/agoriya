import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/local/local_storage_service.dart';
import '../../../data/models/user_model.dart';
import '../../../data/models/attendance_model.dart';
import '../../../data/repositories/firestore_repository.dart';
import '../../home/bloc/home_bloc.dart';
import '../../home/bloc/home_event.dart';
import '../../home/screens/home_screen.dart';

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
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() { _loading = true; _error = null; });
    try {
      final currentUser = LocalStorageService.getUser();
      if (currentUser == null) {
        setState(() { _loading = false; _error = 'Not logged in'; });
        return;
      }

      // Flatten the denormalised hierarchy JSON into a list
      // The JSON shape: { userId: { name, reports: { userId: { name, reports: {} } } } }
      final flat = _flattenHierarchy(currentUser.reports, currentUser.id);
      flat.sort((a, b) => a.name.compareTo(b.name));

      if (flat.isEmpty) {
        setState(() { _loading = false; _reports = []; });
        return;
      }

      // Fetch all users in one pass to get manager names (avoid N+1)
      final repo = FirestoreRepository();
      final allUsersMap = <String, UserModel>{};
      try {
        final allUsers = await repo.getAllUsers();
        for (final u in allUsers) { allUsersMap[u.id] = u; }
      } catch (_) {}

      // Fetch today's attendance for each report
      final today = AppUtils.todayKey();
      final entries = <_ReportEntry>[];
      for (final item in flat) {
        AttendanceModel? todayAtt;
        try {
          // Try local cache first
          final cached = LocalStorageService.getReportData(item.userId);
          if (cached != null && cached['attendance'] != null) {
            final attJson = cached['attendance'] as Map<String, dynamic>;
            if (attJson['date'] == today) {
              todayAtt = AttendanceModel.fromJson(attJson);
            }
          }
          // Always refresh from Firestore
          final fresh = await repo.getAttendance(item.userId, today);
          if (fresh != null) {
            todayAtt = fresh;
            // Cache it
            final existing = LocalStorageService.getReportData(item.userId) ?? {};
            existing['attendance'] = fresh.toJson();
            existing['name'] = item.name;
            await LocalStorageService.saveReportData(item.userId, existing);
          }
        } catch (_) {}

        // Resolve manager name from the already-fetched map
        String managerName = '';
        if (item.directManagerId != null) {
          managerName = allUsersMap[item.directManagerId]?.fullName ?? '';
        }

        entries.add(_ReportEntry(
          userId: item.userId,
          name: item.name,
          directManagerId: item.directManagerId,
          managerName: managerName,
          attendance: todayAtt,
        ));
      }

      if (mounted) setState(() { _reports = entries; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  /// Recursively flattens the hierarchy JSON.
  /// [currentManagerId] is the doc-id of the manager who owns this subtree.
  List<_FlatReport> _flattenHierarchy(
    Map<String, dynamic> node,
    String currentManagerId,
  ) {
    final result = <_FlatReport>[];
    node.forEach((userId, data) {
      final map = Map<String, dynamic>.from(data as Map);
      result.add(_FlatReport(
        userId: userId,
        name: map['name'] as String? ?? '',
        directManagerId: currentManagerId,
      ));
      final subReports = map['reports'];
      if (subReports is Map && subReports.isNotEmpty) {
        result.addAll(
          _flattenHierarchy(
            Map<String, dynamic>.from(subReports),
            userId, // this user is the manager of the next level
          ),
        );
      }
    });
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('My Team')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: AppTheme.error)))
              : _reports.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      onRefresh: _loadReports,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _reports.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 72),
                        itemBuilder: (context, i) =>
                            _buildReportTile(_reports[i]),
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
            const Text(
              'No team members yet',
              style: TextStyle(
                fontFamily: 'Sora',
                fontSize: 16,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Team members who set you as their manager will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Sora',
                fontSize: 13,
                color: AppTheme.textHint,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportTile(_ReportEntry entry) {
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
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: AppTheme.primary.withOpacity(0.12),
        child: Text(
          AppUtils.getInitials(entry.name),
          style: const TextStyle(
            fontFamily: 'Sora',
            fontWeight: FontWeight.w700,
            color: AppTheme.primary,
            fontSize: 15,
          ),
        ),
      ),
      title: Text(
        entry.name,
        style: const TextStyle(
          fontFamily: 'Sora',
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary,
        ),
      ),
      subtitle: entry.managerName.isNotEmpty
          ? Text(
              'Mgr: ${entry.managerName}',
              style: const TextStyle(
                fontFamily: 'Sora',
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            )
          : null,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: statusColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: statusColor.withOpacity(0.3)),
        ),
        child: Text(
          status,
          style: TextStyle(
            fontFamily: 'Sora',
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: statusColor,
          ),
        ),
      ),
      onTap: () => _openReportHome(entry),
    );
  }

  void _openReportHome(_ReportEntry entry) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BlocProvider(
        create: (_) => HomeBloc(userId: entry.userId)
          ..add(HomeInitEvent(entry.userId)),
        child: HomeScreen(
          viewingUserId: entry.userId,
          viewingUserName: entry.name,
        ),
      ),
    ));
  }
}

class _FlatReport {
  final String userId;
  final String name;
  final String? directManagerId;
  _FlatReport({
    required this.userId,
    required this.name,
    this.directManagerId,
  });
}

class _ReportEntry {
  final String userId;
  final String name;
  final String? directManagerId;
  final String managerName;
  final AttendanceModel? attendance;

  _ReportEntry({
    required this.userId,
    required this.name,
    this.directManagerId,
    required this.managerName,
    this.attendance,
  });
}
