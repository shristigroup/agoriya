# Agoriya v1.0 — Flutter Field Force Tracker

## Project Structure
```
lib/
├── main.dart                          # Entry point, nav key, deep-link router
├── core/
│   ├── constants/app_constants.dart   # Hive box names, OSRM URLs, Firestore paths
│   ├── constants/app_routes.dart      # Route name constants
│   ├── theme/app_theme.dart           # Design system (Sora font, green+amber palette)
│   └── utils/app_utils.dart           # Date/time/string helpers
├── data/
│   ├── models/                        # UserModel, AttendanceModel, VisitModel, LocationPoint
│   ├── local/local_storage_service.dart  # Hive JSON storage (all local data)
│   └── repositories/firestore_repository.dart  # All Firestore + Storage CRUD
├── services/
│   ├── location_tracking_service.dart # Background isolate, 5-min sampling, batch flush
│   ├── osrm_service.dart              # Road-snapping + distance via OSRM
│   └── notification_service.dart      # FCM + local notifications
└── features/
    ├── auth/                          # Phone OTP login, AuthBloc
    ├── home/                          # HomeBloc, HomeScreen, Track tab, Visits tab
    │   ├── bloc/
    │   ├── screens/                   # HomeScreen, PunchInCamera, PunchAnimations
    │   ├── track/track_tab.dart       # OSM map + polyline + OSRM road-snap
    │   └── visits/                    # CheckIn, VisitDetail, VisitEdit, VisitsTab
    └── reports/                       # ReportsScreen (hierarchy flatten + manager view)

functions/
├── index.js                           # Cloud Functions: FCM triggers + reports hierarchy
└── package.json

firestore.rules                        # Firestore security rules
storage.rules                          # Firebase Storage security rules
firebase.json                          # Firebase project config
firestore.indexes.json                 # Composite indexes
```

## Setup Instructions

### 1. Flutter dependencies
```bash
flutter pub get
```

### 2. Firebase project files
Add these files (download from Firebase Console):
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`

Run FlutterFire CLI to generate `lib/firebase_options.dart`:
```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

Then update `main.dart` Firebase.initializeApp call:
```dart
await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
```

### 3. Android — build.gradle additions
In `android/app/build.gradle`:
```gradle
android {
    compileSdkVersion 34
    defaultConfig {
        minSdkVersion 21        // required for background service
        targetSdkVersion 34
        multiDexEnabled true
    }
}
dependencies {
    implementation 'com.google.firebase:firebase-messaging:23.4.0'
}
```

In `android/build.gradle` (project level):
```gradle
dependencies {
    classpath 'com.google.gms:google-services:4.4.0'
}
```

### 4. iOS — Signing & Capabilities
In Xcode:
- Enable `Background Modes`: Location updates, Background fetch, Remote notifications
- Enable `Push Notifications` capability

### 5. Deploy Firebase rules and indexes
```bash
firebase deploy --only firestore:rules,firestore:indexes,storage
```

### 6. Deploy Cloud Functions
```bash
cd functions
npm install
cd ..
firebase deploy --only functions
```

## Key Design Decisions

| Feature | Approach |
|---|---|
| Local storage | Hive (JSON serialization, no size limit) |
| Maps | OpenStreetMap via flutter_map |
| Road-snapping | OSRM public API (free) |
| Distance calc | OSRM Route API, haversine fallback |
| Location tracking | flutter_background_service foreground isolate |
| State management | flutter_bloc (BLoC pattern) |
| Notifications | FCM via Cloud Functions Firestore triggers |
| Reports hierarchy | Denormalized JSON on User doc, updated by Cloud Function |
| Offline | All reads served from Hive first; writes require connectivity |

## Firestore Data Model
```
Users/<firstName-lastName-phone>
  uid, firstName, lastName, phoneNumber, managerId, reports{}, fcmToken
  
  Attendance/<yyyy-MM-dd>
    punchInTimestamp, punchOutTimestamp, punchInImage, distance, 
    punchOutLocation, customerVisitCount
    
  Locations/<yyyy-MM-dd>
    locations: [{ geoPoint, timestamp }]
    
  Visits/<clientName-location-date-time>
    clientName, location, checkinTimestamp, checkoutTimestamp,
    visitNotes, expenseAmount, billCopy
    
    Comments/<auto-id>
      userId, userName, text, timestamp
```

## Notes
- `google-services.json` and `GoogleService-Info.plist` are NOT included (add from your Firebase Console)
- `lib/firebase_options.dart` must be generated via `flutterfire configure`
- Storage paths: `<userId>/<date>-punch-in.<ext>` and `<userId>/<visitId>.<ext>`
