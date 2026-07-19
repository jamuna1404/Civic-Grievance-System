import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';

/// A resolved GPS coordinate.
class LatLngPoint {
  const LatLngPoint(this.lat, this.lon);
  final double lat;
  final double lon;
}

/// Raised when the current location can't be obtained. [permanentlyDenied]
/// signals the user must enable permission from system Settings.
class LocationFailure implements Exception {
  LocationFailure(this.message, {this.permanentlyDenied = false});
  final String message;
  final bool permanentlyDenied;
}

/// Abstraction over device GPS + reverse geocoding, so the location step can be
/// tested with a fake and doesn't touch platform channels directly.
abstract class LocationService {
  /// Fetches the current position, requesting permission if needed.
  /// Throws [LocationFailure] on denial or if location services are off.
  Future<LatLngPoint> getCurrentPosition();

  /// Best-effort reverse geocode to a human-readable address. Returns null if
  /// no address could be resolved (never throws — the pin still stands).
  Future<String?> reverseGeocode(LatLngPoint point);
}

class GeolocatorLocationService implements LocationService {
  @override
  Future<LatLngPoint> getCurrentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw LocationFailure(
        'Location services are turned off. Please enable them and try again.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw LocationFailure(
        'Location permission is permanently denied. Enable it for CivicRoute '
        'in your device Settings.',
        permanentlyDenied: true,
      );
    }
    if (permission == LocationPermission.denied) {
      throw LocationFailure('Location permission was denied.');
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return LatLngPoint(position.latitude, position.longitude);
  }

  @override
  Future<String?> reverseGeocode(LatLngPoint point) async {
    try {
      final marks = await geocoding.placemarkFromCoordinates(
        point.lat,
        point.lon,
      );
      if (marks.isEmpty) return null;
      final p = marks.first;
      final parts = <String?>[
        p.name,
        p.subLocality,
        p.locality,
        p.postalCode,
      ].where((s) => s != null && s.trim().isNotEmpty).toSet().toList();
      return parts.isEmpty ? null : parts.join(', ');
    } catch (_) {
      return null; // geocoding unavailable (e.g. desktop) — pin still valid.
    }
  }
}

final locationServiceProvider = Provider<LocationService>(
  (ref) => GeolocatorLocationService(),
);
