import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_messaging/firebase_messaging.dart'
    show AuthorizationStatus;
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
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
import '../../history/screens/history_screen.dart';
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
      // Request location permissions on first open — runs after first frame
      // so the widget tree is ready to show dialogs.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensureLocationPermission();
      });
    }
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
    super.dispose();
  }

  /// Shows a dialog explaining a permission issue with an "Open Settings" button.
  Future<void> _showPermissionDialog(String title, String message) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  /// Returns true only when foreground and background location are both granted.
  /// Uses Geolocator's permission API so it accepts approximate location too —
  /// the user does NOT need to enable "Precise location".
  Future<bool> _ensureLocationPermission() async {
    // ── Step 1: foreground location (coarse or fine both accepted) ────────────
    var perm = await Geolocator.checkPermission();

    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }

    if (perm == LocationPermission.deniedForever) {
      await _showPermissionDialog(
        'Location Permission Required',
        'Location access has been permanently denied.\n\n'
        'Please go to Settings → Agoriya → Permissions → Location and enable it.',
      );
      return false;
    }

    if (perm == LocationPermission.denied) {
      await _showPermissionDialog(
        'Location Permission Required',
        'Agoriya needs location access to track your field visits.\n\n'
        'Please enable location permission in Settings.',
      );
      return false;
    }

    // Already "always" — nothing more to do.
    if (perm == LocationPermission.always) return true;

    // ── Step 2: background location ("Allow all the time") ───────────────────
    // perm is whileInUse at this point — need to upgrade.
    var bgStatus = await Permission.locationAlways.status;
    if (bgStatus.isGranted) return true;

    // Explain before sending to settings.
    if (!mounted) return false;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Background Location Needed'),
        content: const Text(
          'Agoriya needs to track your location while punched in, even when '
          'the app is in the background.\n\n'
          'Precise location is not required — approximate is fine.\n\n'
          'On the next screen select "Allow all the time".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (proceed != true) return false;

    bgStatus = await Permission.locationAlways.request();

    // If still not granted, show dialog with Settings button (don't just snackbar).
    if (!bgStatus.isGranted) {
      await _showPermissionDialog(
        'Background Location Needed',
        'Please go to Settings → Agoriya → Permissions → Location '
        'and select "Allow all the time".\n\n'
        'You do not need to enable "Precise location".',
      );
      return false;
    }

    return true;
  }

  Future<bool> _ensureCameraPermission() =>
      _ensureSimplePermission(
        permission: Permission.camera,
        title: 'Camera Permission Required',
        permanentlyDeniedMessage:
            'Camera access has been permanently denied.\n\n'
            'Please go to Settings → Agoriya → Camera and enable it.',
        deniedMessage:
            'Agoriya needs camera access to take a selfie when you punch in.\n\n'
            'Please enable camera permission in Settings.',
      );

  /// Generic helper for single-step permissions (camera, photos, etc.).
  /// Location uses a custom multi-step flow and is handled separately.
  Future<bool> _ensureSimplePermission({
    required Permission permission,
    required String title,
    required String permanentlyDeniedMessage,
    required String deniedMessage,
  }) async {
    var status = await permission.status;
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) {
      await _showPermissionDialog(title, permanentlyDeniedMessage);
      return false;
    }
    status = await permission.request();
    if (status.isGranted) return true;
    await _showPermissionDialog(title, deniedMessage);
    return false;
  }

  Future<void> _handlePunchIn(HomeLoaded state) async {
    if (!await _ensureLocationPermission()) return;
    if (!await _ensureCameraPermission()) return;

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
    final state = context.read<HomeBloc>().state;
    if (state is HomeLoaded && state.isSnapping) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Route calculation in progress, please wait...'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
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
            Text(message, style: AppTheme.sora(14)),
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

  /// Bottom sheet shown when the user taps "Punch In" after already being
  /// punched out today. Offers "Resume Session" (undo punch-out) or
  /// "Fresh Punch In" (start a brand-new session, overwriting today's data).
  Future<void> _showPunchInOptions(
      BuildContext context, HomeLoaded state) async {
    final punchOutTime = state.attendance?.punchOutTimestamp;

    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text('Punch In',
                  style: AppTheme.sora(18, weight: FontWeight.w700)),
              const SizedBox(height: 20),
              if (punchOutTime != null) ...[
                _punchInOption(
                  context: context,
                  icon: Icons.replay_rounded,
                  iconColor: AppTheme.accent,
                  title: 'Resume Session',
                  subtitle:
                      'Punched out at ${AppUtils.formatTime(punchOutTime)}',
                  onTap: () {
                    Navigator.pop(context);
                    context.read<HomeBloc>().add(ResumeSessionEvent());
                  },
                ),
                const SizedBox(height: 12),
              ],
              _punchInOption(
                context: context,
                icon: Icons.fingerprint_rounded,
                iconColor: AppTheme.punchIn,
                title: 'Fresh Punch In',
                subtitle: 'Start a new session for today',
                onTap: () {
                  Navigator.pop(context);
                  _handlePunchIn(state);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _punchInOption({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: iconColor.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: AppTheme.sora(14, weight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: AppTheme.sora(12,
                          color: AppTheme.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: AppTheme.textHint, size: 20),
          ],
        ),
      ),
    );
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
        final isPunchingOut = loaded?.isPunchingOut ?? false;
        final attendance = loaded?.attendance;

        return Stack(
          children: [
            Scaffold(
          appBar: AppBar(
            backgroundColor: AppTheme.primary,
            elevation: 0,
            leading: _isReadOnly
                ? IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  )
                : null,
            title: Text(
              _isReadOnly ? (widget.viewingUserName ?? 'Team Member') : 'Agoriya',
              style: AppTheme.sora(22, weight: FontWeight.w700, color: Colors.white),
            ),
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.menu, color: Colors.white),
                onSelected: (val) {
                  if (val == 'history') {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => HistoryScreen(
                        userId: _targetUserId,
                        userName: _isReadOnly ? widget.viewingUserName : null,
                      ),
                    ));
                  } else if (val == 'reports') {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const ReportsScreen(),
                    ));
                  } else if (val == 'logout') {
                    context.read<AuthBloc>().add(LogoutEvent());
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'history',
                    child: Row(children: [
                      Icon(Icons.history_rounded, size: 18),
                      SizedBox(width: 10),
                      Text('History'),
                    ]),
                  ),
                  if (!_isReadOnly) ...[
                    const PopupMenuItem(
                      value: 'reports',
                      child: Row(children: [
                        Icon(Icons.people_alt_rounded, size: 18),
                        SizedBox(width: 10),
                        Text('Reports'),
                      ]),
                    ),
                    const PopupMenuItem(
                      value: 'logout',
                      child: Row(children: [
                        Icon(Icons.logout_rounded, size: 18, color: AppTheme.error),
                        SizedBox(width: 10),
                        Text('Logout', style: TextStyle(color: AppTheme.error)),
                      ]),
                    ),
                  ],
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              // ── Stats strip ───────────────────────────────────────────────
              Container(
                color: AppTheme.primary,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: _buildStatsRow(loaded, attendance),
              ),
              // ── Tab bar ───────────────────────────────────────────────────
              Container(
                color: AppTheme.primary,
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: AppTheme.accent,
                  indicatorWeight: 3,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white60,
                  labelStyle: AppTheme.sora(14, weight: FontWeight.w600),
                  unselectedLabelStyle: AppTheme.sora(14),
                  tabs: const [
                    Tab(text: 'Track'),
                    Tab(text: 'Visits'),
                  ],
                ),
              ),
              // ── Tab content ───────────────────────────────────────────────
              Expanded(
                child: state is HomeLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: AppTheme.primary))
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          TrackTab(
                            attendance: attendance,
                            locations: loaded?.locations ?? [],
                            lastKnownLocation: loaded?.lastKnownLocation,
                            isReadOnly: _isReadOnly,
                            isSnapping: loaded?.isSnapping ?? false,
                          ),
                          BlocProvider.value(
                            value: context.read<HomeBloc>(),
                            child: VisitsTab(
                              visits: loaded?.visits ?? [],
                              targetUserId: _targetUserId,
                              isReadOnly: _isReadOnly,
                              isPunchedOut: isPunchedOut,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
          floatingActionButton: _isReadOnly
              ? null
              : _buildFAB(context, loaded, isPunchedIn, isPunchedOut),
          floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
        ),
            // Full-screen punch-out overlay
            if (isPunchingOut)
              Container(
                color: Colors.black.withOpacity(0.65),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 16),
                      Text(
                        'Punching out...',
                        style: AppTheme.sora(16,
                            weight: FontWeight.w600, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildStatsRow(HomeLoaded? loaded, attendance) {
    final isPunchedIn = loaded?.isPunchedIn ?? false;
    final isTrackTab = _currentTab == 0;

    return Row(
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
                    ? AppUtils.formatDistance(loaded!.displayDistance)
                    : '-')
                : (isPunchedIn
                    ? '₹${_totalExpense(loaded?.visits ?? []).toStringAsFixed(0)}'
                    : '-'),
            isTrackTab ? Icons.route_rounded : Icons.receipt_rounded,
          ),
        ],
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
                Text(label, style: AppTheme.sora(11, color: Colors.white.withOpacity(0.65))),
                Text(value, style: AppTheme.sora(18, weight: FontWeight.w800, color: Colors.white)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget? _buildFAB(
    BuildContext context,
    HomeLoaded? loaded,
    bool isPunchedIn,
    bool isPunchedOut,
  ) {
    // Day is done — show Punch In FAB that opens the options sheet.
    // User can resume today's accidental punch-out or start a fresh session.
    if (isPunchedOut) {
      return FloatingActionButton.extended(
        onPressed: loaded != null ? () => _showPunchInOptions(context, loaded) : null,
        backgroundColor: AppTheme.punchIn,
        icon: const Icon(Icons.fingerprint_rounded),
        label: Text('Punch In', style: AppTheme.sora(14, weight: FontWeight.w600, color: Colors.white)),
      );
    }

    // Not yet punched in — go straight to camera (no resumable session today).
    if (!isPunchedIn) {
      return FloatingActionButton.extended(
        onPressed: loaded != null ? () => _handlePunchIn(loaded) : null,
        backgroundColor: AppTheme.punchIn,
        icon: const Icon(Icons.fingerprint_rounded),
        label: Text('Punch In', style: AppTheme.sora(14, weight: FontWeight.w600, color: Colors.white)),
      );
    }

    // Punched in — Track tab shows Punch Out.
    if (_currentTab == 0) {
      return FloatingActionButton.extended(
        onPressed: _handlePunchOut,
        backgroundColor: AppTheme.punchOut,
        icon: const Icon(Icons.logout_rounded),
        label: Text('Punch Out', style: AppTheme.sora(14, weight: FontWeight.w600, color: Colors.white)),
      );
    }

    // Punched in — Visits tab shows Check In.
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
      label: Text('Check In', style: AppTheme.sora(14, weight: FontWeight.w600, color: Colors.white)),
    );
  }
}
