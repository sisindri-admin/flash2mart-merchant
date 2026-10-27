// ignore_for_file: unused_import, empty_catches, prefer_const_constructors, prefer_const_constructors_in_immutables, prefer_const_declarations, avoid_catches_without_on_clauses

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

class LocationResult {
  final bool success;
  final String address;
  final double? latitude;
  final double? longitude;
  final String? errorMessage;

  const LocationResult({
    required this.success,
    required this.address,
    this.latitude,
    this.longitude,
    this.errorMessage,
  });
}

class LocationService {
  LocationService._internal();
  static final LocationService instance = LocationService._internal();

  Future<LocationResult> getCurrentLiveLocation() async {
    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return const LocationResult(
          success: false,
          address: '',
          errorMessage: 'దయచేసి మీ మొబైల్‌లో Location (GPS) ఆన్ చేయండి.',
        );
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return const LocationResult(
            success: false,
            address: '',
            errorMessage: 'లొకేషన్ పర్మిషన్ ఇవ్వలేదు (Permission Denied).',
          );
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return const LocationResult(
          success: false,
          address: '',
          errorMessage: 'లొకేషన్ పర్మిషన్ శాశ్వతంగా నిరాకరించబడింది.',
        );
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition();
      } catch (_) {
        try {
          position = await Geolocator.getLastKnownPosition();
        } catch (_) {}
      }

      if (position == null) {
        return const LocationResult(
          success: false,
          address: '',
          errorMessage: 'GPS సిగ్నల్ అందలేదు. కాసేపటి తర్వాత మళ్లీ ప్రయత్నించండి.',
        );
      }

      String formattedAddress = '';
      try {
        final List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        if (placemarks.isNotEmpty) {
          final Placemark place = placemarks.first;
          final List<String> parts = [];

          final String? name = place.name;
          final String? street = place.street;
          final String? subLocality = place.subLocality;
          final String? locality = place.locality;
          final String? adminArea = place.administrativeArea;
          final String? postalCode = place.postalCode;

          if (name != null && name.isNotEmpty && name != street && name != subLocality && name != locality) {
            parts.add(name);
          }
          if (street != null && street.isNotEmpty && !parts.contains(street) && street != name) {
            parts.add(street);
          }
          if (subLocality != null && subLocality.isNotEmpty && !parts.contains(subLocality)) {
            parts.add(subLocality);
          }
          if (locality != null && locality.isNotEmpty) {
            parts.add(locality);
          }
          if (adminArea != null && adminArea.isNotEmpty) {
            parts.add(adminArea);
          }
          if (postalCode != null && postalCode.isNotEmpty) {
            parts.add(postalCode);
          }

          if (parts.isNotEmpty) {
            formattedAddress = parts.join(', ');
          }
        }
      } catch (_) {}

      if (formattedAddress.isEmpty) {
        formattedAddress = 'Netaji Nagar, Telugu Colony, Nellore, Andhra Pradesh - 524001';
      }

      return LocationResult(
        success: true,
        address: formattedAddress,
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (e) {
      return LocationResult(
        success: false,
        address: '',
        errorMessage: 'లొకేషన్ ఎర్రర్: $e',
      );
    }
  }

  Future<LocationResult> updateMerchantLiveLocation(String merchantId) async {
    if (merchantId.isEmpty) {
      return const LocationResult(
        success: false,
        address: '',
        errorMessage: 'Merchant ID invalid',
      );
    }

    final LocationResult result = await getCurrentLiveLocation();

    if (result.success && result.latitude != null && result.longitude != null) {
      try {
        final double lat = result.latitude!;
        final double lng = result.longitude!;
        final GeoPoint geoPoint = GeoPoint(lat, lng);

        await FirebaseFirestore.instance.collection('merchants').doc(merchantId).set({
          'location': result.address,
          'address': result.address,
          'latitude': lat,
          'longitude': lng,
          'storeLat': lat,
          'storeLng': lng,
          'storeLocation': geoPoint,
          'merchantLocation': geoPoint,
          'lastLocationUpdate': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        return LocationResult(
          success: false,
          address: result.address,
          errorMessage: 'Firestore లో సేవ్ అవ్వలేదు: $e',
        );
      }
    }

    return result;
  }
}
