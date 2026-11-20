import '../services/order_sound_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../services/firestore_service.dart';
import '../services/communication_service.dart';
import '../widgets/order_packing_stepper_sheet.dart';

/// Comprehensive Kitchen & Live Orders Management Screen for Merchant App
/// Upgraded for Multi-Order Handling:
/// 1. FIFO & SLA Priority Sorting (Oldest & Urgent orders on top)
/// 2. Multi-Order Batch Picking Summary (Picks items for 2+ orders in 1 trip)
/// 3. Urgency Timer Badges (Urgent SLA 5m+, Packing 2m+, Fresh)
/// 4. 4 Workflow Queues (Packing, Ready OTP, On Road, History)
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isBatchPickingExpanded = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openPackingStepper(BuildContext context, String orderId, Map<String, dynamic> data) {
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

  String _formatRelativeTime(dynamic timestamp) {
    if (timestamp is Timestamp) {
      final dt = timestamp.toDate();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${dt.day}/${dt.month} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '';
  }

  int _getElapsedMinutes(dynamic timestamp) {
    if (timestamp is Timestamp) {
      return DateTime.now().difference(timestamp.toDate()).inMinutes;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Please log in.')));
    }

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.soup_kitchen_rounded, color: AppColors.primaryGreen, size: 22),
            SizedBox(width: 8),
            Text(
              'Kitchen & Order Stepper',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: AppColors.textDark),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        foregroundColor: AppColors.textDark,
        actions: [
          IconButton(
            tooltip: 'Test Order Ringtone',
            icon: const Icon(Icons.volume_up_rounded, color: Color(0xFFEA580C)),
            onPressed: () => OrderSoundService.testRingtone(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primaryGreen,
          indicatorWeight: 3,
          labelColor: AppColors.primaryGreen,
          unselectedLabelColor: AppColors.textMuted,
          labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5),
          tabs: const [
            Tab(text: 'PACKING'),
            Tab(text: 'READY (OTP)'),
            Tab(text: 'ON ROAD'),
            Tab(text: 'HISTORY'),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .where('merchantId', isEqualTo: user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
          }

          final allDocs = snapshot.hasData ? snapshot.data!.docs : <QueryDocumentSnapshot>[];

          // 1. Preparing / Packing Queue (Sorted by oldest first for FIFO SLA)
          final preparingDocs = allDocs.where((d) {
            final s = ((d.data() as Map)['orderStatus'] ?? (d.data() as Map)['status'] ?? '').toString().toLowerCase();
            return s == 'preparing' || s == 'placed' || s == 'pending' || s == 'accepted';
          }).toList()
            ..sort((a, b) {
              final dynamic tA = (a.data() as Map)['createdAt'] ?? (a.data() as Map)['acceptedAt'];
              final dynamic tB = (b.data() as Map)['createdAt'] ?? (b.data() as Map)['acceptedAt'];
              if (tA is Timestamp && tB is Timestamp) {
                return tA.compareTo(tB); // Oldest first
              }
              return 0;
            });

          // 2. Ready for Pickup Queue
          final readyDocs = allDocs.where((d) {
            final s = ((d.data() as Map)['orderStatus'] ?? (d.data() as Map)['status'] ?? '').toString().toLowerCase();
            return s == 'packing_ready' || s == 'ready' || s == 'packed';
          }).toList();

          // 3. Out for Delivery Queue
          final outDocs = allDocs.where((d) {
            final s = ((d.data() as Map)['orderStatus'] ?? (d.data() as Map)['status'] ?? '').toString().toLowerCase();
            return s == 'out_for_delivery' || s == 'picked_up' || s == 'on_the_way';
          }).toList();

          // 4. Delivered / History Queue
          final historyDocs = allDocs.where((d) {
            final s = ((d.data() as Map)['orderStatus'] ?? (d.data() as Map)['status'] ?? '').toString().toLowerCase();
            return s == 'delivered' || s == 'completed' || s == 'cancelled';
          }).toList();

          return TabBarView(
            controller: _tabController,
            children: [
              _buildOrdersQueue(preparingDocs, 'preparing'),
              _buildOrdersQueue(readyDocs, 'ready'),
              _buildOrdersQueue(outDocs, 'out'),
              _buildOrdersQueue(historyDocs, 'history'),
            ],
          );
        },
      ),
    );
  }

  Widget _buildOrdersQueue(List<QueryDocumentSnapshot> docs, String queueType) {
    if (docs.isEmpty) {
      String msg = 'No orders currently being packed';
      IconData icon = Icons.kitchen_rounded;
      if (queueType == 'ready') {
        msg = 'No orders waiting for delivery partner pickup';
        icon = Icons.moped_rounded;
      } else if (queueType == 'out') {
        msg = 'No orders currently on the road';
        icon = Icons.delivery_dining_rounded;
      } else if (queueType == 'history') {
        msg = 'No past orders recorded yet';
        icon = Icons.history_rounded;
      }

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 54, color: Colors.grey.shade300),
            const SizedBox(height: 10),
            Text(msg, style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      );
    }

    // Build Aggregated Batch Picking Items if > 1 order in preparing queue
    final Map<String, int> batchItems = {};
    if (queueType == 'preparing' && docs.length > 1) {
      for (var d in docs) {
        final data = d.data() as Map<String, dynamic>;
        final items = (data['items'] as List<dynamic>?) ?? [];
        for (var it in items) {
          final item = it as Map<String, dynamic>;
          final name = (item['name'] ?? 'Item').toString();
          final qty = (item['quantity'] ?? 1) is num ? (item['quantity'] as num).toInt() : 1;
          batchItems[name] = (batchItems[name] ?? 0) + qty;
        }
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // MULTI-ORDER BATCH PICKING SUMMARY CARD (Only when > 1 order in kitchen)
        if (queueType == 'preparing' && docs.length > 1) ...[
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 8, offset: const Offset(0, 3)),
              ],
            ),
            child: Column(
              children: [
                InkWell(
                  onTap: () => setState(() => _isBatchPickingExpanded = !_isBatchPickingExpanded),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(color: AppColors.accentYellow, borderRadius: BorderRadius.circular(8)),
                              child: const Icon(Icons.all_inbox_rounded, color: Colors.black, size: 18),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text('BATCH PICKING LIST', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12.5, letterSpacing: 0.5)),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                      decoration: BoxDecoration(color: const Color(0xFF334155), borderRadius: BorderRadius.circular(4)),
                                      child: Text('${docs.length} Active Orders', style: const TextStyle(color: AppColors.accentYellow, fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                                Text('Pick all ${batchItems.length} items from shelves in 1 trip', style: const TextStyle(color: Colors.white60, fontSize: 11)),
                              ],
                            ),
                          ],
                        ),
                        Icon(_isBatchPickingExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: Colors.white70),
                      ],
                    ),
                  ),
                ),
                if (_isBatchPickingExpanded) ...[
                  const Divider(height: 1, color: Color(0xFF334155)),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: batchItems.entries.map((e) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('• ${e.key}', style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(6)),
                                child: Text('Total: ${e.value}x', style: const TextStyle(color: AppColors.accentYellow, fontWeight: FontWeight.w900, fontSize: 11.5)),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        // Orders List
        ...docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final orderId = (data['orderId'] ?? doc.id).toString();
          final customer = (data['customerName'] ?? data['userName'] ?? 'Customer').toString();
          final address = (data['deliveryAddress'] ?? 'Nellore Doorstep Delivery').toString();
          final items = (data['items'] as List<dynamic>?) ?? [];
          final total = (data['grandTotal'] ?? data['totalAmount'] ?? data['itemsTotal'] ?? 0).toDouble();
          final status = (data['orderStatus'] ?? data['status'] ?? 'Preparing').toString();
          final pickupOtp = (data['pickupOtp'] ?? '----').toString();
          final payment = (data['paymentMethod'] ?? 'COD').toString();
          final bool isOnline = payment.toUpperCase().contains('ONLINE') || payment.toUpperCase().contains('UPI');
          final timeStr = _formatRelativeTime(data['createdAt'] ?? data['acceptedAt']);
          final int elapsedMins = _getElapsedMinutes(data['createdAt'] ?? data['acceptedAt']);

          final int packedCount = items.where((it) => (it as Map)['isPacked'] == true).length;
          final bool allPacked = items.isNotEmpty && packedCount == items.length;

          // SLA Urgency Colors
          final bool isCritical = queueType == 'preparing' && elapsedMins >= 5;
          final bool isWarning = queueType == 'preparing' && elapsedMins >= 2 && elapsedMins < 5;

          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            child: InkWell(
              onTap: () => _openPackingStepper(context, doc.id, data),
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isCritical
                        ? Colors.redAccent
                        : (isWarning ? const Color(0xFFF59E0B) : (queueType == 'ready' ? const Color(0xFFFDE68A) : AppColors.cardBorder)),
                    width: isCritical || isWarning || queueType == 'ready' ? 1.5 : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isCritical ? Colors.red.withAlpha(15) : Colors.black.withAlpha(8),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header with Order #, Urgency SLA Badge & Payment Mode
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Text('Order #', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5, color: AppColors.textDark)),
                            if (timeStr.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Text('• $timeStr', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                            ],
                          ],
                        ),
                        Row(
                          children: [
                            // SLA Urgency Badge in Kitchen
                            if (queueType == 'preparing') ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  color: isCritical ? const Color(0xFFFEE2E2) : (isWarning ? const Color(0xFFFEF3C7) : const Color(0xFFDCFCE7)),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isCritical
                                      ? '🚨 URGENT SLA (${elapsedMins}m)'
                                      : (isWarning ? '⏱️ PACKING (${elapsedMins}m)' : '🟢 FRESH'),
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w900,
                                    color: isCritical ? const Color(0xFFDC2626) : (isWarning ? const Color(0xFFB45309) : const Color(0xFF15803D)),
                                  ),
                                ),
                              ),
                            ],
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: isOnline ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isOnline ? 'PAID' : 'COD',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: isOnline ? const Color(0xFF15803D) : const Color(0xFFB45309),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Divider(height: 18),

                    // Customer info
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(customer, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Text(
                          '₹${total.toStringAsFixed(0)}',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.primaryGreen),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(address, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted), maxLines: 1),
                    const SizedBox(height: 12),

                    // Items summary with Packing Progress
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('${items.length} Items to Pack', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textDark)),
                              if (queueType == 'preparing')
                                Text(
                                  allPacked ? 'All Packed (100%)' : '$packedCount / ${items.length} Packed',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: allPacked ? AppColors.primaryGreen : AppColors.accentBlue,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ...items.take(3).map((it) {
                            final item = it as Map<String, dynamic>;
                            final bool isPacked = item['isPacked'] == true;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Icon(
                                    isPacked ? Icons.check_circle : Icons.circle_outlined,
                                    size: 14,
                                    color: isPacked ? AppColors.primaryGreen : Colors.grey,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '${item['quantity'] ?? 1}x ${item['name'] ?? 'Item'}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        decoration: isPacked ? TextDecoration.lineThrough : null,
                                        color: isPacked ? Colors.grey : AppColors.textDark,
                                      ),
                                      maxLines: 1,
                                    ),
                                  ),
                                  Text('₹${item['totalPrice'] ?? item['price'] ?? 0}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            );
                          }),
                          if (items.length > 3)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text('+${items.length - 3} more items...', style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontStyle: FontStyle.italic)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Queue Specific Action Bar & OTP Display
                    if (queueType == 'preparing') ...[
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.accentBlue,
                                side: const BorderSide(color: AppColors.accentBlue),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: () => _openPackingStepper(context, doc.id, data),
                              icon: const Icon(Icons.checklist_rounded, size: 16),
                              label: const Text('PACKING CHECKLIST', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: allPacked ? AppColors.primaryGreen : const Color(0xFF2563EB),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: () async {
                                await FirestoreService.markOrderPackingReady(doc.id);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('✅ Order Packed! Waiting for Delivery Partner pickup.'),
                                      backgroundColor: AppColors.primaryGreen,
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.check_circle_outline, size: 16),
                              label: Text(allPacked ? 'MARK PACKED' : 'QUICK READY', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                            ),
                          ),
                        ],
                      ),
                    ] else if (queueType == 'ready') ...[
                      Builder(
                        builder: (context) {
                          final String partnerId = (data['deliveryPartnerId'] ?? data['riderId'] ?? '').toString().trim();
                          final bool hasRider = partnerId.isNotEmpty;

                          if (!hasRider) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFF38BDF8).withAlpha(80)),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.radar_rounded, color: Color(0xFF38BDF8), size: 20),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('FINDING NEARBY DELIVERY PARTNER...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5)),
                                        Text('Broadcasting order to Flash2Mart riders in Nellore', style: TextStyle(color: Colors.white70, fontSize: 10.5)),
                                      ],
                                    ),
                                  ),
                                  SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8))),
                                ],
                              ),
                            );
                          }

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
                              final riderStatus = (data['orderStatus'] ?? data['status'] ?? data['currentStatus'] ?? '').toString().toLowerCase().replaceAll(' ', '_');

                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.delivery_dining_rounded, color: AppColors.accentBlue, size: 22),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(child: Text(realName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5), overflow: TextOverflow.ellipsis)),
                                              if (data['isBatchedOrder'] == true) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                                  decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(5)),
                                                  child: const Text('BATCHED', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFF4F46E5))),
                                                ),
                                              ],
                                            ],
                                          ),
                                          if (riderStatus == 'reached_store')
                                            const Text('📍 Rider at Store (Ready for Handover)', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF16A34A)))
                                          else if (riderStatus == 'out_for_delivery' || riderStatus == 'picked_up')
                                            const Text('🛵 Picked Up • Out for Delivery', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                                          if ((data['riderIssue'] ?? '').toString().isNotEmpty)
                                            Text('⚠️ Issue: ${data['riderIssue']}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFFDC2626))),
                                          Text('Bike: $realBike • $realPhone', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Call Rider',
                                      icon: const Icon(Icons.call, color: Color(0xFF2563EB), size: 20),
                                      onPressed: realPhone.isNotEmpty ? () => CommunicationService.callPhoneNumber(realPhone) : null,
                                    ),
                                    IconButton(
                                      tooltip: 'WhatsApp Rider',
                                      icon: const Icon(Icons.chat_rounded, color: Color(0xFF16A34A), size: 20),
                                      onPressed: realPhone.isNotEmpty
                                          ? () {
                                              CommunicationService.openWhatsApp(
                                                phone: realPhone,
                                                message: 'Hi $realName, Flash2Mart Order #$orderId is packed and ready for pickup at our store. Pickup OTP is: $pickupOtp. Please collect.',
                                              );
                                            }
                                          : null,
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.key_rounded, color: Color(0xFFB45309), size: 18),
                                SizedBox(width: 6),
                                Text('Pickup Handover OTP:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF92400E))),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFF59E0B)),
                              ),
                              child: Text(
                                pickupOtp,
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFFB45309), letterSpacing: 2),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 38,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF59E0B),
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () => _openPackingStepper(context, doc.id, data),
                          icon: const Icon(Icons.handshake_rounded, size: 16),
                          label: const Text('CONFIRM HANDOVER TO RIDER', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5)),
                        ),
                      ),
                    ] else ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Status: $status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: queueType == 'out' ? Colors.blue : Colors.green)),
                          TextButton.icon(
                            onPressed: () => _openPackingStepper(context, doc.id, data),
                            icon: const Icon(Icons.timeline_rounded, size: 16),
                            label: const Text('View Stepper & Slip', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ],
    );
  }
}
