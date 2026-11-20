import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';

class GeocodedAddress {
  final String doorNo;
  final String street;
  final String area;
  final String city;
  final String pincode;
  final String fullAddress;
  final double latitude;
  final double longitude;
  final String source;

  GeocodedAddress({
    this.doorNo = '',
    this.street = '',
    this.area = '',
    this.city = '',
    this.pincode = '',
    this.fullAddress = '',
    required this.latitude,
    required this.longitude,
    this.source = 'unknown',
  });

  bool get hasAddressText =>
      street.isNotEmpty || area.isNotEmpty || fullAddress.isNotEmpty;
}

class GeocodingService {
  /// Default Nellore City Center Coordinates (used as fallback for Laptop / Ubuntu testing)
  static const double defaultNelloreLat = 14.4428;
  static const double defaultNelloreLng = 79.9890;

  /// IP-based location fallback for Laptop / Ubuntu / Desktop / Emulator
  static Future<Map<String, dynamic>?> fetchIpLocation() async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final uri = Uri.parse('http://ip-api.com/json');
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        if (data['status'] == 'success') {
          return {
            'lat': (data['lat'] as num).toDouble(),
            'lng': (data['lon'] as num).toDouble(),
            'city': (data['city'] ?? 'Nellore').toString(),
            'region': (data['regionName'] ?? 'Andhra Pradesh').toString(),
            'zip': (data['zip'] ?? '').toString(),
          };
        }
      }
    } catch (e) {
      debugPrint('IP location fetch error: $e');
    }
    return null;
  }

  /// Forward Geocode: Search coordinates by typing Area or Street name in Nellore
  static Future<Map<String, double>?> searchCoordinates(String query) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final searchQuery = query.toLowerCase().contains('nellore') ? query : '$query, Nellore';
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(searchQuery)}&format=json&limit=1',
      );
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'Flash2MartMerchantApp/1.0 (contact@flash2mart.com)');
      final response = await request.close().timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final List data = jsonDecode(body) as List;
        if (data.isNotEmpty) {
          final first = data[0] as Map<String, dynamic>;
          final lat = double.tryParse(first['lat'].toString());
          final lng = double.tryParse(first['lon'].toString());
          if (lat != null && lng != null) {
            return {'lat': lat, 'lng': lng};
          }
        }
      }
    } catch (e) {
      debugPrint('Forward geocode search error: $e');
    }
    return null;
  }

  /// Reverse geocode given latitude & longitude.
  /// 1. Tries native platform Geocoder (package:geocoding)
  /// 2. If native Geocoder fails or returns empty street/area, falls back to OSM Nominatim API
  /// 3. Returns GeocodedAddress with real resolved components (NEVER hardcoded fake data)
  static Future<GeocodedAddress> reverseGeocode(double lat, double lng) async {
    // 1. Try Native Geocoder (Android / iOS native API)
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final door = (p.subThoroughfare ?? '').trim();
        final street = _pickBestStreet(p);
        final area = _pickBestArea(p);
        final city = (p.locality ?? p.subAdministrativeArea ?? '').trim();
        final pin = (p.postalCode ?? '').trim();

        if (street.isNotEmpty || area.isNotEmpty || city.isNotEmpty) {
          final full = _formatFull(door: door, street: street, area: area, city: city, pin: pin);
          return GeocodedAddress(
            doorNo: door,
            street: street,
            area: area,
            city: city.isNotEmpty ? city : 'Nellore',
            pincode: pin,
            fullAddress: full,
            latitude: lat,
            longitude: lng,
            source: 'native_geocoder',
          );
        }
      }
    } catch (e) {
      debugPrint('Native geocoder error: $e');
    }

    // 2. Direct HTTPS Fallback via OpenStreetMap Nominatim
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&zoom=18&addressdetails=1',
      );
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'Flash2MartMerchantApp/1.0 (contact@flash2mart.com)');
      request.headers.set('Accept', 'application/json');
      final response = await request.close().timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final addr = (data['address'] as Map<String, dynamic>?) ?? {};

        final door = (addr['house_number'] ?? addr['building'] ?? '').toString().trim();
        final street = (addr['road'] ?? addr['street'] ?? addr['pedestrian'] ?? addr['footway'] ?? '').toString().trim();
        final area = (addr['suburb'] ?? addr['neighbourhood'] ?? addr['residential'] ?? addr['subdistrict'] ?? addr['city_district'] ?? addr['village'] ?? '').toString().trim();
        final city = (addr['city'] ?? addr['town'] ?? addr['municipality'] ?? addr['county'] ?? '').toString().trim();
        final pin = (addr['postcode'] ?? '').toString().trim();

        final rawDisplay = (data['display_name'] ?? '').toString().trim();
        final full = _formatFull(
          door: door,
          street: street,
          area: area,
          city: city,
          pin: pin,
          fallbackDisplayName: rawDisplay,
        );

        return GeocodedAddress(
          doorNo: door,
          street: street,
          area: area,
          city: city.isNotEmpty ? city : 'Nellore',
          pincode: pin,
          fullAddress: full,
          latitude: lat,
          longitude: lng,
          source: 'osm_nominatim',
        );
      }
    } catch (e) {
      debugPrint('OSM Nominatim fallback error: $e');
    }

    // 3. Fallback: Return raw coordinates with empty address strings (NO fake address!)
    return GeocodedAddress(
      doorNo: '',
      street: '',
      area: '',
      city: 'Nellore',
      pincode: '',
      fullAddress: '',
      latitude: lat,
      longitude: lng,
      source: 'gps_only',
    );
  }

  static String _pickBestStreet(Placemark p) {
    if (p.thoroughfare != null && p.thoroughfare!.trim().isNotEmpty) {
      return p.thoroughfare!.trim();
    }
    if (p.street != null && p.street!.trim().isNotEmpty && p.street != p.name) {
      return p.street!.trim();
    }
    if (p.name != null && p.name!.trim().isNotEmpty && !p.name!.contains('+')) {
      return p.name!.trim();
    }
    return '';
  }

  static String _pickBestArea(Placemark p) {
    if (p.subLocality != null && p.subLocality!.trim().isNotEmpty) {
      return p.subLocality!.trim();
    }
    if (p.subAdministrativeArea != null && p.subAdministrativeArea!.trim().isNotEmpty) {
      return p.subAdministrativeArea!.trim();
    }
    return '';
  }

  static String _formatFull({
    required String door,
    required String street,
    required String area,
    required String city,
    required String pin,
    String fallbackDisplayName = '',
  }) {
    final List<String> parts = [];
    if (door.isNotEmpty) parts.add(door);
    if (street.isNotEmpty) parts.add(street);
    if (area.isNotEmpty && area != street) parts.add(area);
    if (city.isNotEmpty && city != area) parts.add(city);
    if (pin.isNotEmpty) parts.add(pin);

    if (parts.isNotEmpty) {
      return parts.join(', ');
    }
    return fallbackDisplayName;
  }
}
