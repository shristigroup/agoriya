import 'package:flutter_test/flutter_test.dart';
import 'package:agoriya/data/models/shift_model.dart';
import 'package:agoriya/data/repositories/shift_repository.dart';

void main() {
  const morning = ShiftModel(id: 'm', name: 'Morning', userIds: ['ravi', 'sunita']);
  const evening = ShiftModel(id: 'e', name: 'Evening', userIds: ['amit']);
  const night = ShiftModel(id: 'n', name: 'Night');

  test('moving people takes each off the shift they were on, and only that one', () {
    final plan = planAssignRemovals([morning, evening, night], 'n', ['ravi', 'amit', 'new']);
    expect(plan, {
      'm': ['ravi'],
      'e': ['amit'],
    });
  });

  test('people already on the target shift, and people on no shift, need no removal', () {
    expect(planAssignRemovals([morning, evening], 'm', ['ravi', 'sunita']), isEmpty);
    expect(planAssignRemovals([morning, evening], 'e', ['stranger']), isEmpty);
  });

  test('the target shift is never in the removals', () {
    final plan = planAssignRemovals([morning, evening], 'm', ['amit', 'ravi']);
    expect(plan.keys, ['e']);
  });
}
