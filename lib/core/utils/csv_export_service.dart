import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/models/tracking_model.dart';
import '../../data/repositories/firestore_repository.dart';

class CsvExportService {
  static final _timeFmt = DateFormat('HH:mm');

  /// Fetches all tracking for [members] in the given [monthKey] (yyyy-MM),
  /// builds a CSV, writes it to the temp directory, and opens the share sheet.
  static Future<void> exportMonthlyReport(
    List<CsvMemberRef> members,
    String monthKey,
  ) async {
    final repo = FirestoreRepository();

    // Fetch tracking for all members in parallel.
    final results = await Future.wait(
      members.map((m) async {
        List<TrackingModel> sessions = [];
        try {
          sessions = await repo.getTrackingForMonth(m.userId, monthKey);
        } catch (_) {}
        return (member: m, sessions: sessions);
      }),
    );

    // Build CSV rows.
    final rows = <_CsvRow>[];
    for (final r in results) {
      for (final t in r.sessions) {
        rows.add(_CsvRow(
          name: r.member.name,
          date: t.date,
          punchIn: t.startTime,
          punchOut: t.stopTime,
          duration: t.isStopped ? t.attendanceDuration : null,
          distanceKm: t.distance,
        ));
      }
    }

    // Sort by name then date.
    rows.sort((a, b) {
      final n = a.name.compareTo(b.name);
      return n != 0 ? n : a.date.compareTo(b.date);
    });

    // Build CSV string.
    final buf = StringBuffer();
    buf.writeln('Name,Date,Punch In,Punch Out,Total Hours,Distance (km)');
    for (final row in rows) {
      final punchOut = row.punchOut != null ? _timeFmt.format(row.punchOut!) : '';
      final hours = row.duration != null ? _formatDuration(row.duration!) : '';
      final km = row.distanceKm.toStringAsFixed(1);
      buf.writeln('${_escape(row.name)},${row.date},${_timeFmt.format(row.punchIn)},$punchOut,$hours,$km');
    }

    // Write to temp file.
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/trackfolks_$monthKey.csv');
    await file.writeAsString(buf.toString());

    // Share.
    final label = DateFormat('MMMM yyyy').format(DateTime.parse('$monthKey-01'));
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'text/csv')],
      subject: 'TrackFolks Report – $label',
    ));
  }

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h == 0) return '${m}m';
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  /// Wraps a value in quotes if it contains a comma or quote, escaping inner quotes.
  static String _escape(String value) {
    if (value.contains(',') || value.contains('"')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}

/// Lightweight reference passed from the Reports screen.
class CsvMemberRef {
  final String userId;
  final String name;
  const CsvMemberRef({required this.userId, required this.name});
}

class _CsvRow {
  final String name;
  final String date;
  final DateTime punchIn;
  final DateTime? punchOut;
  final Duration? duration;
  final double distanceKm;
  const _CsvRow({
    required this.name,
    required this.date,
    required this.punchIn,
    this.punchOut,
    this.duration,
    required this.distanceKm,
  });
}
