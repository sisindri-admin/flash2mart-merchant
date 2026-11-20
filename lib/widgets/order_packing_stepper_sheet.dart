import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../services/firestore_service.dart';
import '../services/communication_service.dart';

/// Full-featured Kitchen Packing & Stepper Modal
/// Includes:
/// 1. Visual Status Stepper (Placed -> Accepted -> Packing -> Ready -> Out -> Delivered)
/// 2. Interactive Item Packing Checklist (Tick items as they are put in bag)
/// 3. Delivery Partner Handover OTP Card
/// 4. Order Slip / Printable Invoice preview
class OrderPackingStepperSheet extends StatefulWidget {
  final String orderId;
  final Map<String, dynamic> initialData;

  const OrderPackingStepperSheet({
    super.key,
    required this.orderId,
    required this.initialData,
  });

  @override
  State<OrderPackingStepperSheet> createState() => _OrderPackingStepperSheetState();
}

class _OrderPackingStepperSheetState extends State<OrderPackingStepperSheet> {
  final TextEditingController _otpVerifyController = TextEditingController();
  bool _isUpdating = false;

  @override
  void dispose() {
    _otpVerifyController.dispose();
    super.dispose();
  }

  int _getStepIndex(String status) {
    final s = status.trim().toLowerCase();
    if (s == 'placed' || s == 'pending' || s == 'accepted' || s == 'preparing') return 1;
    if (s == 'packing_ready' || s == 'packed' || s == 'ready') return 2;
    if (s == 'out_for_delivery' || s == 'picked_up' || s == 'on_the_way') return 3;
    if (s == 'delivered' || s == 'completed') return 4;
    return 1;
  }

