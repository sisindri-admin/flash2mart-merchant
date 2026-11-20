import '../services/navigation_service.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../services/permission_service.dart';
import '../services/order_sound_service.dart';

import '../widgets/dashboard/store_header_widget.dart';
import '../widgets/dashboard/merchant_active_order_banner.dart';
import '../widgets/dashboard/summary_panel_widget.dart';
import '../widgets/new_order_popup_sheet.dart';
import 'add_product_screen.dart';
import 'combo_offers_screen.dart';
import 'manage_products_screen.dart';
import 'orders_screen.dart';
import 'merchant_auth_screen.dart';
import 'merchant_wallet_payout_screen.dart';

/// Executive Merchant Dashboard for Flash2Mart Quick Commerce
/// Features:
/// 1. Real-time Store Online/Offline Toggle & Live GPS Location Pinning (StoreHeaderWidget).
/// 2. Live Today's Revenue, Active Orders counter & Inventory summary (SummaryPanelWidget).
/// 3. Fast Action Bar to Add Products, Manage Combos, and View Live Orders.
/// 4. Real-Time incoming order sound alert & popup trigger.
class MerchantDashboard extends StatefulWidget {
  const MerchantDashboard({super.key});

  @override
  State<MerchantDashboard> createState() => _MerchantDashboardState();
}

class _MerchantDashboardState extends State<MerchantDashboard> {
  StreamSubscription<QuerySnapshot>? _orderSubscription;
  bool _isPopupShowing = false;

  // Theme Colors
  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color primaryPurple = Color(0xFF4F46E5);
  static const Color accentGreen = Color(0xFF16A34A);
  static const Color bgGrey = Color(0xFFF8FAFC);
  static const Color textDark = Color(0xFF0F172A);

  @override
  void initState() {
    super.initState();
    _listenForNewOrders();
    _saveMerchantFcmToken();

    // Foreground Task & Notification Permission check
    WidgetsBinding.instance.addPostFrameCallback((_) {
      OverlayPermissionHandler.checkAndRequestOverlayPermission(context);
    });
  }

  // Save FCM Token to Firestore
  Future<void> _saveMerchantFcmToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await FirebaseFirestore.instance.collection('merchants').doc(user.uid).set({
          'fcmToken': token,
          'lastTokenUpdate': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint("Error saving FCM Token: $e");
    }
  }

  @override
  void dispose() {
    _orderSubscription?.cancel();
    super.dispose();
  }

