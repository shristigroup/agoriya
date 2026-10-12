import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// What an export run produced, so the UI can say when it is incomplete
/// instead of silently handing over a partial file.
class CsvExportSummary {
  final int rowCount;
  final int memberCount;
  final int failedMembers;
  final int skippedDocs;
  const CsvExportSummary({
    required this.rowCount,
    required this.memberCount,
    required this.failedMembers,
    required this.skippedDocs,
  });

  bool get isComplete => failedMembers == 0 && skippedDocs == 0;
}

class CsvExportService {
  static const _url =
      'https://asia-south1-agoriya-app.cloudfunctions.net/exportMonthlyReport';

  /// Asks the exportMonthlyReport Cloud Function (see functions/index.js) to
  /// build the day-wise CSV for the caller's whole team for [monthKey]
  /// (yyyy-MM), saves it to the temp directory and opens the share sheet.
  /// The server reads the data and logs every run.
  static Future<CsvExportSummary> exportMonthlyReport(String monthKey) async {
    final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (idToken == null) throw Exception('Not signed in');

    final response = await http
        .post(
          Uri.parse(_url),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken',
          },
          body: jsonEncode({
            'monthKey': monthKey,
            // So the server draws month/day boundaries in the user's timezone.
            'tzOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
          }),
        )
        .timeout(const Duration(seconds: 75));

    if (response.statusCode != 200) {
      throw Exception('Export failed (${response.statusCode})');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${data['filename'] ?? 'trackfolks_$monthKey.csv'}');
    await file.writeAsString(data['csv'] as String);

    final label = DateFormat('MMMM yyyy').format(DateTime.parse('$monthKey-01'));
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'text/csv')],
      subject: 'TrackFolks Report – $label',
    ));

    return CsvExportSummary(
      rowCount: (data['rowCount'] as num?)?.toInt() ?? 0,
      memberCount: (data['memberCount'] as num?)?.toInt() ?? 0,
      failedMembers: (data['failedMembers'] as num?)?.toInt() ?? 0,
      skippedDocs: (data['skippedDocs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Lightweight reference passed from the Reports screen (used only to show how
/// many members the export covers; the server works out the real list).
class CsvMemberRef {
  final String userId;
  final String name;
  const CsvMemberRef({required this.userId, required this.name});
}
