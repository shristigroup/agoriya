import 'package:flutter_test/flutter_test.dart';
import 'package:agoriya/data/models/user_model.dart';

UserModel _user(Map<String, dynamic> reports) => UserModel(
      id: 'boss-x-+1', uid: 'u', firstName: 'Boss', lastName: 'X', phoneNumber: '+1', reports: reports);

void main() {
  test('reportIds lists everyone below a user, at any depth', () {
    final u = _user({
      'a-+1': {'name': 'A', 'reports': {'b-+2': {'name': 'B', 'reports': {'c-+3': {'name': 'C', 'reports': {}}}}}},
      'd-+4': {'name': 'D', 'reports': {}},
    });
    expect(u.reportIds, {'a-+1', 'b-+2', 'c-+3', 'd-+4'});
  });

  test('reportIds is empty for someone with no team', () {
    expect(_user({}).reportIds, isEmpty);
  });
}
