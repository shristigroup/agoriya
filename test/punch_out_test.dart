import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agoriya/services/network_check.dart';
import 'package:agoriya/services/punch_out_errors.dart';

void main() {
  group('NetworkCheck.isOnline', () {
    test('true when the host resolves', () async {
      final ok = await NetworkCheck.isOnline(
        lookup: (_) async => [InternetAddress('142.250.1.1')],
      );
      expect(ok, isTrue);
    });

    test('false when the lookup fails both times', () async {
      var calls = 0;
      final ok = await NetworkCheck.isOnline(
        lookup: (_) async {
          calls++;
          throw const SocketException('no route to host');
        },
      );
      expect(ok, isFalse);
      expect(calls, 2);
    });

    test('a single failed lookup is retried', () async {
      var calls = 0;
      final ok = await NetworkCheck.isOnline(
        lookup: (_) async {
          calls++;
          if (calls == 1) throw const SocketException('flaky');
          return [InternetAddress('142.250.1.1')];
        },
      );
      expect(ok, isTrue);
      expect(calls, 2);
    });

    test('false when the lookup never answers', () async {
      final ok = await NetworkCheck.isOnline(
        timeout: const Duration(milliseconds: 20),
        lookup: (_) => Completer<List<InternetAddress>>().future,
      );
      expect(ok, isFalse);
    });

    test('false when the lookup returns nothing', () async {
      final ok = await NetworkCheck.isOnline(lookup: (_) async => []);
      expect(ok, isFalse);
    });
  });

  group('PunchOutMessages.forError', () {
    test('timeouts and socket errors say the server was unreachable', () {
      expect(PunchOutMessages.forError(TimeoutException('x')),
          PunchOutMessages.unreachable);
      expect(PunchOutMessages.forError(const SocketException('x')),
          PunchOutMessages.unreachable);
    });

    test('Firestore availability errors say the server was unreachable', () {
      for (final code in ['unavailable', 'deadline-exceeded']) {
        expect(
            PunchOutMessages.forError(
                FirebaseException(plugin: 'cloud_firestore', code: code)),
            PunchOutMessages.unreachable,
            reason: code);
      }
    });

    test('anything else gets the generic message', () {
      expect(PunchOutMessages.forError(StateError('boom')),
          PunchOutMessages.generic);
      expect(
          PunchOutMessages.forError(FirebaseException(
              plugin: 'cloud_firestore', code: 'permission-denied')),
          PunchOutMessages.generic);
    });

    test('every message tells the user they are still punched in', () {
      for (final m in [
        PunchOutMessages.offline,
        PunchOutMessages.unreachable,
        PunchOutMessages.generic,
      ]) {
        expect(m, contains('still punched in'));
      }
    });
  });
}
