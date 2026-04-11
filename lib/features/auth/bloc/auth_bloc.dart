import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_event.dart';
import 'auth_state.dart';
import '../../../data/repositories/firestore_repository.dart';
import '../../../data/local/local_storage_service.dart';
import '../../../data/models/user_model.dart';
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
      );

      await _repo.createOrUpdateUser(user);
      await LocalStorageService.saveUser(user);
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
