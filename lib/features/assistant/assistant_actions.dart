import '../../data/models/shift_model.dart';
import 'assistant_data.dart';
import 'assistant_models.dart';
import 'place_search.dart';

/// "09:30", "9:30", "9" -> minutes after midnight; null if not a time.
int? parseHhmm(String? s) {
  if (s == null) return null;
  final m = RegExp(r'^\s*(\d{1,2})(?::(\d{2}))?\s*$').firstMatch(s);
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final min = int.tryParse(m.group(2) ?? '0') ?? 0;
  if (h > 23 || min > 59) return null;
  return h * 60 + min;
}

String fmtHhmm(int m) =>
    '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

/// The actions the assistant may ask for. Reads return data; writes return a
/// proposal that runs only when the owner taps Confirm. Places come only from
/// find_place (referred to by id), so the model cannot invent coordinates.
List<AssistantAction> buildAssistantActions(AssistantData data) {
  final places = <String, PlaceResult>{};
  var placeCounter = 0;

  Map<String, String> nameOf(List<OrgMember> members) =>
      {for (final m in members) m.id: m.name};

  /// Validates ids against the org's members. Returns (ids, error).
  Future<(List<String>, String?)> checkUsers(Object? raw) async {
    final ids = [for (final v in (raw as List? ?? const [])) v.toString()];
    final names = nameOf(await data.members());
    final unknown = ids.where((i) => !names.containsKey(i)).toList();
    if (unknown.isNotEmpty) {
      return (const <String>[], 'Unknown member id(s): ${unknown.join(', ')}. Use list_members.');
    }
    return (ids.toSet().toList(), null);
  }

  ShiftLocation? place(String? id) {
    final p = id == null ? null : places[id];
    return p == null
        ? null
        : ShiftLocation(lat: p.lat, lng: p.lng, name: p.name, address: p.address);
  }

  String placeLine(ShiftLocation? l) =>
      l == null ? 'none' : '${l.name}${l.address != null ? ' (${l.address})' : ''}';

  Map<String, dynamic> shiftJson(ShiftModel s, Map<String, String> names) => {
        'id': s.id,
        'name': s.name,
        if (s.hasTimes) 'time': s.timeLabel,
        if (s.inLocation != null) 'punchInPlace': s.inLocation!.name,
        'punchOutPlace': s.outLocation?.name ?? (s.inLocation != null ? 'same as punch-in' : null),
        'radiusM': s.radiusM,
        'peopleCount': s.userIds.length,
        'people': [for (final u in s.userIds.take(40)) names[u] ?? u],
      };

  String? timeProblem(ShiftModel s) {
    if (s.startMinute != null &&
        s.endMinute != null &&
        s.endMinute! <= s.startMinute! &&
        !s.endNextDay) {
      return 'The end time is not after the start time. If the shift ends the next '
          'day, set endsNextDay to true.';
    }
    return null;
  }

  ParamSpec optStr(String d) => ParamSpec(ParamType.string, d, required: false);

  return [
    AssistantAction(
      name: 'list_members',
      description: 'List the people in the organisation: id, name and the shift '
          'each is on (if any). Use it to find a person by name.',
      run: (_) async {
        final members = await data.members();
        final shifts = await data.shifts();
        final onShift = <String, String>{
          for (final s in shifts) for (final u in s.userIds) u: s.name
        };
        return ActionOutcome.data({
          'count': members.length,
          'members': [
            for (final m in members.take(150))
              {'id': m.id, 'name': m.name, if (onShift[m.id] != null) 'shift': onShift[m.id]}
          ],
        });
      },
    ),
    AssistantAction(
      name: 'list_shifts',
      description: 'List all shifts with their times, places and the people on each.',
      run: (_) async {
        final names = nameOf(await data.members());
        final shifts = await data.shifts();
        return ActionOutcome.data(
            {'count': shifts.length, 'shifts': [for (final s in shifts) shiftJson(s, names)]});
      },
    ),
    AssistantAction(
      name: 'members_without_shift',
      description: 'The people in the organisation who are not on any shift.',
      run: (_) async {
        final members = await data.members();
        final onShift = {for (final s in await data.shifts()) ...s.userIds};
        final without = [for (final m in members) if (!onShift.contains(m.id)) m];
        return ActionOutcome.data({
          'totalMembers': members.length,
          'withoutShiftCount': without.length,
          'withoutShift': [for (final m in without.take(150)) {'id': m.id, 'name': m.name}],
        });
      },
    ),
    AssistantAction(
      name: 'find_place',
      description: 'Search for a place by name (a mall, office, address), near the '
          "owner's position. Returns candidates, each with a placeId. Use a placeId "
          'in create_shift or update_shift.',
      params: {'query': const ParamSpec(ParamType.string, 'What to search for.')},
      run: (a) async {
        final q = (a['query'] ?? '').toString().trim();
        if (q.isEmpty) return const ActionOutcome.error('query is required');
        final found = await data.searchPlaces(q);
        if (found.isEmpty) {
          return const ActionOutcome.data({
            'candidates': [],
            'note': 'No match. Ask the owner for a more specific name or an address.'
          });
        }
        return ActionOutcome.data({
          'candidates': [
            for (final p in found)
              () {
                final id = 'p${++placeCounter}';
                places[id] = p;
                return {'placeId': id, 'name': p.name, 'address': p.address};
              }()
          ],
        });
      },
    ),
    AssistantAction(
      name: 'create_shift',
      description: 'Propose a new shift. All fields except name are optional: a '
          'shift may have times, places, or both, and people to put on it.',
      params: {
        'name': const ParamSpec(ParamType.string, 'Shift name, for example Morning.'),
        'start': optStr('Start time, 24-hour HH:MM, India time.'),
        'end': optStr('End time, 24-hour HH:MM, India time.'),
        'endsNextDay': const ParamSpec(ParamType.boolean,
            'True if the shift ends the day after it starts (a night shift).',
            required: false),
        'inPlaceId': optStr('placeId from find_place for the punch-in place.'),
        'outPlaceId': optStr('placeId from find_place if punch-out is at a different '
            'place. Leave empty for the same place.'),
        'radiusM': const ParamSpec(ParamType.integer,
            'How far from the place counts as being there, in metres (default 100).',
            required: false),
        'userIds': const ParamSpec(ParamType.stringList,
            'Member ids (from list_members) to put on this shift.',
            required: false),
      },
      run: (a) async {
        final name = (a['name'] ?? '').toString().trim();
        if (name.isEmpty) return const ActionOutcome.error('name is required');
        final existing = await data.shifts();
        if (existing.any((s) => s.name.toLowerCase() == name.toLowerCase())) {
          return ActionOutcome.error('A shift called "$name" already exists. '
              'Use update_shift, or ask for a different name.');
        }
        final start = parseHhmm(a['start']?.toString());
        final end = parseHhmm(a['end']?.toString());
        if (a['start'] != null && start == null) {
          return const ActionOutcome.error('start must be HH:MM in 24-hour form.');
        }
        if (a['end'] != null && end == null) {
          return const ActionOutcome.error('end must be HH:MM in 24-hour form.');
        }
        final inLoc = place(a['inPlaceId']?.toString());
        final outLoc = place(a['outPlaceId']?.toString());
        if (a['inPlaceId'] != null && inLoc == null) {
          return const ActionOutcome.error('Unknown placeId. Call find_place first.');
        }
        if (a['outPlaceId'] != null && outLoc == null) {
          return const ActionOutcome.error('Unknown placeId. Call find_place first.');
        }
        final radius = (a['radiusM'] as num?)?.toInt() ?? ShiftModel.defaultRadiusM;
        if (radius < 20 || radius > 5000) {
          return const ActionOutcome.error('radiusM must be between 20 and 5000.');
        }
        final (ids, err) = await checkUsers(a['userIds']);
        if (err != null) return ActionOutcome.error(err);

        final shift = ShiftModel(
          id: '',
          name: name,
          startMinute: start,
          endMinute: end,
          endNextDay: a['endsNextDay'] == true,
          inLocation: inLoc,
          outLocation: outLoc,
          radiusM: radius,
        );
        final problem = timeProblem(shift);
        if (problem != null) return ActionOutcome.error(problem);
        if (!shift.hasTimes && inLoc == null) {
          return const ActionOutcome.error(
              'A shift needs times, a place, or both. Ask the owner which.');
        }

        final members = nameOf(await data.members());
        final moves = <String>[];
        for (final s in existing) {
          for (final u in ids.where(s.userIds.contains)) {
            moves.add('${members[u]} (from ${s.name})');
          }
        }
        return ActionOutcome.proposal(Proposal(
          title: 'Create shift "$name"',
          lines: [
            if (shift.hasTimes) 'Time: ${shift.timeLabel}' else 'No times, so no reminders',
            'Punch-in place: ${placeLine(inLoc)}',
            if (inLoc != null)
              'Punch-out place: ${outLoc == null ? 'same place' : placeLine(outLoc)}',
            if (inLoc != null) 'Counts as there within $radius m',
            'People: ${ids.isEmpty ? 'none yet' : ids.map((i) => members[i]).join(', ')}',
            if (moves.isNotEmpty) 'Moves from another shift: ${moves.join(', ')}',
          ],
          apply: () async {
            final id = await data.saveShift(shift);
            if (ids.isNotEmpty) await data.assignUsers(id, ids);
            return 'Created "$name"${ids.isEmpty ? '' : ' with ${ids.length} people'}.';
          },
        ));
      },
    ),
    AssistantAction(
      name: 'update_shift',
      description: "Propose changes to an existing shift's name, times or places. "
          'Only pass what changes.',
      params: {
        'shiftId': const ParamSpec(ParamType.string, 'Shift id from list_shifts.'),
        'name': optStr('New name.'),
        'start': optStr('New start time, 24-hour HH:MM.'),
        'end': optStr('New end time, 24-hour HH:MM.'),
        'endsNextDay': const ParamSpec(ParamType.boolean,
            'Whether the shift ends the next day.',
            required: false),
        'clearTimes': const ParamSpec(ParamType.boolean,
            'True to remove the times (the shift becomes place-only).',
            required: false),
        'inPlaceId': optStr('placeId from find_place for the new punch-in place.'),
        'outPlaceId': optStr('placeId from find_place for a different punch-out place.'),
        'sameOutPlace': const ParamSpec(ParamType.boolean,
            'True to make punch-out the same place as punch-in.',
            required: false),
        'radiusM': const ParamSpec(ParamType.integer, 'New radius in metres.',
            required: false),
      },
      run: (a) async {
        final shifts = await data.shifts();
        final current = shifts.where((s) => s.id == a['shiftId']).firstOrNull;
        if (current == null) {
          return const ActionOutcome.error('No such shift. Use list_shifts.');
        }
        final start = a['start'] == null ? null : parseHhmm(a['start'].toString());
        final end = a['end'] == null ? null : parseHhmm(a['end'].toString());
        if (a['start'] != null && start == null || a['end'] != null && end == null) {
          return const ActionOutcome.error('Times must be HH:MM in 24-hour form.');
        }
        final inLoc = place(a['inPlaceId']?.toString());
        final outLoc = place(a['outPlaceId']?.toString());
        if (a['inPlaceId'] != null && inLoc == null ||
            a['outPlaceId'] != null && outLoc == null) {
          return const ActionOutcome.error('Unknown placeId. Call find_place first.');
        }
        final radius = (a['radiusM'] as num?)?.toInt();
        if (radius != null && (radius < 20 || radius > 5000)) {
          return const ActionOutcome.error('radiusM must be between 20 and 5000.');
        }
        final newName = a['name']?.toString().trim();
        if (newName != null &&
            newName.isNotEmpty &&
            shifts.any((s) => s.id != current.id && s.name.toLowerCase() == newName.toLowerCase())) {
          return ActionOutcome.error('A shift called "$newName" already exists.');
        }
        final updated = current.copyWith(
          name: (newName == null || newName.isEmpty) ? null : newName,
          startMinute: start,
          endMinute: end,
          endNextDay: a['endsNextDay'] as bool?,
          inLocation: inLoc,
          outLocation: outLoc,
          radiusM: radius,
          clearTimes: a['clearTimes'] == true,
          clearOutLocation: a['sameOutPlace'] == true,
        );
        final problem = timeProblem(updated);
        if (problem != null) return ActionOutcome.error(problem);
        return ActionOutcome.proposal(Proposal(
          title: 'Update shift "${current.name}"',
          lines: [
            if (updated.name != current.name) 'Name: ${current.name} → ${updated.name}',
            if (updated.timeLabel != current.timeLabel)
              'Time: ${current.timeLabel.isEmpty ? 'none' : current.timeLabel} → '
                  '${updated.timeLabel.isEmpty ? 'none' : updated.timeLabel}',
            if (updated.inLocation?.name != current.inLocation?.name)
              'Punch-in place: ${placeLine(updated.inLocation)}',
            if (updated.outLocation?.name != current.outLocation?.name)
              'Punch-out place: ${updated.outLocation == null ? 'same as punch-in' : placeLine(updated.outLocation)}',
            if (updated.radiusM != current.radiusM) 'Radius: ${updated.radiusM} m',
            '${current.userIds.length} people stay on the shift',
          ],
          apply: () async {
            await data.saveShift(updated);
            return 'Updated "${updated.name}".';
          },
        ));
      },
    ),
    AssistantAction(
      name: 'delete_shift',
      description: 'Propose deleting a shift. The people on it become unassigned.',
      params: {'shiftId': const ParamSpec(ParamType.string, 'Shift id from list_shifts.')},
      run: (a) async {
        final s = (await data.shifts()).where((x) => x.id == a['shiftId']).firstOrNull;
        if (s == null) return const ActionOutcome.error('No such shift. Use list_shifts.');
        return ActionOutcome.proposal(Proposal(
          title: 'Delete shift "${s.name}"',
          lines: ['${s.userIds.length} people will no longer be on a shift'],
          apply: () async {
            await data.deleteShift(s.id);
            return 'Deleted "${s.name}".';
          },
        ));
      },
    ),
    AssistantAction(
      name: 'assign_users',
      description: 'Propose putting people on a shift. A person is on at most one '
          'shift, so anyone already on another shift is moved.',
      params: {
        'shiftId': const ParamSpec(ParamType.string, 'Shift id from list_shifts.'),
        'userIds': const ParamSpec(ParamType.stringList, 'Member ids from list_members.'),
      },
      run: (a) async {
        final shifts = await data.shifts();
        final target = shifts.where((x) => x.id == a['shiftId']).firstOrNull;
        if (target == null) return const ActionOutcome.error('No such shift. Use list_shifts.');
        final (ids, err) = await checkUsers(a['userIds']);
        if (err != null) return ActionOutcome.error(err);
        if (ids.isEmpty) return const ActionOutcome.error('userIds is empty.');
        final names = nameOf(await data.members());
        final already = ids.where(target.userIds.contains).toList();
        final toAdd = ids.where((i) => !target.userIds.contains(i)).toList();
        if (toAdd.isEmpty) {
          return ActionOutcome.data({'note': 'They are all on "${target.name}" already.'});
        }
        final moves = <String>[];
        for (final s in shifts.where((x) => x.id != target.id)) {
          for (final u in toAdd.where(s.userIds.contains)) {
            moves.add('${names[u]} (from ${s.name})');
          }
        }
        return ActionOutcome.proposal(Proposal(
          title: 'Put ${toAdd.length} ${toAdd.length == 1 ? 'person' : 'people'} on "${target.name}"',
          lines: [
            toAdd.map((i) => names[i]).join(', '),
            if (moves.isNotEmpty) 'Moves from another shift: ${moves.join(', ')}',
            if (already.isNotEmpty) 'Already on it: ${already.map((i) => names[i]).join(', ')}',
          ],
          apply: () async {
            await data.assignUsers(target.id, toAdd);
            return 'Added ${toAdd.length} to "${target.name}".';
          },
        ));
      },
    ),
    AssistantAction(
      name: 'remove_users_from_shift',
      description: 'Propose taking people off a shift (they end up on no shift).',
      params: {
        'shiftId': const ParamSpec(ParamType.string, 'Shift id from list_shifts.'),
        'userIds': const ParamSpec(ParamType.stringList, 'Member ids from list_members.'),
      },
      run: (a) async {
        final target = (await data.shifts()).where((x) => x.id == a['shiftId']).firstOrNull;
        if (target == null) return const ActionOutcome.error('No such shift. Use list_shifts.');
        final (ids, err) = await checkUsers(a['userIds']);
        if (err != null) return ActionOutcome.error(err);
        final names = nameOf(await data.members());
        final on = ids.where(target.userIds.contains).toList();
        if (on.isEmpty) {
          return ActionOutcome.data({'note': 'None of them are on "${target.name}".'});
        }
        return ActionOutcome.proposal(Proposal(
          title: 'Take ${on.length} off "${target.name}"',
          lines: [on.map((i) => names[i]).join(', ')],
          apply: () async {
            await data.removeUsers(target.id, on);
            return 'Removed ${on.length} from "${target.name}".';
          },
        ));
      },
    ),
    AssistantAction(
      name: 'team_today',
      description: "Today's status of the people who report to the owner: punched in, "
          'punched out, or not punched in.',
      run: (_) async => ActionOutcome.data({'team': await data.teamToday()}),
    ),
    AssistantAction(
      name: 'member_history',
      description: "One member's sessions in a month, per day: times, hours, distance, "
          'visits, auto punch-outs and late / far-from-place flags. Only works for '
          'people who report to the owner.',
      params: {
        'userId': const ParamSpec(ParamType.string, 'Member id from list_members.'),
        'month': ParamSpec(ParamType.string,
            'Month as yyyy-MM. Defaults to the current month.',
            required: false),
      },
      run: (a) async {
        final month = (a['month'] ?? '').toString();
        final key = RegExp(r'^\d{4}-\d{2}$').hasMatch(month) ? month : null;
        final id = (a['userId'] ?? '').toString();
        if ((await data.members()).every((m) => m.id != id)) {
          return const ActionOutcome.error('Unknown member id. Use list_members.');
        }
        try {
          final days = await data.memberHistory(
              id, key ?? DateTime.now().toIso8601String().substring(0, 7));
          return ActionOutcome.data({'days': days, 'count': days.length});
        } catch (_) {
          return const ActionOutcome.error(
              "I can't see that person's history. They may not report to you.");
        }
      },
    ),
  ];
}
