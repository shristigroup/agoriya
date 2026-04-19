import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_event.dart';
import 'auth_state.dart';
import '../../../data/repositories/firestore_repository.dart';
import '../../../data/local/local_storage_service.dart';
import '../../../data/models/user_model.dart';
import '../../../data/data_manager.dart';
import '../../../core/utils/app_utils.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirestoreRepository _repo = FirestoreRepository();

  String? _verificationId;
  String? _pendingPhoneNumber;
  String? _pendingUid;

  AuthBloc() : super(AuthInitial()) {
    on<CheckAuthEvent>(_onCheckAuth);
    on<SendOtpEvent>(_onSendOtp);
    on<VerifyOtpEvent>(_onVerifyOtp);
    on<CompleteProfileEvent>(_onCompleteProfile);
    on<LogoutEvent>(_onLogout);
  }

  Future<void> _onCheckAuth(CheckAuthEvent event, Emitter<AuthState> emit) async {
    final user = LocalStorageService.getUser();
    if (user != null && _auth.currentUser != null) {
      DataManager.init(user.id);
      emit(AuthAuthenticated(user));
    } else {
      emit(AuthUnauthenticated());
    }
  }

  Future<void> _onSendOtp(SendOtpEvent event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    _pendingPhoneNumber = event.phoneNumber;

    // Use a Completer to keep the event handler alive until the
    // codeSent callback fires asynchronously — avoids the
    // "emit called after handler completed" BLoC assertion.
    final completer = Completer<String>();

    await _auth.verifyPhoneNumber(
      phoneNumber: event.phoneNumber,
      verificationCompleted: (_) {
        // User enters OTP manually — ignore auto-verification.
      },
      verificationFailed: (FirebaseAuthException e) {
        if (!completer.isCompleted) {
          completer.completeError(e.message ?? 'Verification failed');
        }
      },
      codeSent: (String verificationId, int? resendToken) {
        if (!completer.isCompleted) {
          completer.complete(verificationId);
        }
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
        if (!completer.isCompleted) {
          completer.complete(verificationId);
        }
      },
    );

    try {
      _verificationId = await completer.future;
      emit(OtpSent(
        verificationId: _verificationId!,
        phoneNumber: event.phoneNumber,
      ));
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  Future<void> _onVerifyOtp(VerifyOtpEvent event, Emitter<AuthState> emit) async {
    if (_verificationId == null) {
      emit(AuthError('Please request OTP first'));
      return;
    }
    emit(AuthLoading());
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: event.otp,
      );
      final result = await _auth.signInWithCredential(credential);
      _pendingUid = result.user?.uid;
      emit(OtpVerified(_pendingUid!));
    } catch (e) {
      emit(AuthError('Invalid OTP. Please try again.'));
    }
  }

  Future<void> _onCompleteProfile(
      CompleteProfileEvent event, Emitter<AuthState> emit) async {
    if (_pendingUid == null || _pendingPhoneNumber == null) {
      emit(AuthError('Session expired. Please try again.'));
      return;
    }
    emit(AuthLoading());
    try {
      final existing = await _repo.getUserByPhone(_pendingPhoneNumber!);

      final docId = existing?.id ??
          AppUtils.userDocId(
            event.firstName,
            event.lastName,
            _pendingPhoneNumber!,
          );

      // Determine which org code to attach to this user.
      // Priority: existing code in DB > code entered during login > generate new one.
      String? resolvedCode = existing?.code;
      if (resolvedCode == null || resolvedCode.isEmpty) {
        if (event.orgCode != null && event.orgCode!.isNotEmpty) {
          resolvedCode = event.orgCode;
        } else {
          // No code entered — create a new org with this user as owner.
          resolvedCode = await _repo.createOrgCode(docId);
        }
      }

      final user = UserModel(
        id: docId,
        uid: _pendingUid!,
        firstName: event.firstName.isNotEmpty
            ? event.firstName
            : (existing?.firstName ?? ''),
        lastName: event.lastName.isNotEmpty
            ? event.lastName
            : (existing?.lastName ?? ''),
        phoneNumber: _pendingPhoneNumber!,
        managerId: event.managerId ?? existing?.managerId,
        reports: existing?.reports ?? {},
        code: resolvedCode,
      );

      await _repo.createOrUpdateUser(user);
      await LocalStorageService.saveUser(user);
      DataManager.init(user.id);

      // Keep the manager's `reports` map in Firestore up to date.
      final effectiveManagerId = event.managerId ?? existing?.managerId;
      if (effectiveManagerId != null) {
        try {
          final manager = await _repo.getUserById(effectiveManagerId);
          if (manager != null && !manager.reports.containsKey(docId)) {
            await _repo.createOrUpdateUser(manager.copyWith(
              reports: {...manager.reports, docId: {'name': user.fullName, 'reports': {}}},
            ));
          }
        } catch (_) {}
      }

      // If joining an org via code (not generating a new one), increment count.
      if (event.orgCode != null &&
          event.orgCode!.isNotEmpty &&
          (existing?.code == null || existing!.code!.isEmpty)) {
        try {
          await _repo.incrementOrgUserCount(event.orgCode!);
        } catch (_) {}
      }

      emit(AuthAuthenticated(user));
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  Future<void> _onLogout(LogoutEvent event, Emitter<AuthState> emit) async {
    await _auth.signOut();
    await LocalStorageService.clearAll();
    emit(AuthUnauthenticated());
  }
}