  // --- REALTIME NEW ORDERS LISTENER ---
  void _listenForNewOrders() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _orderSubscription = FirebaseFirestore.instance
        .collection('orders')
        .where('merchantId', isEqualTo: user.uid)
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added ||
            change.type == DocumentChangeType.modified) {
          final orderData = change.doc.data() ;
          if (orderData == null) continue;

          final String rawStatus =
              (orderData['orderStatus'] ?? orderData['status'] ?? '').toString();
          final String status = rawStatus.trim().toLowerCase();

          if ((status == 'pending' || status == 'placed' || status == 'ordered') &&
              !_isPopupShowing) {
            final String customerName =
                (orderData['customerName'] ?? orderData['userName'] ?? 'Customer').toString();
            final String totalAmount = (orderData['grandTotal'] ??
                    orderData['totalAmount'] ??
                    orderData['price'] ??
                    '0')
                .toString();

            // Trigger Loud Looping Ringtone Alert & Vibration
            OrderSoundService.startLoopingAlert();
            OverlayPermissionHandler.triggerOrderSoundNotification(
              change.doc.id,
              "$customerName (💰 ₹$totalAmount)",
            );

            // Fast Auto-Open: 0.5s delay to display popup sheet
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted && !_isPopupShowing) {
                _showNewOrderBottomSheet(change.doc.id, orderData);
              }
            });
          }
        }
      }
    });
  }

  void _showNewOrderBottomSheet(String orderId, Map<String, dynamic> orderData) {
    if (!mounted || _isPopupShowing) return;

    setState(() {
      _isPopupShowing = true;
    });

    final targetContext = NavigationService.currentContext ?? context;

    showModalBottomSheet(
      context: targetContext,
      useRootNavigator: true,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => NewOrderPopupSheet(
        orderId: orderId,
        orderData: orderData,
      ),
    ).then((_) {
      if (mounted) {
        setState(() {
          _isPopupShowing = false;
        });
      }
    });
  }

  void _logout() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Logout', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to log out of Flash2Mart Merchant?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const MerchantAuthScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: bgGrey,
      bottomNavigationBar: const MerchantActiveOrderBanner(),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.bolt_rounded, color: Color(0xFFF59E0B), size: 24),
            SizedBox(width: 6),
            Text(
              'Flash2Mart Merchant',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                letterSpacing: 0.3,
                color: textDark,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        actions: [
          IconButton(
            tooltip: 'Test Order Ringtone (Speaker Test)',
            icon: const Icon(Icons.volume_up_rounded, color: Color(0xFFEA580C)),
            onPressed: () => OrderSoundService.testRingtone(context),
          ),
          IconButton(
            tooltip: 'Wallet & Payouts',
            icon: const Icon(Icons.account_balance_wallet_rounded, color: accentGreen),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MerchantWalletPayoutScreen()),
              );
            },
          ),
          IconButton(
            tooltip: 'Orders',
            icon: const Icon(Icons.receipt_long_rounded, color: primaryBlue),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const OrdersScreen()),
              );
            },
          ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout_rounded, color: Color(0xFF64748B)),
            onPressed: _logout,
          ),
        ],
      ),
      body: user == null
          ? const Center(child: Text('Please log in.'))
          : RefreshIndicator(
              onRefresh: () async {
                setState(() {});
              },
              color: primaryBlue,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                children: [
                  // 1. Live Store Profile, Online Toggle & GPS Location Pinning Header
                  StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('merchants')
                        .doc(user.uid)
                        .snapshots(),
                    builder: (context, snapshot) {
                      final Map<String, dynamic> storeData = snapshot.hasData && snapshot.data!.exists
                          ? snapshot.data!.data() as Map<String, dynamic>
                          : {
                              'storeName': user.displayName ?? 'Flash2Mart Store',
                              'address': 'Nellore, Andhra Pradesh',
                              'isOpen': true,
                            };

                      return StoreHeaderWidget(
                        storeData: storeData,
                        onLocationUpdated: () => setState(() {}),
                      );
                    },
                  ),

                  // 2. Real-Time Today's Summary & Inventory Overview
                  const SummaryPanelWidget(),
                  const SizedBox(height: 16),

                  // 3. Quick Action Buttons Card
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Quick Actions',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w900,
                            color: textDark,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 10),

                        Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _buildActionButton(
                                    context,
                                    title: '+ Add Product',
                                    subtitle: 'Scan & Catalog',
                                    icon: Icons.add_circle_outline_rounded,
                                    color: accentGreen,
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => const AddProductScreen()),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _buildActionButton(
                                    context,
                                    title: 'Manage Stock',
                                    subtitle: 'Rates & Stock',
                                    icon: Icons.inventory_2_outlined,
                                    color: primaryPurple,
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => const ManageProductsScreen()),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildActionButton(
                                    context,
                                    title: 'Live Orders',
                                    subtitle: 'Kitchen Stepper & OTP',
                                    icon: Icons.soup_kitchen_rounded,
                                    color: primaryBlue,
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => const OrdersScreen()),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _buildActionButton(
                                    context,
                                    title: 'Wallet & Payouts',
                                    subtitle: 'Withdraw & Transfers',
                                    icon: Icons.account_balance_wallet_rounded,
                                    color: const Color(0xFFD97706),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => const MerchantWalletPayoutScreen()),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildActionButton(
                                    context,
                                    title: 'Combo Offers',
                                    subtitle: 'Bundles & Deals',
                                    icon: Icons.local_offer_rounded,
                                    color: const Color(0xFF7C3AED),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => const ComboOffersScreen()),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Expanded(child: SizedBox()),
                              ],
                            ),
                          ],
                        )
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 4. Live Active Orders Quick Preview Section
                  _buildLiveOrdersSection(user.uid),
                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: textDark,
        elevation: 1,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: color.withAlpha(102), width: 1.2),
        ),
      ),
      onPressed: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withAlpha(31),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const Icon(Icons.arrow_forward_rounded, color: Color(0xFF94A3B8), size: 16),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveOrdersSection(String merchantId) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent Store Orders',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w900,
                  color: textDark,
                  letterSpacing: 0.2,
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const OrdersScreen()),
                  );
                },
                child: const Text('View All', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 6),

          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('orders')
                .where('merchantId', isEqualTo: merchantId)
                .limit(5)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Center(
                    child: Column(
                      children: [
                        Icon(Icons.inbox_rounded, color: Color(0xFF94A3B8), size: 36),
                        SizedBox(height: 8),
                        Text(
                          'No orders placed yet',
                          style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          'When customers order in Customer App, they will appear here.',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final docs = snapshot.data!.docs;
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final String orderId = (data['orderId'] ?? docs[index].id).toString();
                  final String customer = (data['customerName'] ?? data['userName'] ?? 'Customer').toString();
                  final String status = (data['orderStatus'] ?? data['status'] ?? 'Placed').toString();
                  final double total = (data['grandTotal'] ?? data['totalAmount'] ?? data['itemsTotal'] ?? 0).toDouble();

                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.shopping_bag_outlined, color: primaryBlue, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Order #$orderId • $customer',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Status: $status',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: status.toLowerCase() == 'delivered'
                                      ? accentGreen
                                      : const Color(0xFFEA580C),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '₹${total.toStringAsFixed(0)}',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: textDark),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
