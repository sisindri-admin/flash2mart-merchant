import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../constants/app_colors.dart';
import '../services/geocoding_service.dart';

/// Store Location Sheet with Real Live GPS & Reverse Geocoding
/// Uses GeocodingService (native geocoder + OSM Nominatim fallback)
/// Saves high-precision GeoPoint & structured address to `merchants/{uid}`
class StoreLocationSheet extends StatefulWidget {
  final Map<String, dynamic> currentData;
  final VoidCallback? onSaved;

  const StoreLocationSheet({
    super.key,
    required this.currentData,
    this.onSaved,
  });

  @override
  State<StoreLocationSheet> createState() => _StoreLocationSheetState();
}

class _StoreLocationSheetState extends State<StoreLocationSheet> {
  final _nameController = TextEditingController();
  final _doorNoController = TextEditingController();
  final _streetController = TextEditingController();
  final _areaController = TextEditingController();
  final _cityController = TextEditingController(text: 'Nellore');
  final _pincodeController = TextEditingController();
  final _addressController = TextEditingController();

  double? _latitude;
  double? _longitude;
  bool _isLocating = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = (widget.currentData['storeName'] ??
            widget.currentData['shopName'] ??
            widget.currentData['name'] ??
            '')
        .toString();
    _doorNoController.text = (widget.currentData['doorNo'] ?? '').toString();
    _streetController.text = (widget.currentData['street'] ?? '').toString();
    _areaController.text = (widget.currentData['area'] ?? '').toString();
    _cityController.text = (widget.currentData['city'] ?? 'Nellore').toString();
    _pincodeController.text = (widget.currentData['pincode'] ?? '').toString();
    _addressController.text = (widget.currentData['fullAddress'] ??
            widget.currentData['address'] ??
            '')
        .toString();

