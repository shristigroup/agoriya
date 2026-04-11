import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'core/theme/app_theme.dart';
import 'data/local/local_storage_service.dart';
import 'data/repositories/firestore_repository.dart';
import 'services/location_tracking_service.dart';
import 'services/notification_service.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/auth/bloc/auth_event.dart';
import 'features/auth/bloc/auth_state.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/home/bloc/home_bloc.dart';
import 'features/home/bloc/home_event.dart';
import 'features/home/screens/home_screen.dart';
import 'features/home/visits/visit_detail_screen.dart';
import 'data/models/visit_model.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await Firebase.initializeApp();
  await LocalStorageService.init();
  await LocationTrackingService.initialize();
  await NotificationService.initialize();

  // Wire notification deep-link navigation
  NotificationService.onNotificationTap = _handleNotificationTap;

  runApp(const AgoriyaApp());
}

void _handleNotificationTap(Map<String, dynamic> data) {
  final type = data['type'] as String?;
  final targetUserId = data['targetUserId'] as String?;
  final visitId = data['visitId'] as String?;

  if (type == null || targetUserId == null) return;

  final nav = navigatorKey.currentState;
  if (nav == null) return;

  switch (type) {
    case 'check_in':
    case 'check_out':
    case 'comment':
    case 'comment_reply':
      if (visitId != null) {
        _navigateToVisitDetail(nav, targetUserId, visitId);
      }
      break;
    case 'punch_out':
      _navigateToUserHome(nav, targetUserId);
      break;
  }
}

Future<void> _navigateToVisitDetail(
  NavigatorState nav,
  String targetUserId,
  String visitId,
) async {
  try {
    // Try local cache first
    VisitModel? visit = LocalStorageService.getVisit(visitId);
    // If not cached, fetch from Firestore
    if (visit == null) {
      final visits = await FirestoreRepository().getVisits(targetUserId);
      try {
        visit = visits.firstWhere((v) => v.id == visitId);
      } catch (_) {
        return;
      }
    }
    final currentUser = LocalStorageService.getUser();
    final isOwnVisit = currentUser?.id == targetUserId;

    // Fetch comments
    final comments =
        await FirestoreRepository().getComments(targetUserId, visitId);
    visit = visit.copyWith(comments: comments);

    nav.push(MaterialPageRoute(
      builder: (_) => VisitDetailScreen(
        visit: visit!,
        targetUserId: targetUserId,
        isReadOnly: !isOwnVisit,
      ),
    ));
  } catch (_) {}
}

void _navigateToUserHome(NavigatorState nav, String targetUserId) {
  final currentUser = LocalStorageService.getUser();
  if (currentUser?.id == targetUserId) return; // own punch-out, ignore

  // Look up report name from cached reports hierarchy
  String reportName = 'Team Member';
  final reportData = LocalStorageService.getReportData(targetUserId);
  if (reportData != null && reportData['name'] != null) {
    reportName = reportData['name'] as String;
  }

  nav.push(MaterialPageRoute(
    builder: (_) => BlocProvider(
      create: (_) => HomeBloc(userId: targetUserId)
        ..add(HomeInitEvent(targetUserId)),
      child: HomeScreen(
        viewingUserId: targetUserId,
        viewingUserName: reportName,
      ),
    ),
  ));
}

class AgoriyaApp extends StatelessWidget {
  const AgoriyaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => AuthBloc()..add(CheckAuthEvent()),
        ),
      ],
      child: MaterialApp(
        title: 'Agoriya',
        theme: AppTheme.light,
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        home: const _AppEntry(),
      ),
    );
  }
}

class _AppEntry extends StatelessWidget {
  const _AppEntry();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthBloc, AuthState>(
      listener: (context, state) {},
      builder: (context, state) {
        if (state is AuthLoading || state is AuthInitial) {
          return const _SplashScreen();
        }

        if (state is AuthAuthenticated) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            try {
              final token = await NotificationService.getToken();
              if (token != null) {
                await FirestoreRepository()
                    .saveFcmToken(state.user.id, token);
              }
            } catch (_) {}
          });

          return BlocProvider(
            create: (_) => HomeBloc(userId: state.user.id)
              ..add(HomeInitEvent(state.user.id)),
            child: const HomeScreen(),
          );
        }

        return const LoginScreen();
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppTheme.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Agoriya',
              style: TextStyle(
                fontFamily: 'Sora',
                fontSize: 44,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -1,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Field Force Tracker',
              style: TextStyle(
                fontFamily: 'Sora',
                fontSize: 15,
                color: Colors.white54,
              ),
            ),
            SizedBox(height: 48),
            CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
          ],
        ),
      ),
    );
  }
}
