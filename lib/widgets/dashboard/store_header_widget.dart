import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../store_location_sheet.dart';
import '../store_timing_sheet.dart';

/// Store Header Widget with Live Online/Offline Toggle, Operating Hours, Auto-Pause Mode & GPS Pinning
class StoreHeaderWidget extends StatelessWidget {
  final Map<String, dynamic> storeData;
  final VoidCallback? onLocationUpdated;

  const StoreHeaderWidget({
    super.key,
    required this.storeData,
    this.onLocationUpdated,
  });

  Future<void> _toggleStoreStatus(BuildContext context, bool currentStatus) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final bool newStatus = !currentStatus;
    try {
      await FirebaseFirestore.instance.collection('merchants').doc(user.uid).set({
        'isOpen': newStatus,
        'isPaused': false,
        'pauseUntil': FieldValue.delete(),
        'pauseUntilFormatted': FieldValue.delete(),
        'pauseReason': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  newStatus ? Icons.check_circle_rounded : Icons.pause_circle_filled_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  newStatus
                      ? 'Store is now ONLINE & accepting customer orders!'
                      : 'Store is now OFFLINE (Orders paused in Customer App).',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                ),
              ],
            ),
            backgroundColor: newStatus ? AppColors.primaryGreen : const Color(0xFF475569),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating store status: $e')),
        );
      }
    }
  }

  void _openLocationSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StoreLocationSheet(
        currentData: storeData,
        onSaved: onLocationUpdated,
      ),
    );
  }

  void _openTimingSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StoreTimingSheet(
        storeData: storeData,
        onUpdated: onLocationUpdated,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String storeName = (storeData['storeName'] ??
            storeData['shopName'] ??
            storeData['name'] ??
            'Flash2Mart Partner Store')
        .toString();
    final String address = (storeData['fullAddress'] ??
            storeData['address'] ??
            storeData['locationAddress'] ??
            'Main Road, Nellore, Andhra Pradesh')
        .toString();
    final bool isOpen = storeData['isOpen'] == true;
    final bool isPaused = storeData['isPaused'] == true;
    final String pauseUntilFormatted = (storeData['pauseUntilFormatted'] ?? '').toString();
    final String pauseReason = (storeData['pauseReason'] ?? 'Temporary Break').toString();
    final String openTime = (storeData['openingTime'] ?? '07:00 AM').toString();
    final String closeTime = (storeData['closingTime'] ?? '10:30 PM').toString();
    final String status = (storeData['status'] ?? 'active').toString();
    final bool isPendingAdmin = status == 'pending_approval' || storeData['isApprovedByAdmin'] == false;

    // Check if real GPS coordinates are attached
    final dynamic loc = storeData['storeLocation'] ?? storeData['location'];
    bool hasGpsPin = false;
    if (loc is GeoPoint) {
      hasGpsPin = loc.latitude != 0 || loc.longitude != 0;
    } else if (storeData['latitude'] != null && storeData['longitude'] != null) {
      hasGpsPin = true;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryDark, AppColors.surfaceDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF334155), width: 1.2),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Store Name and Status Badge Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: AppColors.accentBlue.withAlpha(51),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.storefront_rounded, color: Color(0xFF38BDF8), size: 18),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        storeName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              // Live Status Pill (Online / Paused / Offline)
              GestureDetector(
                onTap: () => _toggleStoreStatus(context, isOpen),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isPaused
                        ? const Color(0x26F59E0B)
                        : (isOpen ? const Color(0x2616A34A) : const Color(0x2694A3B8)),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isPaused
                          ? const Color(0xFFF59E0B)
                          : (isOpen ? const Color(0xFF22C55E) : const Color(0xFF64748B)),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isPaused
                              ? const Color(0xFFF59E0B)
                              : (isOpen ? const Color(0xFF22C55E) : const Color(0xFF94A3B8)),
                          boxShadow: isOpen && !isPaused
                              ? const [
                                  BoxShadow(
                                    color: Color(0xFF22C55E),
                                    blurRadius: 6,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isPaused ? 'PAUSED' : (isOpen ? 'ONLINE' : 'OFFLINE'),
                        style: TextStyle(
                          color: isPaused
                              ? const Color(0xFFFDE68A)
                              : (isOpen ? const Color(0xFF4ADE80) : const Color(0xFFCBD5E1)),
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 18, color: Color(0xFF334155)),

          // Address & GPS Pinning Row
          InkWell(
            onTap: () => _openLocationSheet(context),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                    hasGpsPin ? Icons.location_on_rounded : Icons.location_off_rounded,
                    color: hasGpsPin ? AppColors.accentAmber : Colors.redAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          address,
                          style: const TextStyle(
                            color: Color(0xFFE2E8F0),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          hasGpsPin
                              ? 'GPS Coordinates pinned • Tap to re-locate'
                              : '⚠️ GPS Pin Missing! Tap to attach store coordinates',
                          style: TextStyle(
                            color: hasGpsPin ? const Color(0xFF38BDF8) : const Color(0xFFF87171),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B), size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // OPERATING HOURS & AUTO-PAUSE ACTION ROW
          InkWell(
            onTap: () => _openTimingSheet(context),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.schedule_rounded, color: Color(0xFF38BDF8), size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Hours: $openTime - $closeTime',
                        style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 11.5, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isPaused ? const Color(0xFFD97706) : AppColors.accentBlue.withAlpha(51),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(isPaused ? Icons.play_arrow_rounded : Icons.pause_circle_outline_rounded, size: 13, color: Colors.white),
                        const SizedBox(width: 3),
                        Text(
                          isPaused ? 'RESUME NOW' : 'PAUSE STORE',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // PAUSED STORE NOTIFICATION BANNER
          if (isPaused) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.pause_circle_filled_rounded, color: Color(0xFFD97706), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Store Paused for $pauseReason${pauseUntilFormatted.isNotEmpty ? " until $pauseUntilFormatted" : ""}. Orders paused in Customer App.',
                      style: const TextStyle(color: Color(0xFF92400E), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Admin Approval Status Banner
          if (isPendingAdmin) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.hourglass_top_rounded, color: Color(0xFFD97706), size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Store Verification Pending Admin Review (Takes 2-4 hrs). You can add products & manage catalog in the meantime!',
                      style: TextStyle(color: Color(0xFF92400E), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