    final dynamic loc =
        widget.currentData['storeLocation'] ?? widget.currentData['location'];
    if (loc is GeoPoint) {
      _latitude = loc.latitude;
      _longitude = loc.longitude;
    } else {
      _latitude = (widget.currentData['latitude'] ?? widget.currentData['storeLat'])?.toDouble();
      _longitude = (widget.currentData['longitude'] ?? widget.currentData['storeLng'])?.toDouble();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _doorNoController.dispose();
    _streetController.dispose();
    _areaController.dispose();
    _cityController.dispose();
    _pincodeController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _updateFormattedAddress() {
    final door = _doorNoController.text.trim();
    final street = _streetController.text.trim();
    final area = _areaController.text.trim();
    final city = _cityController.text.trim();
    final pin = _pincodeController.text.trim();

    final List<String> parts = [];
    if (door.isNotEmpty) parts.add(door);
    if (street.isNotEmpty) parts.add(street);
    if (area.isNotEmpty && area != street) parts.add(area);
    if (city.isNotEmpty && city != area) parts.add(city);
    if (pin.isNotEmpty) parts.add(pin);

    setState(() {
      _addressController.text = parts.join(', ');
    });
  }

  Future<void> _detectLiveGps() async {
    setState(() => _isLocating = true);
    double detectedLat = GeocodingService.defaultNelloreLat;
    double detectedLng = GeocodingService.defaultNelloreLng;
    bool hasHardwareGps = false;

    // 1. Try Hardware GPS (Android / iOS mobile phone)
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.denied && permission != LocationPermission.deniedForever) {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 8),
        );
        detectedLat = position.latitude;
        detectedLng = position.longitude;
        hasHardwareGps = true;
      }
    } catch (e) {
      debugPrint('Hardware GPS not available on this laptop/device: $e');
    }

    // 2. Fallback for Ubuntu Laptop / Desktop:
    if (!hasHardwareGps) {
      final ipLoc = await GeocodingService.fetchIpLocation();
      if (ipLoc != null) {
        detectedLat = (ipLoc['lat'] as num).toDouble();
        detectedLng = (ipLoc['lng'] as num).toDouble();
        if (_cityController.text.isEmpty) _cityController.text = ipLoc['city'].toString();
        if (_pincodeController.text.isEmpty && (ipLoc['zip'] as String).isNotEmpty) {
          _pincodeController.text = ipLoc['zip'].toString();
        }
      }
    }

    _latitude = detectedLat;
    _longitude = detectedLng;

    // 3. Real live reverse geocoding via GeocodingService
    final geo = await GeocodingService.reverseGeocode(detectedLat, detectedLng);

    if (geo.street.isNotEmpty) _streetController.text = geo.street;
    if (geo.area.isNotEmpty) _areaController.text = geo.area;
    if (geo.city.isNotEmpty) _cityController.text = geo.city;
    if (geo.pincode.isNotEmpty) _pincodeController.text = geo.pincode;
    if (geo.doorNo.isNotEmpty) _doorNoController.text = geo.doorNo;

    _updateFormattedAddress();
    setState(() {});

    if (mounted) {
      if (geo.hasAddressText) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '🎯 Location Detected: ${_streetController.text}, ${_areaController.text}',
            ),
            backgroundColor: AppColors.primaryGreen,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '💻 Laptop Mode: Pinned at Lat $detectedLat, Lng $detectedLng. Please enter your shop address.',
            ),
            backgroundColor: AppColors.primaryGreen,
          ),
        );
      }
    }
    if (mounted) setState(() => _isLocating = false);
  }

  Future<void> _saveLocation() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final String name = _nameController.text.trim();
    final String door = _doorNoController.text.trim();
    final String street = _streetController.text.trim();
    final String area = _areaController.text.trim();
    final String city = _cityController.text.trim().isNotEmpty ? _cityController.text.trim() : 'Nellore';
    final String pin = _pincodeController.text.trim();

    _updateFormattedAddress();
    final String fullAddress = _addressController.text.trim().isNotEmpty
        ? _addressController.text.trim()
        : [street, area, city, pin].where((s) => s.isNotEmpty).join(', ');

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter store name.')),
      );
      return;
    }

    if (street.isEmpty || area.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter Street and Area name for delivery navigation.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final docData = <String, dynamic>{
        'storeName': name,
        'shopName': name,
        'name': name,
        'doorNo': door,
        'street': street,
        'area': area,
        'city': city,
        'pincode': pin,
        'address': fullAddress,
        'locationAddress': fullAddress,
        'fullAddress': fullAddress,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (_latitude != null && _longitude != null) {
        final point = GeoPoint(_latitude!, _longitude!);
        docData['storeLocation'] = point;
        docData['location'] = point;
        docData['latitude'] = _latitude!;
        docData['longitude'] = _longitude!;
        docData['storeLat'] = _latitude!;
        docData['storeLng'] = _longitude!;
      }

      await FirebaseFirestore.instance
          .collection('merchants')
          .doc(user.uid)
          .set(docData, SetOptions(merge: true));

      if (_latitude != null && _longitude != null) {
        final point = GeoPoint(_latitude!, _longitude!);
        try {
          final activeOrders = await FirebaseFirestore.instance
              .collection('orders')
              .where('merchantId', isEqualTo: user.uid)
              .get();
          for (final oDoc in activeOrders.docs) {
            final os = (oDoc.data()['orderStatus'] ?? oDoc.data()['status'] ?? '').toString().toLowerCase();
            if (os == 'delivered' || os == 'completed' || os == 'cancelled') continue;
            await oDoc.reference.update({
              'storeLocation': point,
              'merchantLocation': point,
              'storeLat': _latitude!,
              'storeLng': _longitude!,
            });
          }
          final prods = await FirebaseFirestore.instance
              .collection('products')
              .where('merchantId', isEqualTo: user.uid)
              .get();
          for (final pDoc in prods.docs) {
            await pDoc.reference.update({
              'storeLocation': point,
              'storeLat': _latitude!,
              'storeLng': _longitude!,
            });
          }
        } catch (_) {}
      }

      if (widget.onSaved != null) {
        widget.onSaved!();
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Real Store Address & GPS pinned for Customer & Delivery Partner!'),
            backgroundColor: AppColors.primaryGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving store info: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasCoords = _latitude != null && _longitude != null;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const Row(
              children: [
                Icon(Icons.edit_location_alt_rounded, color: AppColors.accentBlue, size: 22),
                SizedBox(width: 8),
                Text(
                  'Store Address & Real GPS Pin',
                  style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900, color: AppColors.textDark),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Store Name
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Store Name (Seen by Customers)',
                prefixIcon: const Icon(Icons.storefront_rounded, size: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),

            // GPS Pin Detection Box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: hasCoords ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasCoords ? const Color(0xFF86EFAC) : const Color(0xFFFECACA),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            hasCoords ? Icons.gps_fixed_rounded : Icons.gps_off_rounded,
                            color: hasCoords ? AppColors.primaryGreen : Colors.red,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            hasCoords ? 'Live GPS Pin Attached' : 'No GPS Pin Attached',
                            style: TextStyle(
                              color: hasCoords ? AppColors.primaryGreen : Colors.red.shade900,
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.accentBlue,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                        onPressed: _isLocating ? null : _detectLiveGps,
                        icon: _isLocating
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.my_location_rounded, size: 16),
                        label: const Text('Capture Live GPS', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  if (hasCoords) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Lat: ${_latitude!.toStringAsFixed(5)}, Lng: ${_longitude!.toStringAsFixed(5)}',
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF334155), fontFamily: 'monospace'),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Structured Address Fields
            Row(
              children: [
                Expanded(
                  flex: 4,
                  child: TextField(
                    controller: _doorNoController,
                    onChanged: (_) => _updateFormattedAddress(),
                    decoration: InputDecoration(
                      labelText: 'Door / Shop No',
                      hintText: 'Shop No, D.No',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 6,
                  child: TextField(
                    controller: _streetController,
                    onChanged: (_) => _updateFormattedAddress(),
                    decoration: InputDecoration(
                      labelText: 'Street / Road *',
                      hintText: 'Street or Road name',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            TextField(
              controller: _areaController,
              onChanged: (_) => _updateFormattedAddress(),
              decoration: InputDecoration(
                labelText: 'Area / Colony / Nagar *',
                hintText: 'Area or Colony name',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cityController,
                    onChanged: (_) => _updateFormattedAddress(),
                    decoration: InputDecoration(
                      labelText: 'City',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _pincodeController,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _updateFormattedAddress(),
                    decoration: InputDecoration(
                      labelText: 'Pincode',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            TextField(
              controller: _addressController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Full Formatted Address (Saved for Deliveries)',
                hintText: 'Complete address for delivery partner references',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 18),

            // Save Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 1,
                ),
                onPressed: _isSaving ? null : _saveLocation,
                icon: _isSaving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.check_circle_rounded, size: 20),
                label: Text(
                  _isSaving ? 'SAVING...' : 'SAVE & SYNC REAL ADDRESS',
                  style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.3),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