  void _showOrderSlip(BuildContext context, Map<String, dynamic> data) {
    final items = (data['items'] as List<dynamic>?) ?? [];
    final customer = (data['customerName'] ?? data['userName'] ?? 'Customer').toString();
    final phone = (data['customerPhone'] ?? data['phone'] ?? '').toString();
    final address = (data['deliveryAddress'] ?? 'Nellore Doorstep').toString();
    final total = (data['grandTotal'] ?? data['totalAmount'] ?? data['itemsTotal'] ?? 0).toDouble();
    final payment = (data['paymentMethod'] ?? 'COD').toString();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              children: [
                Icon(Icons.receipt_rounded, color: AppColors.primaryGreen, size: 22),
                SizedBox(width: 8),
                Text('Order Slip / Invoice', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Column(
                  children: [
                    const Text('FLASH2MART', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.primaryGreen, letterSpacing: 1.2)),
                    const Text('Quick Commerce Store Slip', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    const SizedBox(height: 6),
                    Text('Order #${widget.orderId}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                  ],
                ),
              ),
              const Divider(height: 20),
              Text('Customer: $customer', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              if (phone.isNotEmpty) Text('Phone: $phone', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              Text('Address: $address', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
              const SizedBox(height: 4),
              Text('Payment: ${payment.toUpperCase()}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.accentBlue)),
              const Divider(height: 20),
              const Text('ITEM LIST:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 6),
              ...items.map((it) {
                final item = it as Map<String, dynamic>;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${item['quantity'] ?? 1}x ${item['name'] ?? 'Item'}', style: const TextStyle(fontSize: 12)),
                      Text('₹${item['totalPrice'] ?? item['price'] ?? 0}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                );
              }),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('GRAND TOTAL:', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                  Text('₹${total.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.primaryGreen)),
                ],
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx),
            icon: const Icon(Icons.check, size: 16),
            label: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('orders').doc(widget.orderId).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.hasData && snapshot.data!.exists
            ? snapshot.data!.data() as Map<String, dynamic>
            : widget.initialData;

        final status = (data['orderStatus'] ?? data['status'] ?? 'Preparing').toString();
        final currentStep = _getStepIndex(status);
        final items = (data['items'] as List<dynamic>?) ?? [];
        final pickupOtp = (data['pickupOtp'] ?? '----').toString();
        final total = (data['grandTotal'] ?? data['totalAmount'] ?? data['itemsTotal'] ?? 0).toDouble();

        // Calculate packed items count
        final int packedCount = items.where((it) => (it as Map)['isPacked'] == true).length;
        final double progress = items.isNotEmpty ? (packedCount / items.length) : 0.0;
        final bool allPacked = items.isNotEmpty && packedCount == items.length;

        final isPreparing = currentStep <= 1;
        final isPackedReady = currentStep == 2;
        final isOut = currentStep == 3;
        final isDelivered = currentStep == 4;

        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Sheet Drag Indicator
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
                ),
              ),

              // Title Bar with Order ID & Print Slip
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Order #${widget.orderId}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.textDark)),
                        Text('Live Kitchen & Packing Stepper', style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    IconButton(
                      tooltip: 'View / Print Slip',
                      icon: const Icon(Icons.receipt_long_rounded, color: AppColors.accentBlue),
                      onPressed: () => _showOrderSlip(context, data),
                    ),
                  ],
                ),
              ),

              const Divider(height: 12),

              // Scrollable Body
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. VISUAL STEPPER WIDGET
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.cardBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('ORDER WORKFLOW TRACKING', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5, color: AppColors.textMuted, letterSpacing: 0.5)),
                            const SizedBox(height: 14),
                            _buildStepperVisual(currentStep),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 2. REAL-TIME DELIVERY PARTNER DETAILS (SYNCED FROM FIRESTORE)
                      if (isPackedReady || isOut) ...[
                        Builder(
                          builder: (context) {
                            final String partnerId = (data['deliveryPartnerId'] ?? data['riderId'] ?? '').toString().trim();
                            final bool hasRider = partnerId.isNotEmpty;

                            if (!hasRider) {
                              // WAITING FOR RIDER STATE (ZERO DUMMY DATA)
                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: const Color(0xFF38BDF8).withAlpha(100), width: 1.5),
                                  boxShadow: const [
                                    BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 4)),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(color: const Color(0xFF38BDF8).withAlpha(40), shape: BoxShape.circle),
                                          child: const Icon(Icons.radar_rounded, color: Color(0xFF38BDF8), size: 22),
                                        ),
                                        const SizedBox(width: 10),
                                        const Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'FINDING NEARBY DELIVERY PARTNER...',
                                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12.5),
                                              ),
                                              SizedBox(height: 2),
                                              Text(
                                                'Order broadcasted to active Flash2Mart riders in Nellore',
                                                style: TextStyle(color: Colors.white70, fontSize: 11),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8))),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    // Pickup Handover OTP Box
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withAlpha(20),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: AppColors.accentYellow),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text(
                                            'Pickup Handover OTP (Verify with Rider):',
                                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5),
                                          ),
                                          Text(
                                            pickupOtp,
                                            style: const TextStyle(color: AppColors.accentYellow, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 3),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            // RIDER ASSIGNED: LIVE STREAM REAL DATA FROM delivery_partners/{partnerId}
                            return StreamBuilder<DocumentSnapshot>(
                              stream: FirebaseFirestore.instance.collection('delivery_partners').doc(partnerId).snapshots(),
                              builder: (context, riderSnap) {
                                Map<String, dynamic> riderData = {};
                                if (riderSnap.hasData && riderSnap.data!.exists) {
                                  riderData = riderSnap.data!.data() as Map<String, dynamic>;
                                }

                                final realName = (riderData['fullName'] ?? riderData['name'] ?? data['deliveryPartnerName'] ?? 'Flash2Mart Delivery Partner').toString();
                                final realPhone = (riderData['phone'] ?? data['deliveryPartnerPhone'] ?? '').toString();
                                final realBike = (riderData['vehicleNumber'] ?? riderData['bikeNumber'] ?? data['vehicleNumber'] ?? 'Two Wheeler').toString();

                                final bool reachedStore = data['reachedStoreAt'] != null ||
                                    data['status'] == 'Reached_Store' ||
                                    (data['riderStatus'] ?? '').toString().toLowerCase().contains('reached');

                                final String liveStatus = reachedStore
                                    ? '📍 Reached Store Doorstep!'
                                    : (isOut ? '🛵 Out for Delivery to Customer' : '🛵 On the way to your store');

                                return Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: reachedStore ? const Color(0xFF4ADE80) : AppColors.accentYellow.withAlpha(120), width: 1.5),
                                    boxShadow: const [
                                      BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 4)),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Row(
                                            children: [
                                              Icon(Icons.delivery_dining_rounded, color: AppColors.accentYellow, size: 24),
                                              SizedBox(width: 8),
                                              Text(
                                                'ASSIGNED DELIVERY PARTNER',
                                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12.5, letterSpacing: 0.5),
                                              ),
                                            ],
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: reachedStore
                                                  ? AppColors.primaryGreen
                                                  : (isOut ? AppColors.accentBlue : AppColors.accentYellow),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              reachedStore
                                                  ? 'ARRIVED AT STORE'
                                                  : (isOut ? 'BAG HANDED OVER' : 'ARRIVING FOR PICKUP'),
                                              style: TextStyle(
                                                fontWeight: FontWeight.w900,
                                                fontSize: 10,
                                                color: reachedStore || isOut ? Colors.white : Colors.black,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),

                                      // Real Rider Profile Row
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withAlpha(15),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: const BoxDecoration(color: AppColors.accentYellow, shape: BoxShape.circle),
                                              child: const Icon(Icons.person_rounded, color: Colors.black, size: 20),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    realName,
                                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    'Bike: $realBike • $liveStatus',
                                                    style: TextStyle(
                                                      color: reachedStore ? const Color(0xFF86EFAC) : Colors.white70,
                                                      fontSize: 11,
                                                      fontWeight: reachedStore ? FontWeight.bold : FontWeight.normal,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 10),

                                      // Real 1-Tap Call & WhatsApp Action Buttons
                                      Row(
                                        children: [
                                          // 1-Tap Phone Call (Opens Dialer with real number pasted)
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(0xFF2563EB),
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(vertical: 10),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                              ),
                                              onPressed: realPhone.isNotEmpty
                                                  ? () => CommunicationService.callPhoneNumber(realPhone)
                                                  : null,
                                              icon: const Icon(Icons.call_rounded, size: 16),
                                              label: const Text('CALL RIDER', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5)),
                                            ),
                                          ),
                                          const SizedBox(width: 8),

                                          // 1-Tap WhatsApp (Opens WhatsApp with pre-filled pickup message)
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(0xFF16A34A),
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(vertical: 10),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                              ),
                                              onPressed: realPhone.isNotEmpty
                                                  ? () {
                                                      CommunicationService.openWhatsApp(
                                                        phone: realPhone,
                                                        message: 'Hi $realName, Flash2Mart Order #${widget.orderId} is packed & ready for pickup at our store. Pickup OTP is: $pickupOtp. Please collect.',
                                                      );
                                                    }
                                                  : null,
                                              icon: const Icon(Icons.chat_rounded, size: 16),
                                              label: const Text('WHATSAPP', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5)),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),

                                      // Pickup OTP Box
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withAlpha(20),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: AppColors.accentYellow),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text(
                                              'Pickup Handover OTP:',
                                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                            ),
                                            Text(
                                              pickupOtp,
                                              style: const TextStyle(color: AppColors.accentYellow, fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: 4),
                                            ),
                                          ],
                                        ),
                                      ),

                                      if (isPackedReady) ...[
                                        const SizedBox(height: 10),
                                        SizedBox(
                                          width: double.infinity,
                                          height: 40,
                                          child: ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: AppColors.accentYellow,
                                              foregroundColor: Colors.black,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            ),
                                            onPressed: () async {
                                              await FirestoreService.updateOrderStatusWithTracking(
                                                orderId: widget.orderId,
                                                newStatus: 'Out_for_Delivery',
                                                title: 'Store handed over bag to delivery partner',
                                                updatedBy: 'Merchant',
                                              );
                                            },
                                            icon: const Icon(Icons.handshake_rounded, size: 18),
                                            label: const Text('CONFIRM HANDOVER TO RIDER', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),
                        const SizedBox(height: 14),
                      ],
                      // 3. INTERACTIVE KITCHEN PACKING CHECKLIST
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppColors.cardBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('PACKING CHECKLIST', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: AppColors.textDark)),
                                Text('$packedCount / ${items.length} Packed', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: allPacked ? AppColors.primaryGreen : AppColors.accentBlue)),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // Progress Bar
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 6,
                                backgroundColor: const Color(0xFFF1F5F9),
                                valueColor: AlwaysStoppedAnimation<Color>(allPacked ? AppColors.primaryGreen : AppColors.accentBlue),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // List of items with checkboxes
                            ...items.asMap().entries.map((entry) {
                              final int index = entry.key;
                              final item = entry.value as Map<String, dynamic>;
                              final bool isPacked = item['isPacked'] == true;

                              return InkWell(
                                onTap: isDelivered || isOut
                                    ? null
                                    : () async {
                                        await FirestoreService.updateItemPackedStatus(
                                          orderId: widget.orderId,
                                          items: items,
                                          itemIndex: index,
                                          isPacked: !isPacked,
                                        );
                                      },
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isPacked ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isPacked ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isPacked ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                        color: isPacked ? AppColors.primaryGreen : const Color(0xFF94A3B8),
                                        size: 22,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${item['quantity'] ?? 1}x ${item['name'] ?? 'Product'}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                                decoration: isPacked ? TextDecoration.lineThrough : null,
                                                color: isPacked ? const Color(0xFF15803D) : AppColors.textDark,
                                              ),
                                            ),
                                            if ((item['unit'] ?? '').toString().isNotEmpty)
                                              Text(
                                                item['unit'].toString(),
                                                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        '₹${item['totalPrice'] ?? item['price'] ?? 0}',
                                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Order Summary Bar
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Grand Total Billable:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textDark)),
                            Text('₹${total.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.primaryGreen)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom Primary Action Button
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                color: Colors.white,
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isPreparing
                          ? (allPacked ? AppColors.primaryGreen : AppColors.accentBlue)
                          : (isPackedReady ? const Color(0xFFF59E0B) : const Color(0xFF0F172A)),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 1,
                    ),
                    onPressed: _isUpdating || isDelivered
                        ? null
                        : () async {
                            setState(() => _isUpdating = true);
                            if (isPreparing) {
                              await FirestoreService.markOrderPackingReady(widget.orderId);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('✅ Order packed! Ready for Delivery Partner pickup.'),
                                    backgroundColor: AppColors.primaryGreen,
                                  ),
                                );
                              }
                            } else if (isPackedReady) {
                              await FirestoreService.updateOrderStatusWithTracking(
                                orderId: widget.orderId,
                                newStatus: 'Out_for_Delivery',
                                title: 'Store handed over bag to delivery partner',
                                updatedBy: 'Merchant',
                              );
                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('🛵 Bag handed over to delivery partner! Out for Delivery.'),
                                    backgroundColor: AppColors.primaryGreen,
                                  ),
                                );
                              }
                            }
                            if (mounted) setState(() => _isUpdating = false);
                          },
                    child: Text(
                      isPreparing
                          ? (allPacked ? 'MARK PACKED & CALL RIDER' : 'MARK ALL PACKED (READY)')
                          : (isPackedReady ? 'CONFIRM HANDOVER (OTP: $pickupOtp)' : (isOut ? 'OUT FOR DELIVERY' : 'COMPLETED')),
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, letterSpacing: 0.3),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStepperVisual(int currentStep) {
    final steps = [
      {'title': 'Placed', 'icon': Icons.shopping_bag_outlined},
      {'title': 'Preparing', 'icon': Icons.soup_kitchen_rounded},
      {'title': 'Packed', 'icon': Icons.inventory_2_rounded},
      {'title': 'On Road', 'icon': Icons.moped_rounded},
      {'title': 'Delivered', 'icon': Icons.check_circle_rounded},
    ];

    return Row(
      children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          final lineIndex = i ~/ 2;
          final isCompleted = currentStep > lineIndex;
          return Expanded(
            child: Container(
              height: 3,
              color: isCompleted ? AppColors.primaryGreen : const Color(0xFFE2E8F0),
            ),
          );
        }

        final stepIndex = i ~/ 2;
        final isCompleted = currentStep >= stepIndex;
        final isCurrent = currentStep == stepIndex;

        return Column(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isCurrent
                    ? AppColors.primaryGreen
                    : (isCompleted ? AppColors.primaryGreenLight : const Color(0xFFF1F5F9)),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isCurrent || isCompleted ? AppColors.primaryGreen : const Color(0xFFCBD5E1),
                  width: isCurrent ? 2 : 1,
                ),
              ),
              child: Icon(
                steps[stepIndex]['icon'] as IconData,
                size: 16,
                color: isCurrent
                    ? Colors.white
                    : (isCompleted ? AppColors.primaryGreen : const Color(0xFF94A3B8)),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              steps[stepIndex]['title'] as String,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w600,
                color: isCurrent ? AppColors.primaryGreen : AppColors.textMuted,
              ),
            ),
          ],
        );
      }),
    );
  }
}
