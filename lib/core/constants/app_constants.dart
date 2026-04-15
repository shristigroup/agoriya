class AppConstants {
  // Hive box names
  static const String userBox = 'user_box';
  static const String attendanceBox = 'attendance_box';
  static const String visitsBox = 'visits_box';
  static const String locationsBox = 'locations_box';
  static const String reportsBox = 'reports_box';
  static const String settingsBox = 'settings_box';

  // Hive keys
  static const String currentUserKey = 'current_user';
  static const String reportsCacheKey = 'reports_cache';

  // Today's tracking state — two arrays + two distance values
  static const String finalLocationsKey = 'final_locations';
  static const String currentBatchKey = 'current_batch';
  static const String finalLocationsDistanceKey = 'final_locations_distance';
  static const String currentBatchDistanceKey = 'current_batch_distance';

  // Location tracking
  static const int locationSamplingSeconds = 60; // sample every 1 min
  static const int locationBatchSize = 15;        // signal HomeBloc every 15 points (~15 min)

  // OSRM
  static const String osrmBaseUrl = 'https://router.project-osrm.org';
  static const String osrmMatchUrl = '$osrmBaseUrl/match/v1/driving';
  static const String osrmRouteUrl = '$osrmBaseUrl/route/v1/driving';

  // Firestore collections
  static const String usersCollection = 'Users';
  static const String attendanceCollection = 'Attendance';
  static const String locationsCollection = 'Locations';
  static const String visitsCollection = 'Visits';
  static const String commentsCollection = 'Comments';
  static const String monthlyCollection = 'Monthly';

  // Cache key prefix for monthly summaries (used in settingsBox)
  static const String monthlyCachePrefix = 'monthly_';

  // Storage paths
  static String punchInImagePath(String userId, String date, String ext) =>
      '$userId/$date-punch-in.$ext';
  static String billCopyPath(String userId, String visitId, String ext) =>
      '$userId/$visitId.$ext';

  // Cached app version — used by DataManager to detect reinstall / update
  // and re-seed today's data from Firestore into Hive.
  static const String cacheVersionKey = 'cache_version';

  // Background service
  static const String bgServiceChannel = 'agoriya_location_channel';
  static const int bgNotificationId = 1001;
}
