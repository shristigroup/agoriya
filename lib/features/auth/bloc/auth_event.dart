abstract class AuthEvent {}

class SendOtpEvent extends AuthEvent {
  final String phoneNumber;
  SendOtpEvent(this.phoneNumber);
}

class VerifyOtpEvent extends AuthEvent {
  final String otp;
  VerifyOtpEvent(this.otp);
}

class CompleteProfileEvent extends AuthEvent {
  final String firstName;
  final String lastName;
  final String? managerId;
  CompleteProfileEvent({
    required this.firstName,
    required this.lastName,
    this.managerId,
  });
}

class LogoutEvent extends AuthEvent {}

class CheckAuthEvent extends AuthEvent {}
