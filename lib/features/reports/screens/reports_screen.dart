import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/local/local_storage_service.dart';
import '../../../data/models/tracking_model.dart';
import '../../../data/models/org_code_model.dart';
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
  OrgCodeModel? _orgCode;

  @override
  void initState() {
    super.initState();
    _loadFromCache();
    _refreshFromFirestore();
  }

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

  Future<void> _loadFromCache() async {
    final currentUser = LocalStorageService.getUser();
    if (currentUser == null) {
      if (mounted) setState(() { _loading = false; _error = 'Not logged in'; });
      return;
    }
    final entries = _flatten(currentUser.reports);
    await _populateAttendance(entries);
  }

  Future<void> _refreshFromFirestore() async {
    try {
      final currentUser = LocalStorageService.getUser();
      if (currentUser == null) return;

      final repo = FirestoreRepository();
      final fresh = await repo.getUserById(currentUser.id);
      if (fresh == null || !mounted) return;

      await LocalStorageService.saveUser(fresh);
      final entries = _flatten(fresh.reports);
      await _populateAttendance(entries);

      // Load org code stats if user has a code
      if (fresh.code != null && fresh.code!.isNotEmpty) {
        try {
          final orgCode = await repo.getOrgCode(fresh.code!);
          if (mounted) setState(() => _orgCode = orgCode);
        } catch (_) {}
      }
    } catch (_) {}
  }

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

  Future<void> _onRefresh() => _refreshFromFirestore();

  Future<void> _removeUser(_ReportEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove member'),
        content: Text('Remove ${entry.name} from your organisation?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await FirestoreRepository().removeUserFromOrg(entry.userId);
      await _refreshFromFirestore();
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().contains('cannot_remove_has_reports')
          ? '${entry.name} still has team members reporting to them. They must change their manager first.'
          : 'Could not remove member. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: AppTheme.error,
      ));
    }
  }

  void _shareInvite() {
    final currentUser = LocalStorageService.getUser();
    final code = currentUser?.code ?? '';
    if (code.isEmpty) return;
    SharePlus.instance.share(ShareParams(
      text: 'Join my team on TrackFolks!\n\nUse my organisation code: $code\n\nDownload the app: https://tf.shristigroup.com',
    ));
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = LocalStorageService.getUser();
    final hasCode = currentUser?.code != null && currentUser!.code!.isNotEmpty;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('My Team')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _error != null
              ? Center(child: Text(_error!, style: AppTheme.sora(14, color: AppTheme.error)))
              : Column(
                  children: [
                    // ── Org stats bar ───────────────────────────────────────
                    if (_orgCode != null)
                      _buildOrgStatsBar(_orgCode!),

                    // ── Swipe hint ──────────────────────────────────────────
                    if (_reports.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Row(
                          children: [
                            const Icon(Icons.swipe_left_outlined,
                                size: 14, color: AppTheme.textHint),
                            const SizedBox(width: 6),
                            Text('Swipe left on a member to remove them',
                                style: AppTheme.sora(11, color: AppTheme.textHint)),
                          ],
                        ),
                      ),

                    // ── List ────────────────────────────────────────────────
                    Expanded(
                      child: _reports.isEmpty
                          ? _buildEmptyState()
                          : RefreshIndicator(
                              onRefresh: _onRefresh,
                              child: ListView.separated(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                itemCount: _reports.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1, indent: 72),
                                itemBuilder: (_, i) =>
                                    _buildTile(_reports[i]),
                              ),
                            ),
                    ),

                    // ── Invite button ───────────────────────────────────────
                    if (hasCode)
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: OutlinedButton.icon(
                              onPressed: _shareInvite,
                              icon: const Icon(Icons.share_outlined, size: 18),
                              label: const Text('Invite from your Organisation'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.primary,
                                side: const BorderSide(color: AppTheme.primary),
                                textStyle: AppTheme.sora(14, weight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }

  Widget _buildOrgStatsBar(OrgCodeModel org) {
    final remaining = org.remainingSeats;
    return Container(
      color: AppTheme.primary.withValues(alpha: 0.06),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.group_outlined, size: 16, color: AppTheme.primary),
          const SizedBox(width: 8),
          Text(
            '${org.currentUserCount} of ${org.totalUserCount} members',
            style: AppTheme.sora(13, weight: FontWeight.w600, color: AppTheme.primary),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: remaining > 0 ? AppTheme.punchIn.withValues(alpha: 0.12) : AppTheme.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              remaining > 0 ? '$remaining seats left' : 'Full',
              style: AppTheme.sora(11,
                  weight: FontWeight.w600,
                  color: remaining > 0 ? AppTheme.punchIn : AppTheme.error),
            ),
          ),
        ],
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
              'Invite people using your organisation code.',
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

    return Dismissible(
      key: ValueKey(entry.userId),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await _removeUser(entry);
        return false; // we handle list refresh ourselves
      },
      background: Container(
        alignment: Alignment.centerRight,
        color: AppTheme.error,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.person_remove_outlined,
            color: Colors.white, size: 24),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
          child: Text(
            AppUtils.getInitials(entry.name),
            style: AppTheme.sora(15, weight: FontWeight.w700, color: AppTheme.primary),
          ),
        ),
        title: Text(entry.name, style: AppTheme.sora(14, weight: FontWeight.w600)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: statusColor.withValues(alpha: 0.3)),
          ),
          child: Text(status,
              style: AppTheme.sora(11, weight: FontWeight.w600, color: statusColor)),
        ),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => HistoryScreen(userId: entry.userId, userName: entry.name),
        )),
      ),
    );
  }
}

class _ReportEntry {
  final String userId;
  final String name;
  final TrackingModel? attendance;
  _ReportEntry({required this.userId, required this.name, this.attendance});
}
