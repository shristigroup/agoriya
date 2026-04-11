import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_messaging/firebase_messaging.dart'
    show AuthorizationStatus;
import 'package:flutter_background_service/flutter_background_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/local/local_storage_service.dart';
import '../../../data/models/attendance_model.dart';
import '../../../data/models/visit_model.dart';
import '../../../data/repositories/firestore_repository.dart';
import '../bloc/home_bloc.dart';
import '../bloc/home_event.dart';
import '../bloc/home_state.dart';
import '../track/track_tab.dart';
import '../visits/visits_tab.dart';
import '../visits/check_in_screen.dart';
import '../screens/punch_in_camera_screen.dart';
import '../screens/punch_animations_screen.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../reports/screens/reports_screen.dart';
import '../../../services/notification_service.dart';

class HomeScreen extends StatefulWidget {
  /// When set, this is a manager viewing a report's home screen
  final String? viewingUserId;
  final String? viewingUserName;

  const HomeScreen({
    super.key,
    this.viewingUserId,
    this.viewingUserName,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentTab = 0;
  StreamSubscription? _bgServiceSub;
  bool _loadingDialogOpen = false;

  bool get _isReadOnly => widget.viewingUserId != null;
  String get _targetUserId {
    if (_isReadOnly) return widget.viewingUserId!;
    return LocalStorageService.getUser()?.id ?? '';
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() => _currentTab = _tabController.index);
    });
    if (!_isReadOnly) {
      _checkNotificationPermission();
      _subscribeToBgService();
    }
  }

  void _subscribeToBgService() {
    _bgServiceSub = FlutterBackgroundService()
        .on('newPoint')
        .listen((data) {
      if (data == null || !mounted) return;
      context.read<HomeBloc>().add(NewLocationPointEvent(
            lat: (data['lat'] as num).toDouble(),
            lng: (data['lng'] as num).toDouble(),
            timestamp: DateTime.parse(data['timestamp'] as String),
          ));
    });
  }

  Future<void> _checkNotificationPermission() async {
    final user = LocalStorageService.getUser();
    if (user == null || user.reports.isEmpty) return;
    final status = await NotificationService.getPermissionStatus();
    if (status != AuthorizationStatus.authorized && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showNotificationPrompt();
      });
    }
  }

  void _showNotificationPrompt() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Enable Notifications'),
        content: const Text(
          'You have team members reporting to you. Enable notifications to stay updated on their activities.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await NotificationService.requestPermission();
            },
            child: const Text('Enable'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _bgServiceSub?.cancel();
    super.dispose();
  }

  Future<void> _handlePunchIn(HomeLoaded state) async {
    final file = await Navigator.of(context).push<File>(
      MaterialPageRoute(builder: (_) => const PunchInCameraScreen()),
    );
    if (file == null || !mounted) return;

    _showLoadingDialog('Uploading selfie...');

    try {
      final user = LocalStorageService.getUser()!;
      final today = AppUtils.todayKey();
      final now = DateTime.now();
      final imageUrl = await FirestoreRepository()
          .uploadPunchInImage(user.id, today, file);

      if (mounted) _dismissLoadingDialog();

      context.read<HomeBloc>().add(PunchInEvent(imageUrl));

      // Build a minimal attendance for the animation screen
      final att = state.attendance?.copyWith(
            punchInTimestamp: now,
            punchInImage: imageUrl,
          ) ??
          AttendanceModel(
            date: today,
            punchInTimestamp: now,
            punchInImage: imageUrl,
          );

      if (mounted) {
        await Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => PunchInSuccessScreen(attendance: att),
            transitionDuration: const Duration(milliseconds: 400),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _dismissLoadingDialog();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.error),
        );
      }
    }
  }

  Future<void> _handlePunchOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Punch Out?'),
        content: const Text('Are you sure you want to punch out for today?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.punchOut),
            child: const Text('Punch Out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      context.read<HomeBloc>().add(PunchOutEvent());
    }
  }

  void _showLoadingDialog(String message) {
    if (_loadingDialogOpen) return;
    _loadingDialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Text(message, style: const TextStyle(fontFamily: 'Sora')),
          ],
        ),
      ),
    ).whenComplete(() => _loadingDialogOpen = false);
  }

  void _dismissLoadingDialog() {
    if (_loadingDialogOpen && mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<HomeBloc, HomeState>(
      listener: (context, state) {
        if (state is PunchInSuccess) {
          context.read<HomeBloc>().add(HomeInitEvent(_targetUserId));
        } else if (state is PunchOutSuccess) {
          final attendance = state.attendance;
          final totalTime = state.totalTime;
          Navigator.of(context).push(
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => PunchOutSummaryScreen(
                attendance: attendance,
                totalTime: totalTime,
              ),
              transitionDuration: const Duration(milliseconds: 400),
              transitionsBuilder: (_, anim, __, child) =>
                  FadeTransition(opacity: anim, child: child),
            ),
          ).then((_) {
            context.read<HomeBloc>().add(HomeInitEvent(_targetUserId));
          });
        } else if (state is HomeError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: AppTheme.error,
            ),
          );
        }
      },
      builder: (context, state) {
        final loaded = state is HomeLoaded ? state : null;
        final isPunchedIn = loaded?.isPunchedIn ?? false;
        final isPunchedOut = loaded?.isPunchedOut ?? false;
        final attendance = loaded?.attendance;

        return Scaffold(
          body: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverAppBar(
                expandedHeight: 160,
                floating: false,
                pinned: true,
                snap: false,
                backgroundColor: AppTheme.primary,
                leading: _isReadOnly
                    ? IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.of(context).pop(),
                      )
                    : null,
                title: Text(
                  _isReadOnly
                      ? (widget.viewingUserName ?? 'Team Member')
                      : 'Agoriya',
                  style: const TextStyle(
                    fontFamily: 'Sora',
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                actions: [
                  if (!_isReadOnly)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.menu, color: Colors.white),
                      onSelected: (val) {
                        if (val == 'reports') {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const ReportsScreen(),
                          ));
                        } else if (val == 'logout') {
                          context.read<AuthBloc>().add(LogoutEvent());
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'reports',
                          child: Row(
                            children: [
                              Icon(Icons.people_alt_rounded, size: 18),
                              SizedBox(width: 10),
                              Text('Reports'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'logout',
                          child: Row(
                            children: [
                              Icon(Icons.logout_rounded, size: 18, color: AppTheme.error),
                              SizedBox(width: 10),
                              Text('Logout', style: TextStyle(color: AppTheme.error)),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: _buildSliverHeader(loaded, attendance),
                ),
                bottom: TabBar(
                  controller: _tabController,
                  indicatorColor: AppTheme.accent,
                  indicatorWeight: 3,
                  labelStyle: const TextStyle(
                    fontFamily: 'Sora',
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontFamily: 'Sora',
                    fontWeight: FontWeight.w400,
                    fontSize: 14,
                  ),
                  tabs: const [
                    Tab(text: 'Track'),
                    Tab(text: 'Visits'),
                  ],
                ),
              ),
            ],
            body: state is HomeLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      // Track tab
                      TrackTab(
                        attendance: attendance,
                        locations: loaded?.locations ?? [],
                        lastKnownLocation: loaded?.lastKnownLocation,
                        isReadOnly: _isReadOnly,
                      ),
                      // Visits tab
                      BlocProvider.value(
                        value: context.read<HomeBloc>(),
                        child: VisitsTab(
                          visits: loaded?.visits ?? [],
                          filteredVisits: loaded?.filteredVisits ?? [],
                          filterClient: loaded?.filterClient,
                          clientNames: LocalStorageService.getDistinctClientNames(),
                          targetUserId: _targetUserId,
                          isReadOnly: _isReadOnly,
                        ),
                      ),
                    ],
                  ),
          ),
          floatingActionButton: _isReadOnly
              ? null
              : _buildFAB(context, loaded, isPunchedIn, isPunchedOut),
        );
      },
    );
  }

  Widget _buildSliverHeader(HomeLoaded? loaded, attendance) {
    final isPunchedIn = loaded?.isPunchedIn ?? false;
    final isTrackTab = _currentTab == 0;

    return Container(
      decoration: const BoxDecoration(color: AppTheme.primary),
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 48),
      child: Row(
        children: [
          _statChip(
            isTrackTab ? 'Time' : 'Visits',
            isTrackTab
                ? (isPunchedIn
                    ? AppUtils.formatDuration(
                        loaded!.attendance!.attendanceDuration)
                    : '-')
                : (isPunchedIn
                    ? '${loaded!.attendance?.customerVisitCount ?? 0}'
                    : '-'),
            isTrackTab ? Icons.access_time_rounded : Icons.storefront_rounded,
          ),
          const SizedBox(width: 12),
          _statChip(
            isTrackTab ? 'Distance' : 'Expense',
            isTrackTab
                ? (isPunchedIn
                    ? AppUtils.formatDistance(loaded!.attendance?.distance ?? 0)
                    : '-')
                : (isPunchedIn
                    ? '₹${_totalExpense(loaded?.visits ?? []).toStringAsFixed(0)}'
                    : '-'),
            isTrackTab ? Icons.route_rounded : Icons.receipt_rounded,
          ),
        ],
      ),
    );
  }

  double _totalExpense(List<VisitModel> visits) {
    double total = 0;
    for (final v in visits) {
      if (AppUtils.isSameDay(v.checkinTimestamp, DateTime.now())) {
        total += v.expenseAmount ?? 0;
      }
    }
    return total;
  }

  Widget _statChip(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.accent, size: 20),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.65),
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFAB(
    BuildContext context,
    HomeLoaded? loaded,
    bool isPunchedIn,
    bool isPunchedOut,
  ) {
    if (!isPunchedIn || isPunchedOut) {
      return FloatingActionButton.extended(
        onPressed: loaded != null ? () => _handlePunchIn(loaded) : null,
        backgroundColor: AppTheme.punchIn,
        icon: const Icon(Icons.fingerprint_rounded),
        label: const Text('Punch In',
            style: TextStyle(fontFamily: 'Sora', fontWeight: FontWeight.w600)),
      );
    }

    if (_currentTab == 0) {
      return FloatingActionButton.extended(
        onPressed: _handlePunchOut,
        backgroundColor: AppTheme.punchOut,
        icon: const Icon(Icons.logout_rounded),
        label: const Text('Punch Out',
            style: TextStyle(fontFamily: 'Sora', fontWeight: FontWeight.w600)),
      );
    }

    // Visits tab - Check In
    return FloatingActionButton.extended(
      onPressed: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => BlocProvider.value(
            value: context.read<HomeBloc>(),
            child: const CheckInScreen(),
          ),
        ));
      },
      backgroundColor: AppTheme.checkIn,
      icon: const Icon(Icons.add_location_alt_rounded),
      label: const Text('Check In',
          style: TextStyle(fontFamily: 'Sora', fontWeight: FontWeight.w600)),
    );
  }
}
