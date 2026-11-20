import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../constants/app_colors.dart';
import '../services/geocoding_service.dart';
import 'merchant_dashboard.dart';

/// Executive Merchant Authentication Screen (Sign In & Store Registration Tabs)
/// Features:
/// 1. Sign In tab with email/password and 1-tap quick demo login.
/// 2. Register Store tab with Real Reverse Geocoding (resolves real Street, Area, City, Pin from live GPS).
/// 3. High-precision GeoPoint coordinates saving for Customer & Delivery Partner route navigation.
/// 4. Sets initial store status to 'pending_approval' for Flash2Mart Admin verification!
class MerchantAuthScreen extends StatefulWidget {
  const MerchantAuthScreen({super.key});

  @override
  State<MerchantAuthScreen> createState() => _MerchantAuthScreenState();
}

class _MerchantAuthScreenState extends State<MerchantAuthScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Login Controllers
  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  bool _loginObscure = true;
  bool _isLoggingIn = false;

  // Register Controllers (Structured Address)
  final _regOwnerNameController = TextEditingController();
  final _regStoreNameController = TextEditingController();
  final _regPhoneController = TextEditingController();
  final _regEmailController = TextEditingController();
  final _regPasswordController = TextEditingController();
  final _regDoorNoController = TextEditingController();
  final _regStreetController = TextEditingController();
  final _regAreaController = TextEditingController();
  final _regCityController = TextEditingController(text: 'Nellore');
  final _regPincodeController = TextEditingController();
  final _regAddressController = TextEditingController();

  String _selectedCategory = 'Grocery / Supermarket';
  double? _storeLat;
  double? _storeLng;
  bool _regObscure = true;
  bool _isLocating = false;
  bool _isRegistering = false;

  final List<String> _storeCategories = const [
    'Grocery / Supermarket',
    'Vegetables & Fruits',
    'Dairy, Bread & Eggs',
    'Meat, Fish & Poultry',
    'Bakery & Snacks',
    'Medicines & Pharmacy',
    'Electronics Store',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _regOwnerNameController.dispose();
    _regStoreNameController.dispose();
    _regPhoneController.dispose();
    _regEmailController.dispose();
    _regPasswordController.dispose();
    _regDoorNoController.dispose();
    _regStreetController.dispose();
    _regAreaController.dispose();
    _regCityController.dispose();
    _regPincodeController.dispose();
    _regAddressController.dispose();
    super.dispose();
  }

  void _showToast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade700 : AppColors.primaryGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // --- SIGN IN ACTION ---
  Future<void> _handleLogin() async {
    final email = _loginEmailController.text.trim();
    final password = _loginPasswordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showToast('Please enter both email and password.', isError: true);
      return;
    }

    setState(() => _isLoggingIn = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MerchantDashboard()),
        );
      }
    } on FirebaseAuthException catch (e) {
      _showToast(e.message ?? 'Invalid credentials.', isError: true);
    } catch (e) {
      _showToast('Sign in error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoggingIn = false);
    }
  }

  // --- QUICK DEMO LOGIN ---
  Future<void> _handleQuickDemoLogin() async {
    setState(() => _isLoggingIn = true);
    try {
      const demoEmail = 'merchant.demo@flash2mart.com';
      const demoPass = 'Flash2Mart@123';
      try {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: demoEmail,
          password: demoPass,
        );
      } catch (_) {
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: demoEmail,
          password: demoPass,
        );
        await FirebaseFirestore.instance.collection('merchants').doc(cred.user!.uid).set({
          'merchantId': cred.user!.uid,
          'uid': cred.user!.uid,
          'storeName': 'Nellore Flash2Mart Super Mart',
          'ownerName': 'Store Manager',
          'phone': '+91 9876543210',
          'email': demoEmail,
          'doorNo': 'Shop 4',
          'street': 'Trunk Road',
          'area': 'Nellore Central',
          'city': 'Nellore',
          'pincode': '524001',
          'address': 'Shop 4, Trunk Road, Nellore Central, Nellore - 524001',
          'locationAddress': 'Shop 4, Trunk Road, Nellore Central, Nellore - 524001',
          'fullAddress': 'Shop 4, Trunk Road, Nellore Central, Nellore - 524001',
          'category': 'Grocery / Supermarket',
          'storeLocation': const GeoPoint(14.4428, 79.9890),
          'location': const GeoPoint(14.4428, 79.9890),
          'latitude': 14.4428,
          'longitude': 79.9890,
          'isOpen': true,
          'status': 'active',
          'isApprovedByAdmin': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MerchantDashboard()),
        );
      }
    } catch (e) {
      _showToast('Demo login error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoggingIn = false);
    }
  }

  // --- REVERSE GEOCODING (GPS + IP FALLBACK FOR LAPTOP / UBUNTU) ---
  Future<void> _detectStoreGps() async {
    setState(() => _isLocating = true);
    double detectedLat = GeocodingService.defaultNelloreLat;
    double detectedLng = GeocodingService.defaultNelloreLng;
    bool hasHardwareGps = false;

    // 1. Try Hardware GPS (works when running on mobile phone)
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm != LocationPermission.denied && perm != LocationPermission.deniedForever) {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 8),
        );
        detectedLat = pos.latitude;
        detectedLng = pos.longitude;
        hasHardwareGps = true;
      }
    } catch (e) {
      debugPrint('Hardware GPS unavailable on this device/OS (Laptop/Desktop): $e');
    }

    // 2. Fallback for Laptop / Ubuntu / Desktop testing:
    if (!hasHardwareGps) {
      final ipLoc = await GeocodingService.fetchIpLocation();
      if (ipLoc != null) {
        detectedLat = (ipLoc['lat'] as num).toDouble();
        detectedLng = (ipLoc['lng'] as num).toDouble();
        if (_regCityController.text.isEmpty) _regCityController.text = ipLoc['city'].toString();
        if (_regPincodeController.text.isEmpty && (ipLoc['zip'] as String).isNotEmpty) {
          _regPincodeController.text = ipLoc['zip'].toString();
        }
      }
    }

    _storeLat = detectedLat;
    _storeLng = detectedLng;

    // 3. Reverse geocode to resolve components
    final geo = await GeocodingService.reverseGeocode(detectedLat, detectedLng);

    if (geo.street.isNotEmpty) _regStreetController.text = geo.street;
    if (geo.area.isNotEmpty) _regAreaController.text = geo.area;
    if (geo.city.isNotEmpty) _regCityController.text = geo.city;
    if (geo.pincode.isNotEmpty) _regPincodeController.text = geo.pincode;
    if (geo.doorNo.isNotEmpty) _regDoorNoController.text = geo.doorNo;

    _updateFormattedAddressPreview();

    if (geo.hasAddressText) {
      _showToast('🎯 Location Detected: ${_regStreetController.text}, ${_regAreaController.text}');
    } else {
      _showToast('💻 Laptop Mode: Location Pinned to Nellore ($detectedLat, $detectedLng). Please enter your shop address.');
    }

    if (mounted) setState(() => _isLocating = false);
  }

  void _updateFormattedAddressPreview() {
    final door = _regDoorNoController.text.trim();
    final street = _regStreetController.text.trim();
    final area = _regAreaController.text.trim();
    final city = _regCityController.text.trim();
    final pin = _regPincodeController.text.trim();

    final List<String> parts = [];
    if (door.isNotEmpty) parts.add(door);
    if (street.isNotEmpty) parts.add(street);
    if (area.isNotEmpty && area != street) parts.add(area);
    if (city.isNotEmpty && city != area) parts.add(city);
    if (pin.isNotEmpty) parts.add(pin);

    setState(() {
      _regAddressController.text = parts.join(', ');
    });
  }

  // --- REGISTER STORE & ADMIN APPROVAL SYNC ---
  Future<void> _handleRegisterStore() async {
    final owner = _regOwnerNameController.text.trim();
    final store = _regStoreNameController.text.trim();
    final phone = _regPhoneController.text.trim();
    final email = _regEmailController.text.trim();
    final password = _regPasswordController.text.trim();

    final door = _regDoorNoController.text.trim();
    final street = _regStreetController.text.trim();
    final area = _regAreaController.text.trim();
    final city = _regCityController.text.trim().isNotEmpty ? _regCityController.text.trim() : 'Nellore';
    final pin = _regPincodeController.text.trim();

    _updateFormattedAddressPreview();
    final fullAddress = _regAddressController.text.trim().isNotEmpty
        ? _regAddressController.text.trim()
        : [street, area, city, pin].where((s) => s.isNotEmpty).join(', ');

    if (owner.isEmpty || store.isEmpty || email.isEmpty || password.isEmpty) {
      _showToast('Please fill all required store details.', isError: true);
      return;
    }
    if (password.length < 6) {
      _showToast('Password must be at least 6 characters.', isError: true);
      return;
    }

    // If GPS not pinned (e.g. testing on Laptop), use Nellore default coordinates
    if (_storeLat == null || _storeLng == null) {
      _storeLat = GeocodingService.defaultNelloreLat;
      _storeLng = GeocodingService.defaultNelloreLng;
    }

    if (street.isEmpty || area.isEmpty) {
      _showToast('Please enter your shop Street and Area/Colony name.', isError: true);
      return;
    }

    setState(() => _isRegistering = true);
    try {
      // 1. Create Firebase Auth user
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid = cred.user!.uid;

      // 2. High-precision GPS coordinates from live device
      final double lat = _storeLat!;
      final double lng = _storeLng!;
      final geo = GeoPoint(lat, lng);

      // 3. Save Store Document with 'pending_approval' for Admin Verification!
      await FirebaseFirestore.instance.collection('merchants').doc(uid).set({
        'merchantId': uid,
        'uid': uid,
        'ownerName': owner,
        'storeName': store,
        'shopName': store,
        'name': store,
        'phone': phone.isNotEmpty ? phone : '+91 9999999999',
        'email': email,
        'category': _selectedCategory,
        'doorNo': door,
        'street': street,
        'area': area,
        'city': city,
        'pincode': pin,
        'address': fullAddress,
        'locationAddress': fullAddress,
        'fullAddress': fullAddress,
        'storeLocation': geo,
        'location': geo,
        'latitude': lat,
        'longitude': lng,
        'storeLat': lat,
        'storeLng': lng,
        'isOpen': true,
        'status': 'pending_approval', // ⏳ Sent to Flash2Mart Admin for Approval!
        'isApprovedByAdmin': false,
        'rating': 4.8,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        _showToast('🎉 Store registered! Submitted for Flash2Mart Admin approval.');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MerchantDashboard()),
        );
      }
    } on FirebaseAuthException catch (e) {
      _showToast(e.message ?? 'Registration failed.', isError: true);
    } catch (e) {
      _showToast('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isRegistering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Header Banner with Logo & Welcome
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primaryDark, AppColors.surfaceDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primaryGreen,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 28),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'FLASH2MART',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 20,
                                letterSpacing: 1.2,
                              ),
                            ),
                            Text(
                              'Merchant Partner Portal',
                              style: TextStyle(
                                color: AppColors.accentYellow,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0x14FFFFFF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        indicatorColor: AppColors.accentYellow,
                        indicatorWeight: 3,
                        labelColor: AppColors.accentYellow,
                        unselectedLabelColor: Colors.white70,
                        labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                        tabs: const [
                          Tab(text: 'SIGN IN'),
                          Tab(text: 'REGISTER STORE'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Tab View Content
              Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  // Sized appropriately for tab content
                  child: AnimatedBuilder(
                    animation: _tabController,
                    builder: (context, _) {
                      return _tabController.index == 0
                          ? _buildSignInTab()
                          : _buildRegisterStoreTab();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- TAB 1: SIGN IN ---
  Widget _buildSignInTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Welcome Back Partner',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textDark),
        ),
        const SizedBox(height: 4),
        const Text(
          'Sign in to manage your inventory, live orders & daily payouts',
          style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
        ),
        const SizedBox(height: 20),

        TextField(
          controller: _loginEmailController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: 'Registered Merchant Email',
            hintText: 'e.g. store@flash2mart.com',
            prefixIcon: const Icon(Icons.email_outlined, size: 20),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 14),

        TextField(
          controller: _loginPasswordController,
          obscureText: _loginObscure,
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline, size: 20),
            suffixIcon: IconButton(
              icon: Icon(_loginObscure ? Icons.visibility_off : Icons.visibility, size: 20),
              onPressed: () => setState(() => _loginObscure = !_loginObscure),
            ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 22),

        // Sign In Button
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 2,
            ),
            onPressed: _isLoggingIn ? null : _handleLogin,
            child: _isLoggingIn
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.login_rounded, size: 20),
                      SizedBox(width: 8),
                      Text('SIGN IN TO STORE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 16),

        // Quick Demo Login Button
        SizedBox(
          width: double.infinity,
          height: 46,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accentBlue,
              side: const BorderSide(color: AppColors.accentBlue, width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _isLoggingIn ? null : _handleQuickDemoLogin,
            icon: const Icon(Icons.flash_on_rounded, size: 18),
            label: const Text('1-TAP DEMO MERCHANT LOGIN', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
          ),
        ),
        const SizedBox(height: 20),

        Center(
          child: TextButton(
            onPressed: () => _tabController.animateTo(1),
            child: const Text('New to Flash2Mart? Register your Store here →', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryGreen)),
          ),
        ),
      ],
    );
  }

  // --- TAB 2: REGISTER STORE ---
  Widget _buildRegisterStoreTab() {
    final bool hasGps = _storeLat != null && _storeLng != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Register New Partner Store',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textDark),
        ),
        const SizedBox(height: 4),
        const Text(
          'Live GPS & Address ensure fast delivery partner pickup & customer reach',
          style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
        ),
        const SizedBox(height: 18),

        // Owner & Store Name
        TextField(
          controller: _regOwnerNameController,
          decoration: InputDecoration(
            labelText: 'Owner Full Name *',
            hintText: 'e.g. Ramesh Reddy',
            prefixIcon: const Icon(Icons.person_outline, size: 20),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),

        TextField(
          controller: _regStoreNameController,
          decoration: InputDecoration(
            labelText: 'Store / Shop Name *',
            hintText: 'e.g. Sri Balaji Supermarket',
            prefixIcon: const Icon(Icons.storefront_rounded, size: 20),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),

        // Phone & Email
        TextField(
          controller: _regPhoneController,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: 'Merchant Mobile Number *',
            hintText: 'e.g. +91 9876543210',
            prefixIcon: const Icon(Icons.phone_android_rounded, size: 20),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),

        TextField(
          controller: _regEmailController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: 'Merchant Email (Login ID) *',
            hintText: 'e.g. balaji.supermarket@gmail.com',
            prefixIcon: const Icon(Icons.email_outlined, size: 20),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),

        TextField(
          controller: _regPasswordController,
          obscureText: _regObscure,
          decoration: InputDecoration(
            labelText: 'Create Password *',
            prefixIcon: const Icon(Icons.lock_outline, size: 20),
            suffixIcon: IconButton(
              icon: Icon(_regObscure ? Icons.visibility_off : Icons.visibility, size: 20),
              onPressed: () => setState(() => _regObscure = !_regObscure),
            ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),

        // Store Category Dropdown
        DropdownButtonFormField<String>(
          initialValue: _selectedCategory,
          decoration: InputDecoration(
            labelText: 'Store Category',
            prefixIcon: const Icon(Icons.category_outlined, size: 20),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          items: _storeCategories.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 13)))).toList(),
          onChanged: (val) {
            if (val != null) setState(() => _selectedCategory = val);
          },
        ),
        const SizedBox(height: 16),

        // --- STRUCTURED ADDRESS & REAL LIVE GPS DETECTION SECTION ---
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.location_on_rounded, color: AppColors.accentBlue, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'Store Address & Real GPS Pin',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textDark),
                      ),
                    ],
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.accentBlue,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    onPressed: _isLocating ? null : _detectStoreGps,
                    icon: _isLocating
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.my_location_rounded, size: 16),
                    label: const Text('Capture Live GPS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Door / Shop No and Street
              Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: TextField(
                      controller: _regDoorNoController,
                      onChanged: (_) => _updateFormattedAddressPreview(),
                      decoration: InputDecoration(
                        labelText: 'Door / Shop No',
                        hintText: 'e.g. Shop 4',
                        prefixIcon: const Icon(Icons.meeting_room_outlined, size: 18),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 6,
                    child: TextField(
                      controller: _regStreetController,
                      onChanged: (_) => _updateFormattedAddressPreview(),
                      decoration: InputDecoration(
                        labelText: 'Street / Road *',
                        hintText: 'Street or road name',
                        prefixIcon: const Icon(Icons.add_road_rounded, size: 18),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Area / Colony / Nagar Input
              TextField(
                controller: _regAreaController,
                onChanged: (_) => _updateFormattedAddressPreview(),
                decoration: InputDecoration(
                  labelText: 'Area / Colony / Nagar *',
                  hintText: 'Colony or area name',
                  prefixIcon: const Icon(Icons.holiday_village_outlined, size: 18),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _regCityController,
                      onChanged: (_) => _updateFormattedAddressPreview(),
                      decoration: InputDecoration(
                        labelText: 'City',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _regPincodeController,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => _updateFormattedAddressPreview(),
                      decoration: InputDecoration(
                        labelText: 'Pincode',
                        hintText: 'e.g. 524001',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Full Formatted Address Preview
              TextField(
                controller: _regAddressController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Complete Full Address (Seen by Customers & Delivery Boy)',
                  hintText: 'Auto-composed or enter full address',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),

              if (hasGps) ...[
                const SizedBox(height: 6),
                Text(
                  '🎯 Live GPS Coordinates: Lat ${_storeLat!.toStringAsFixed(5)}, Lng ${_storeLng!.toStringAsFixed(5)}',
                  style: const TextStyle(fontSize: 11, color: AppColors.primaryGreen, fontWeight: FontWeight.bold),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Register Store Button
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 2,
            ),
            onPressed: _isRegistering ? null : _handleRegisterStore,
            child: _isRegistering
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_rounded, size: 20),
                      SizedBox(width: 8),
                      Text('SUBMIT STORE FOR ADMIN APPROVAL', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5)),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
