import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/api_client.dart';
import 'location_repository.dart';

/// Answers an HR "live location" request: checks permission + GPS, tries to get a
/// current fix, and reports the result (or the reason it failed) to the backend.
///
/// Top-level so it can run from the FCM background isolate too (where Riverpod
/// providers aren't available) — it uses the [ApiClient] singleton directly.
Future<void> respondToLiveLocationRequest() async {
  try {
    final serviceOn = await Geolocator.isLocationServiceEnabled();
    final perm = await Geolocator.checkPermission();
    final granted = perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;

    final whileInUseOnly = perm == LocationPermission.whileInUse;

    double? lat;
    double? lng;
    String? reason;

    if (!granted) {
      reason = perm == LocationPermission.deniedForever
          ? 'Location permission permanently denied — enable it in app settings'
          : 'Location permission not granted in the app';
    } else if (!serviceOn) {
      reason = 'Device location services (GPS) are turned off';
    } else {
      // Last-known first: instant, and a useful fallback if a fresh fix can't be had
      // (e.g. "while using the app" permission with the app in the background).
      Position? lastKnown;
      try {
        lastKnown = await Geolocator.getLastKnownPosition();
      } catch (_) {
        lastKnown = null;
      }
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 12),
        );
        lat = pos.latitude;
        lng = pos.longitude;
      } catch (_) {
        if (lastKnown != null) {
          lat = lastKnown.latitude;
          lng = lastKnown.longitude;
          reason = whileInUseOnly
              ? 'Showing last known location — live GPS needs the app open '
                  '(permission is "while using the app")'
              : 'Showing last known location (could not get a fresh GPS fix)';
        } else {
          reason = whileInUseOnly
              ? 'No live fix — location is allowed only while the app is open. '
                  'Ask the employee to open the app.'
              : 'Could not get a GPS fix (timed out)';
        }
      }
    }

    // tracking=true: the app is responsive. (For a live request, whether the
    // employee is "checked in" is irrelevant — HR just wants the position.)
    await LocationRepository(ApiClient.instance).reportLive(
      locationEnabled: serviceOn,
      permissionGranted: granted,
      tracking: true,
      latitude: lat,
      longitude: lng,
      reason: reason,
    );
  } catch (e) {
    if (kDebugMode) debugPrint('Live-location respond failed: $e');
  }
}
