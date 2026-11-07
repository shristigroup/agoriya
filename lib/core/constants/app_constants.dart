class AppConstants {
  // Hive box names
  static const String userBox = 'user_box';
  static const String attendanceBox = 'attendance_box';
  static const String visitsBox = 'visits_box';
  static const String locationsBox = 'locations_box';
  static const String reportsBox = 'reports_box';
  static const String settingsBox = 'settings_box';

  // Owned EXCLUSIVELY by the location-tracking background isolate — never
  // opened by the main isolate. Hive does not support one box being opened
  // by two isolates concurrently (each isolate's box instance keeps its own
  // in-memory state, and concurrent writes from separate isolates can
  // corrupt the on-disk file). currentBatch/pendingSampleCount/
  // lastConfirmedPoint live here; HomeBloc only ever reads/writes them via
  // messages to the isolate (requestSnapshot/snapshot, batchSynced) — see
  // LocationTrackingService.
  static const String trackingCursorBox = 'tracking_cursor_box';

  // Hive keys
  static const String currentUserKey = 'current_user';
  static const String reportsCacheKey = 'reports_cache';

  // Today's tracking state — owned by HomeBloc/main isolate (locationsBox).
  static const String currentTrackingIdKey = 'current_tracking_id';
  static const String finalLocationsKey = 'final_locations';
  static const String finalLocationsDistanceKey = 'final_locations_distance';

  // Set once today's Tracking doc has hit Firestore's 1 MiB document size
  // limit — so the user is only notified once per session, not on every
  // subsequent failed sync. Cleared on a fresh punch-in, NOT on resume
  // (resuming continues the same, already-oversized doc).
  static const String locationSizeLimitHitKey = 'location_size_limit_hit';

  // Cursor-box keys — owned by the background isolate (trackingCursorBox).
  static const String currentBatchKey = 'current_batch';

  // Count of samples (movement or stationary) since the last confirmed sync.
  // NOT derivable from currentBatch.length, since a stationary run never
  // grows currentBatch. Lets HomeBloc detect "a flush was missed while the
  // app was dead" even when nothing but durationSeconds changed.
  static const String pendingSampleCountKey = 'pending_sample_count';

  // The last point HomeBloc confirmed as synced (position/timestamp/
  // durationSeconds) — the isolate's anchor for classifying the next sample
  // as stationary vs. movement once currentBatch is empty. Deliberately NOT
  // the full finalLocations array (that stays HomeBloc's own data) — the
  // isolate only ever needs this one point.
  static const String lastConfirmedPointKey = 'last_confirmed_point';

  // Day distance (km) as of the last confirmed sync — lets the isolate show
  // synced + unsynced distance in its notification without touching the main
  // isolate's locationsBox. Null until the first sync after a (re)start.
  static const String syncedDistanceKmKey = 'synced_distance_km';

  // Location tracking — tunable via functions/.env (see functions/.env.example).
  // Pass `--dart-define-from-file=functions/.env` to flutter run/build to
  // pick up non-default values.

  // Minutes between GPS samples.
  static const int locationSampleIntervalMinutes =
      int.fromEnvironment('LOCATION_SAMPLE_INTERVAL_MINUTE', defaultValue: 1);
  static const int locationSamplingSeconds = locationSampleIntervalMinutes * 60;

  // Minutes of samples collected before a batch auto-syncs. 9, not 10: a sync
  // sends [previous batch's last point, the point held back last time, then
  // this batch's new points minus the newest, which is held back again] to
  // OSRM, and OSRM accepts at most AppConstants.osrmMaxCoordinates (10) per
  // request — so 9 new samples fills one request exactly.
  static const int locationBatchMinutes =
      int.fromEnvironment('LOCATION_BATCH_MINUTES', defaultValue: 9);

  // Samples per batch = batch duration ÷ sample interval, rounded up (so the
  // batch never syncs later than locationBatchMinutes even when the interval
  // doesn't divide it evenly). `(a + b - 1) ~/ b` is integer-ceiling-division,
  // kept const-evaluable (no .ceil() calls, which aren't allowed in a const
  // context).
  static const int locationBatchSize =
      (locationBatchMinutes + locationSampleIntervalMinutes - 1) ~/
          locationSampleIntervalMinutes;

  // OSRM
  static const String osrmBaseUrl = 'https://router.project-osrm.org';
  static const String osrmMatchUrl = '$osrmBaseUrl/match/v1/driving';
  static const String osrmRouteUrl = '$osrmBaseUrl/route/v1/driving';

  // Firestore collections
  static const String usersCollection = 'Users';
  static const String trackingCollection = 'Tracking';
  static const String visitsCollection = 'Visits';
  static const String commentsCollection = 'Comments';
  static const String monthlyCollection = 'Monthly';
  static const String codesCollection = 'Codes';

  // Stationary detection thresholds
  static const int stationaryThresholdMeters = 50;

  // Stray-fix (spike) detection — see GpsOutlier.
  /// Both legs into and out of a candidate spike must be longer than this.
  static const double outlierMinLegMeters = 300;

  /// A point is a spike when the speed into it AND out of it are each at least
  /// this many times the speed of going straight from the point before it to
  /// the point after it (the path through it is that much faster than the
  /// route actually travelled).
  static const double outlierSpeedRatio = 3.0;

  // OSRM's public map-matching server rejects (HTTP 400 "TooBig") any trace
  // with more than this many coordinates. A request carries the previous
  // batch's last stored point plus up to (this - 1) new ones.
  static const int osrmMaxCoordinates = 10;

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
  static const String bgServiceChannel = 'trackfolks_location_channel';
  static const int bgNotificationId = 1001;
}
