import 'package:flutter_test/flutter_test.dart';
import 'package:agoriya/data/models/shift_model.dart';
import 'package:agoriya/features/assistant/assistant_actions.dart';
import 'package:agoriya/features/assistant/assistant_data.dart';
import 'package:agoriya/features/assistant/assistant_models.dart';
import 'package:agoriya/features/assistant/place_search.dart';

class FakeData implements AssistantData {
  final people = const [
    OrgMember('ravi', 'Ravi Kumar'),
    OrgMember('sunita', 'Sunita Rao'),
    OrgMember('amit', 'Amit Shah'),
  ];
  List<ShiftModel> shiftList = [
    const ShiftModel(id: 's1', name: 'Morning', startMinute: 540, endMinute: 1080, userIds: ['ravi']),
    const ShiftModel(id: 's2', name: 'Evening'),
  ];
  final List<String> calls = [];

  @override
  Future<List<OrgMember>> members() async => people;
  @override
  Future<List<ShiftModel>> shifts() async => shiftList;
  @override
  Future<String> saveShift(ShiftModel s) async {
    calls.add('save:${s.name}');
    return 'new1';
  }

  @override
  Future<void> deleteShift(String id) async => calls.add('delete:$id');
  @override
  Future<void> assignUsers(String shiftId, List<String> ids) async =>
      calls.add('assign:$shiftId:${ids.join(',')}');
  @override
  Future<void> removeUsers(String shiftId, List<String> ids) async =>
      calls.add('remove:$shiftId:${ids.join(',')}');
  @override
  Future<List<PlaceResult>> searchPlaces(String q) async => const [
        PlaceResult(name: 'Reliance Mall', address: 'Raipur', lat: 21.25, lng: 81.63)
      ];
  @override
  Future<List<Map<String, dynamic>>> teamToday() async => [];
  @override
  Future<List<Map<String, dynamic>>> memberHistory(String u, String m) async => [];
}

Future<ActionOutcome> run(List<AssistantAction> a, String name, Map<String, dynamic> args) =>
    a.firstWhere((x) => x.name == name).run(args);

void main() {
  late FakeData data;
  late List<AssistantAction> actions;
  setUp(() {
    data = FakeData();
    actions = buildAssistantActions(data);
  });

  test('members_without_shift lists exactly the people on no shift', () async {
    final out = await run(actions, 'members_without_shift', {});
    expect(out.data!['withoutShiftCount'], 2);
    expect((out.data!['withoutShift'] as List).map((m) => m['name']),
        ['Sunita Rao', 'Amit Shah']);
  });

  test('create_shift only proposes; Confirm saves, then assigns', () async {
    final out = await run(actions, 'create_shift',
        {'name': 'Late', 'start': '14:00', 'end': '22:00', 'userIds': ['sunita']});
    expect(data.calls, isEmpty);
    await out.proposal!.apply();
    expect(data.calls, ['save:Late', 'assign:new1:sunita']);
  });

  test('a night shift needs endsNextDay', () async {
    final bad = await run(actions, 'create_shift', {'name': 'Night', 'start': '22:00', 'end': '06:00'});
    expect(bad.error, contains('endsNextDay'));
    final ok = await run(actions, 'create_shift',
        {'name': 'Night', 'start': '22:00', 'end': '06:00', 'endsNextDay': true});
    expect(ok.proposal, isNotNull);
  });

  test('a place must come from find_place; made-up ids and unknown members are refused', () async {
    expect((await run(actions, 'create_shift', {'name': 'X', 'inPlaceId': 'p99'})).error,
        contains('find_place'));
    expect((await run(actions, 'create_shift', {'name': 'X', 'start': '9:00', 'userIds': ['ghost']})).error,
        contains('Unknown member'));
    final found = await run(actions, 'find_place', {'query': 'mall'});
    final id = (found.data!['candidates'] as List).first['placeId'] as String;
    final out = await run(actions, 'create_shift', {'name': 'Mall', 'inPlaceId': id});
    expect(out.proposal!.lines.join('\n'), contains('Reliance Mall'));
  });

  test('assign_users says who moves from which shift, and applies on Confirm', () async {
    final out = await run(actions, 'assign_users', {'shiftId': 's2', 'userIds': ['ravi', 'sunita']});
    expect(out.proposal!.lines.join('\n'), contains('Ravi Kumar (from Morning)'));
    await out.proposal!.apply();
    expect(data.calls, ['assign:s2:ravi,sunita']);
  });
}
