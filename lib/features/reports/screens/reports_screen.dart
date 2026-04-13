import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/local/local_storage_service.dart';
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

      final repo = FirestoreRepository();
      // Always query Firestore directly — local cache is stale when new
      // team members register after this user last logged in.
      final directReports = await repo.getUsersByManagerId(currentUser.id);

      final today = AppUtils.todayKey();
      final entries = await Future.wait(
        directReports.map((u) async {
          AttendanceModel? att;
          try { att = await repo.getAttendance(u.id, today); } catch (_) {}
          return _ReportEntry(userId: u.id, name: u.fullName, attendance: att);
        }),
      );
      entries.sort((a, b) => a.name.compareTo(b.name));

      if (mounted) setState(() { _reports = entries; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

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
                      onRefresh: _loadReports,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _reports.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
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
      title: Text(entry.name,
          style: AppTheme.sora(14, weight: FontWeight.w600)),
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
        builder: (_) => BlocProvider(
          create: (_) => HomeBloc(userId: entry.userId)
            ..add(HomeInitEvent(entry.userId)),
          child: HomeScreen(
            viewingUserId: entry.userId,
            viewingUserName: entry.name,
          ),
        ),
      )),
    );
  }
}

class _ReportEntry {
  final String userId;
  final String name;
  final AttendanceModel? attendance;
  _ReportEntry({required this.userId, required this.name, this.attendance});
}
