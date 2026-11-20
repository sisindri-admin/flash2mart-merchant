import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../order_packing_stepper_sheet.dart';

/// Pinned Active Order Progress Floating Banner for Merchant App
/// Visible across the screen from the moment merchant accepts an order
/// until delivery partner picks it up (Handover completed).
/// Features:
/// 1. Real-time Firestore stream of active kitchen orders
/// 2. Stage 1 (Preparing): Packing progress (2/3 items packed) & elapsed kitchen timer
/// 3. Stage 2 (Packing Ready): Rider arrival status & Bold Pickup OTP Card [ 4892 ]
/// 4. Multi-Order Auto-Slide: Smoothly cycles between orders if 2+ orders are active
/// 5. 1-Tap Tap-to-Open: Immediately opens OrderPackingStepperSheet
/// 6. Auto-hides when 0 active orders remain (Zero space consumed)
class MerchantActiveOrderBanner extends StatefulWidget {
  const MerchantActiveOrderBanner({super.key});

  @override
  State<MerchantActiveOrderBanner> createState() => _MerchantActiveOrderBannerState();
}

class _MerchantActiveOrderBannerState extends State<MerchantActiveOrderBanner>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  Timer? _autoSlideTimer;
  Timer? _tickerTimer;
  int _currentIndex = 0;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // 1-second ticker for live elapsed kitchen clock
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _startAutoSlide(int totalOrders) {
    _autoSlideTimer?.cancel();
    if (totalOrders <= 1) return;

    _autoSlideTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      if (_pageController.hasClients) {
        final nextIdx = (_currentIndex + 1) % totalOrders;
        _pageController.animateToPage(
          nextIdx,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _autoSlideTimer?.cancel();
    _tickerTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  String _formatElapsedClock(dynamic timestamp) {
    if (timestamp is Timestamp) {
      final diff = DateTime.now().difference(timestamp.toDate());
      final minutes = diff.inMinutes;
      final seconds = diff.inSeconds % 60;
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '00:00';
  }

  void _openStepper(BuildContext context, String orderId, Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => OrderPackingStepperSheet(
        orderId: orderId,
        initialData: data,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('merchantId', isEqualTo: user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final allDocs = snapshot.data!.docs;

        // Filter active kitchen orders: Preparing or Ready for Rider Pickup
        final activeDocs = allDocs.where((d) {
          final s = ((d.data() as Map)['orderStatus'] ?? (d.data() as Map)['status'] ?? '').toString().toLowerCase();
          return s == 'preparing' ||
              s == 'accepted' ||
              s == 'packing_ready' ||
              s == 'ready' ||
              s == 'packed';
        }).toList()
          ..sort((a, b) {
            final dynamic tA = (a.data() as Map)['createdAt'] ?? (a.data() as Map)['acceptedAt'];
            final dynamic tB = (b.data() as Map)['createdAt'] ?? (b.data() as Map)['acceptedAt'];
            if (tA is Timestamp && tB is Timestamp) {
              return tA.compareTo(tB); // FIFO
            }
            return 0;
          });

        if (activeDocs.isEmpty) {
          _autoSlideTimer?.cancel();
          return const SizedBox.shrink();
        }

        final int totalActive = activeDocs.length;
        if (_currentIndex >= totalActive) {
          _currentIndex = totalActive - 1;
        }

        // Start auto-slide if more than 1 active order
        _startAutoSlide(totalActive);

        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            height: 94,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF38BDF8).withAlpha(102),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(50),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: PageView.builder(
              controller: _pageController,
              itemCount: totalActive,
              onPageChanged: (idx) {
                setState(() => _currentIndex = idx);
              },
              itemBuilder: (context, index) {
                final doc = activeDocs[index];
                final data = doc.data() as Map<String, dynamic>;
                final orderId = (data['orderId'] ?? doc.id).toString();
                final customer = (data['customerName'] ?? data['userName'] ?? 'Customer').toString();
                final status = (data['orderStatus'] ?? data['status'] ?? 'Preparing').toString();
                final pickupOtp = (data['pickupOtp'] ?? '----').toString();
                final items = (data['items'] as List<dynamic>?) ?? [];
                final timeClock = _formatElapsedClock(data['createdAt'] ?? data['acceptedAt']);

                final isReadyForRider = status.toLowerCase() == 'packing_ready' ||
                    status.toLowerCase() == 'ready' ||
                    status.toLowerCase() == 'packed';

                final int packedCount = items.where((it) => (it as Map)['isPacked'] == true).length;
                final double progress = items.isNotEmpty ? (packedCount / items.length) : 0.0;

                return InkWell(
                  onTap: () => _openStepper(context, doc.id, data),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Top Row: Order ID, Multi-Order Counter, Live Status Tag
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                ScaleTransition(
                                  scale: _pulseAnimation,
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isReadyForRider ? AppColors.accentYellow : const Color(0xFF4ADE80),
                                      boxShadow: [
                                        BoxShadow(
                                          color: isReadyForRider ? AppColors.accentYellow : const Color(0xFF4ADE80),
                                          blurRadius: 6,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Order #$orderId',
                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, color: Colors.white),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '• $customer',
                                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),

                            // Multi-Order Counter or Clock
                            Row(
                              children: [
                                if (totalActive > 1) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    margin: const EdgeInsets.only(right: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF334155),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${index + 1}/$totalActive Active',
                                      style: const TextStyle(color: AppColors.accentYellow, fontSize: 9.5, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withAlpha(60),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.timer_outlined, size: 11, color: Colors.white70),
                                      const SizedBox(width: 3),
                                      Text(
                                        timeClock,
                                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        // Middle Content: Stage 1 (Packing Progress) vs Stage 2 (Rider Pickup OTP)
                        if (!isReadyForRider) ...[
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: AppColors.accentBlue.withAlpha(51),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.soup_kitchen_rounded, color: Color(0xFF38BDF8), size: 16),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'Packing in Kitchen',
                                          style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.w900, fontSize: 11.5),
                                        ),
                                        Text(
                                          '$packedCount/${items.length} Items Packed (${(progress * 100).round()}%)',
                                          style: const TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: progress,
                                        minHeight: 4,
                                        backgroundColor: const Color(0xFF334155),
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          packedCount == items.length ? const Color(0xFF4ADE80) : const Color(0xFF38BDF8),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white60, size: 13),
                            ],
                          ),
                        ] else ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFD97706).withAlpha(51),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.moped_rounded, color: AppColors.accentYellow, size: 18),
                                  ),
                                  const SizedBox(width: 8),
                                  const Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'RIDER ARRIVING FOR PICKUP',
                                        style: TextStyle(color: AppColors.accentYellow, fontWeight: FontWeight.w900, fontSize: 11),
                                      ),
                                      Text(
                                        'Show OTP when delivery boy arrives',
                                        style: TextStyle(color: Colors.white70, fontSize: 10),
                                      ),
                                    ],
                                  ),
                                ],
                              ),

                              // BOLD PICKUP OTP BADGE
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.accentYellow,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.key_rounded, size: 14, color: Colors.black),
                                    const SizedBox(width: 4),
                                    Text(
                                      'OTP: $pickupOtp',
                                      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1.5),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],

                        // Bottom Tap to Open Hint
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              isReadyForRider
                                  ? 'Tap to confirm handover to rider ➔'
                                  : 'Tap to view checklist & mark packed ➔',
                              style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
