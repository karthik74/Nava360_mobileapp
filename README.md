# HRMS Mobile (Flutter)

Companion mobile app for the HRMS backend in `../hrms-backend`. Targets employees and managers (ADMIN / HR / MANAGER):

- **Attendance** — GPS-aware punch in/out, monthly history.
- **Leaves** — annual balances, list own requests, submit new ones.
- **My Team** — pending leave requests of direct reports, approve/reject (ADMIN/HR).

Built with Flutter 3.19+, Riverpod, go_router, Dio, flutter_secure_storage, geolocator.

## 1. First-time setup

The `lib/` files are checked in but the Flutter platform scaffolds (Android/iOS/Web) are not. Generate them once:

```bash
cd hrms-mobile
flutter create --org com.hrms --project-name hrms_mobile .
flutter pub get
```

`flutter create .` is safe — it adds missing platform folders without touching files that already exist.

## 2. Run against the backend

The backend must be reachable from the device/emulator. Default base URL (`lib/core/env.dart`) is `http://10.0.2.2:8080`, which works for the **Android emulator** talking to a Spring Boot app on the host machine.

| Where you're running          | Base URL                       |
| ----------------------------- | ------------------------------ |
| Android emulator              | `http://10.0.2.2:8080`         |
| iOS simulator                 | `http://localhost:8080`        |
| Physical device on Wi-Fi      | `http://<your-LAN-IP>:8080`    |

Override at run time with `--dart-define`:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8080
```

## 3. Android permissions

Geolocation needs runtime permission. Add these inside `<manifest>` in `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
```

If you target Android 9+ and the backend is plain HTTP (not HTTPS), also enable cleartext for development:

```xml
<application
    android:usesCleartextTraffic="true"
    ...>
```

## 4. iOS permissions

Add to `ios/Runner/Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Required to record your attendance check-in/out location.</string>
```

For dev against HTTP, also add (under the existing `<dict>` in `Info.plist`):

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsArbitraryLoads</key>
  <true/>
</dict>
```

## 5. Layout

```
lib/
├── app.dart                       # MaterialApp + go_router setup
├── main.dart
├── core/
│   ├── api_client.dart            # Dio + JWT interceptor + ApiException
│   ├── env.dart                   # API base URL (--dart-define overrides)
│   └── secure_storage.dart        # Keychain / EncryptedSharedPreferences
└── features/
    ├── auth/
    │   ├── auth_controller.dart   # Riverpod StateNotifier for session
    │   ├── auth_models.dart       # AuthUser, LoginRequest
    │   ├── auth_repository.dart
    │   └── login_screen.dart
    ├── home/
    │   └── home_shell.dart        # Bottom-nav scaffold
    ├── attendance/
    │   ├── attendance_models.dart
    │   ├── attendance_repository.dart
    │   └── attendance_screen.dart # Punch in/out + monthly history
    ├── leaves/
    │   ├── leave_models.dart
    │   ├── leave_repository.dart
    │   └── leaves_screen.dart     # Balances + own list + request sheet
    └── team/
        └── team_screen.dart       # Pending leaves of direct reports
```

## 6. Backend endpoints used

| Feature        | Method     | Path                                  |
| -------------- | ---------- | ------------------------------------- |
| Login          | `POST`     | `/api/auth/login`                     |
| Punch in       | `POST`     | `/api/attendance/check-in/{id}`       |
| Punch out      | `POST`     | `/api/attendance/check-out/{id}`      |
| My attendance  | `GET`      | `/api/attendance/employee/{id}`       |
| My leaves      | `GET`      | `/api/leaves/employee/{id}`           |
| My balance     | `GET`      | `/api/leaves/balance/{id}`            |
| Apply leave    | `POST`     | `/api/leaves`                         |
| Team leaves    | `GET`      | `/api/leaves/team`                    |
| Review leave   | `PATCH`    | `/api/leaves/{id}/review`             |

## 7. Location tracking after punch-in

When an employee successfully checks in, the app starts an adaptive GPS tracker
that POSTs samples to `/api/attendance/locations` until check-out.

**Adaptive cadence** (`lib/features/attendance/location_tracker.dart`):

| Movement state            | Interval     |
| ------------------------- | ------------ |
| Moving fast (> 3 m/s)     | 2 min        |
| Default                   | 5 min        |
| Stopped (< 0.5 m/s)       | 30 min       |
| Distance changes > 200 m  | event-driven |

Samples are buffered (5 pings or 2 min, whichever comes first) and uploaded in
one batch — saves battery and survives short network drops.

State persists in secure storage, so if the app is killed while a session is
active, [`LocationTracker.restoreIfActive`](lib/features/attendance/location_tracker.dart)
is called from `locationLifecycleProvider` on next launch and tracking resumes.

### Required Android permissions (foreground service)

Add to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION"/>

<!-- Foreground-service declarations (Android 14+ needs the typed variant) -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>
<uses-permission android:name="android.permission.WAKE_LOCK"/>

<application ...>
    <service
        android:name="com.baseflow.geolocator.GeolocatorLocationService"
        android:enabled="true"
        android:exported="false"
        android:foregroundServiceType="location" />
    ...
</application>
```

On Android 10+ the OS shows a runtime prompt for *background* location the
first time the foreground notification appears. Tell users to pick **Allow all
the time** if they're field staff.

### Required iOS keys

Add to `ios/Runner/Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Records your attendance location while you are checked in.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Records your attendance location while you are checked in, even in the background.</string>
<key>UIBackgroundModes</key>
<array>
  <string>location</string>
</array>
```

### Reviewing pings (admin)

| Method   | Path                                                  | Purpose                               |
| -------- | ----------------------------------------------------- | ------------------------------------- |
| `POST`   | `/api/attendance/locations`                           | Mobile uploads a batch (self only)    |
| `GET`    | `/api/attendance/locations/employee/{id}?date=YYYY-MM-DD` | All pings for one day (ADMIN/HR)      |
| `GET`    | `/api/attendance/locations/employee/{id}/page`        | Paginated raw history (ADMIN/HR)      |

The next obvious add-on is a web map (Leaflet or Google Maps) that polylines
these points — endpoint already returns the data; just needs UI.

## 8. Roadmap (next features to wire)

- **Regularization** — `/api/regularizations` (POST + my list). Reuse the leave-request sheet pattern with a date + check-in time + check-out time.
- **Tasks** — `/api/tasks` (my list, fill form). Render `formSchema` with a simple field-type switch (text / number / select / date / file).
- **Profile photo upload** — `POST /api/files`, then PUT `/api/employees/{id}` with `profileImageUrl`.
- **Push notifications for pending approvals** — backend hook + FCM.
