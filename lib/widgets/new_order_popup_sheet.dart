import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../screens/orders_screen.dart';
import '../services/firestore_service.dart';
import '../services/order_sound_service.dart';

/// Full-Screen High-Priority Incoming Order Alert Modal for Merchant App
/// STAYS on screen until merchant explicitly taps ACCEPT or REJECT!
/// Supports Single Order & Multi-Order Carousel with 1-Tap Accept All.
class NewOrderPopupSheet extends StatefulWidget {
  final Map<String, dynamic>? orderData;
  final String? orderId;

  const NewOrderPopupSheet({
    super.key,
    this.orderData,
    this.orderId,
  });

  @override
  State<NewOrderPopupSheet> createState() => _NewOrderPopupSheetState();
}

class _NewOrderPopupSheetState extends State<NewOrderPopupSheet>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  int _currentPageIndex = 0;
  Timer? _countdownTimer;
  int _remainingSeconds = 60;
  bool _isSubmitting = false;
  bool _isMuted = false;
  String? _selectedRejectReason;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final List<String> _rejectReasons = [
    'Item Out of Stock / Damaged',
    'Store Closing Soon / Power Failure',
    'Heavy Rush / Kitchen Overloaded',
    'Price / Quantity Mismatch',
    'Delivery Area Not Serviceable',
    'Other Operational Reason',
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Start loud looping alert and vibration
    OrderSoundService.startLoopingAlert();
    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _remainingSeconds = 60;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
      } else {
        timer.cancel();
      }
    });
  }

  void _toggleMute() async {
    final muted = await OrderSoundService.toggleMute();
    setState(() => _isMuted = muted);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _countdownTimer?.cancel();
    OrderSoundService.stopAlert();
    _pulseController.dispose();
    super.dispose();
  }

  double _calculateItemsOnlyTotal(List<dynamic> items) {
    double total = 0.0;
    for (var item in items) {
      final price = item['totalPrice'] ?? item['price'] ?? 0;
      if (price is num) {
        total += price.toDouble();
      } else if (price is String) {
        total += double.tryParse(price) ?? 0.0;
      }
    }
    return total;
  }

  double? _calculateDistanceKm(dynamic custLoc, dynamic storeLoc) {
    double? custLat, custLng, storeLat, storeLng;
    if (custLoc is GeoPoint) {
      custLat = custLoc.latitude;
      custLng = custLoc.longitude;
    } else if (custLoc is Map) {
      custLat = (custLoc['latitude'] ?? custLoc['lat'])?.toDouble();
      custLng = (custLoc['longitude'] ?? custLoc['lng'])?.toDouble();
    }

    if (storeLoc is GeoPoint) {
      storeLat = storeLoc.latitude;
      storeLng = storeLoc.longitude;
    } else if (storeLoc is Map) {
      storeLat = (storeLoc['latitude'] ?? storeLoc['lat'])?.toDouble();
      storeLng = (storeLoc['longitude'] ?? storeLoc['lng'])?.toDouble();
    }

    if (custLat != null && custLng != null && storeLat != null && storeLng != null) {
      const double p = 0.017453292519943295;
      final double c = 0.5 -
          math.cos((storeLat - custLat) * p) / 2 +
          math.cos(custLat * p) * math.cos(storeLat * p) * (1 - math.cos((storeLng - custLng) * p)) / 2;
      return 12742 * math.asin(math.sqrt(c));
    }
    return null;
  }

  void _showRejectReasonDialog(String currentOrderId, Map<String, dynamic> currentOrderData, int remainingOrderCount) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 22),
                SizedBox(width: 8),
                Text('Reject Order', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select a reason to cancel this order:', style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B))),
                  const SizedBox(height: 10),
                  ..._rejectReasons.map((reason) {
                    final isSelected = _selectedRejectReason == reason;
                    return InkWell(
                      onTap: () => setDialogState(() => _selectedRejectReason = reason),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFFFEE2E2) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: isSelected ? Colors.redAccent : const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_off, size: 18, color: isSelected ? Colors.redAccent : Colors.grey),
                            const SizedBox(width: 8),
                            Expanded(child: Text(reason, style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500))),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Back')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                onPressed: _selectedRejectReason == null || _isSubmitting
                    ? null
                    : () async {
                        setDialogState(() => _isSubmitting = true);
                        await FirestoreService.rejectOrder(
                          orderId: currentOrderId,
                          orderData: currentOrderData,
                          reason: _selectedRejectReason!,
                        );

                        if (remainingOrderCount <= 1) {
                          await OrderSoundService.stopAlert();
                          if (context.mounted) {
                            Navigator.pop(ctx);
                            Navigator.pop(context);
                          }
                        } else {
                          if (ctx.mounted) Navigator.pop(ctx);
                        }
                      },
                child: _isSubmitting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Confirm Reject', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _processAcceptSingle(String orderId, Map<String, dynamic> orderData, int remainingOrderCount) async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    try {
      await FirestoreService.acceptOrder(orderId: orderId, orderData: orderData);

      if (remainingOrderCount <= 1) {
        await OrderSoundService.stopAlert();
        if (mounted) {
          Navigator.pop(context);
          Navigator.push(context, MaterialPageRoute(builder: (_) => const OrdersScreen()));
        }
      } else {
        setState(() => _isSubmitting = false);
      }
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error accepting order: $e')));
      }
    }
  }

  Future<void> _processAcceptAll(List<Map<String, dynamic>> orders) async {
    if (_isSubmitting || orders.isEmpty) return;
    setState(() => _isSubmitting = true);
    await OrderSoundService.stopAlert();

    try {
      await FirestoreService.acceptAllOrders(orders: orders);
      if (mounted) {
        Navigator.pop(context);
        Navigator.push(context, MaterialPageRoute(builder: (_) => const OrdersScreen()));
      }
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error batch accepting: $e')));
      }
    }
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
        // Collect orders from stream
        List<Map<String, dynamic>> pendingOrders = [];

        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          for (var doc in snapshot.data!.docs) {
            final data = Map<String, dynamic>.from(doc.data() as Map);
            final s = (data['orderStatus'] ?? data['status'] ?? '').toString().toLowerCase();
            if (s == 'pending' || s == 'placed' || s == 'ordered') {
              data['id'] = doc.id;
              data['orderId'] = data['orderId'] ?? doc.id;
              pendingOrders.add(data);
            }
          }
        }

        // If Stream is still loading or returned empty, but widget.orderData was passed, use it!
        if (pendingOrders.isEmpty && widget.orderData != null) {
          final fallbackData = Map<String, dynamic>.from(widget.orderData!);
          fallbackData['id'] = widget.orderId ?? 'ORD-001';
          fallbackData['orderId'] = fallbackData['orderId'] ?? widget.orderId ?? 'ORD-001';
          pendingOrders.add(fallbackData);
        }

        // If STILL empty AND stream finished loading, close sheet
        if (pendingOrders.isEmpty && snapshot.connectionState != ConnectionState.waiting) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            OrderSoundService.stopAlert();
            if (mounted && Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          });
          return const SizedBox.shrink();
        }

        if (pendingOrders.isEmpty) {
          // While waiting, show real orderData passed in widget
          return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
        }

        final int totalOrdersCount = pendingOrders.length;
        if (_currentPageIndex >= totalOrdersCount) {
          _currentPageIndex = totalOrdersCount - 1;
        }

        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. MULTI-ORDER EMERGENCY ALERT HEADER
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFDC2626), Color(0xFFEA580C)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Row(
                  children: [
                    ScaleTransition(
                      scale: _pulseAnimation,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                        child: const Icon(Icons.notifications_active_rounded, color: Color(0xFFDC2626), size: 24),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                totalOrdersCount > 1
                                    ? '🚨 $totalOrdersCount NEW ORDERS!'
                                    : 'NEW INCOMING ORDER!',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5),
                              ),
                              if (totalOrdersCount > 1) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.black.withAlpha(50), borderRadius: BorderRadius.circular(6)),
                                  child: Text('${_currentPageIndex + 1} of $totalOrdersCount', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ],
                          ),
                          Row(
                            children: [
                              const Icon(Icons.timer_outlined, size: 14, color: Colors.white70),
                              const SizedBox(width: 4),
                              Text('Auto-expires in ${_remainingSeconds}s', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: _isMuted ? 'Unmute Ringtone' : 'Mute Ringtone',
                      onPressed: _toggleMute,
                      icon: Icon(_isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: Colors.white),
                    ),
                  ],
                ),
              ),

              // 2. HORIZONTAL MULTI-ORDER CAROUSEL / PAGEVIEW
              Flexible(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: totalOrdersCount,
                  onPageChanged: (idx) {
                    setState(() {
                      _currentPageIndex = idx;
                    });
                  },
                  itemBuilder: (context, index) {
                    final currentData = pendingOrders[index];
                    final currentOrderId = (currentData['orderId'] ?? currentData['id']).toString();

                    return _buildSingleOrderCard(
                      orderId: currentOrderId,
                      orderData: currentData,
                      orderIndex: index,
                      totalCount: totalOrdersCount,
                    );
                  },
                ),
              ),

              // Carousel Page Indicator Dots (If > 1 Order)
              if (totalOrdersCount > 1) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(totalOrdersCount, (dotIdx) {
                      final isSelected = dotIdx == _currentPageIndex;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: isSelected ? 20 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFFDC2626) : const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      );
                    }),
                  ),
                ),
              ],

              // 3. ACTION BAR: (ACCEPT ALL vs CURRENT ACCEPT/REJECT)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                color: Colors.white,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // BATCH 1-TAP ACCEPT ALL BUTTON (If more than 1 order)
                    if (totalOrdersCount > 1) ...[
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F172A),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 2,
                          ),
                          onPressed: _isSubmitting ? null : () => _processAcceptAll(pendingOrders),
                          icon: const Icon(Icons.flash_on_rounded, color: AppColors.accentYellow, size: 20),
                          label: Text(
                            '⚡ ACCEPT ALL ($totalOrdersCount ORDERS)',
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, letterSpacing: 0.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    // Current Card Single Action Buttons
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                              side: const BorderSide(color: Colors.redAccent, width: 1.5),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () {
                              final currentData = pendingOrders[_currentPageIndex];
                              final currentOrderId = (currentData['orderId'] ?? currentData['id']).toString();
                              _showRejectReasonDialog(
                                currentOrderId,
                                currentData,
                                totalOrdersCount,
                              );
                            },
                            child: const Text('REJECT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 7,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryGreen,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              elevation: 2,
                            ),
                            onPressed: _isSubmitting
                                ? null
                                : () {
                                    final currentData = pendingOrders[_currentPageIndex];
                                    final currentOrderId = (currentData['orderId'] ?? currentData['id']).toString();
                                    _processAcceptSingle(
                                      currentOrderId,
                                      currentData,
                                      totalOrdersCount,
                                    );
                                  },
                            icon: _isSubmitting
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Icon(Icons.check_circle_rounded, size: 18),
                            label: Text(
                              totalOrdersCount > 1
                                  ? 'ACCEPT THIS ORDER (#${_currentPageIndex + 1})'
                                  : 'ACCEPT & START PACKING',
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSingleOrderCard({
    required String orderId,
    required Map<String, dynamic> orderData,
    required int orderIndex,
    required int totalCount,
  }) {
    final customerName = (orderData['customerName'] ?? orderData['userName'] ?? 'Customer').toString();
    final items = (orderData['items'] as List<dynamic>?) ?? [];
    final deliveryAddress = (orderData['deliveryAddress'] ?? 'Standard Doorstep Delivery, Nellore').toString();
    final paymentMethod = (orderData['paymentMethod'] ?? 'COD').toString();
    final bool isOnline = paymentMethod.toUpperCase().contains('ONLINE') || paymentMethod.toUpperCase().contains('UPI');

    final double itemsOnlyTotal = _calculateItemsOnlyTotal(items);
    final double grandTotal = (orderData['grandTotal'] ?? orderData['totalAmount'] ?? itemsOnlyTotal).toDouble();
    final double? distanceKm = _calculateDistanceKm(
      orderData['customerLocation'] ?? orderData['deliveryLocation'],
      orderData['storeLocation'] ?? orderData['merchantLocation'],
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Order #, Payment Badge & Customer Info
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Order #$orderId', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.textDark)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isOnline ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isOnline ? const Color(0xFF86EFAC) : const Color(0xFFFDE68A)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(isOnline ? Icons.check_circle_rounded : Icons.payments_rounded, size: 14, color: isOnline ? const Color(0xFF15803D) : const Color(0xFFB45309)),
                          const SizedBox(width: 4),
                          Text(
                            isOnline ? 'PAID ONLINE (UPI)' : 'CASH ON DELIVERY',
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: isOnline ? const Color(0xFF15803D) : const Color(0xFFB45309)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 18),
                Text(customerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.location_on, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Expanded(child: Text(deliveryAddress, style: const TextStyle(fontSize: 12, color: Colors.black87), maxLines: 1)),
                    if (distanceKm != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(4)),
                        child: Text('${distanceKm.toStringAsFixed(1)} km', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Itemized Packing List Preview
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('ITEMS TO PACK (${items.length})', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: AppColors.textMuted, letterSpacing: 0.5)),
                    Text('Total: ₹${grandTotal.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.primaryGreen)),
                  ],
                ),
                const Divider(height: 14),
                ...items.map((it) {
                  final item = it as Map<String, dynamic>;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: AppColors.primaryGreenLight, borderRadius: BorderRadius.circular(6)),
                              child: Text('${item['quantity'] ?? 1}x', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: AppColors.primaryGreen)),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item['name'] ?? 'Item', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                if ((item['unit'] ?? '').toString().isNotEmpty)
                                  Text(item['unit'].toString(), style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                              ],
                            ),
                          ],
                        ),
                        Text('₹${item['totalPrice'] ?? item['price'] ?? 0}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
