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
  final String? orgCode; // null = generate a new org for this user
  CompleteProfileEvent({
    required this.firstName,
    required this.lastName,
    this.managerId,
    this.orgCode,
  });
}

class LogoutEvent extends AuthEvent {}

class CheckAuthEvent extends AuthEvent {}
