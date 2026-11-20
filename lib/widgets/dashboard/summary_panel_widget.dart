import '../../screens/merchant_earnings_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../screens/orders_screen.dart';
import '../../screens/manage_products_screen.dart';

/// Executive Summary Panel Widget for Flash2Mart Merchant Dashboard
/// Real-time live synchronization with Firestore `orders` and `products` collections.
class SummaryPanelWidget extends StatelessWidget {
  const SummaryPanelWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    // Get today's start timestamp (midnight)
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final todayTimestamp = Timestamp.fromDate(startOfToday);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Today\'s Live Overview',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 10),

          // StreamBuilder for Merchant's Orders
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('orders')
                .where('merchantId', isEqualTo: user.uid)
                .snapshots(),
            builder: (context, snapshot) {
              int activeCount = 0;
              int completedCount = 0;
              double todayRevenue = 0.0;

              if (snapshot.hasData) {
                for (final doc in snapshot.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final String status =
                      (data['orderStatus'] ?? data['status'] ?? '').toString().toLowerCase();

                  // Active orders: Placed, Preparing, Packing Ready, Accepted, On Way
                  if (status == 'placed' ||
                      status == 'pending' ||
                      status == 'preparing' ||
                      status == 'packing_ready' ||
                      status == 'accepted') {
                    activeCount++;
                  }

                  // Completed orders
                  if (status == 'delivered' || status == 'completed') {
                    final Timestamp? createdAt =
                        data['createdAt'] as Timestamp? ?? data['acceptedAt'] as Timestamp?;
                    if (createdAt != null && createdAt.compareTo(todayTimestamp) >= 0) {
                      completedCount++;
                      final double amount = (data['itemsTotal'] ??
                              data['itemTotal'] ??
                              data['grandTotal'] ??
                              data['totalAmount'] ??
                              0)
                          .toDouble();
                      todayRevenue += amount;
                    }
                  }
                }
              }

              return Row(
                children: [
                  // 1. Live Active Orders Card
                  Expanded(
                    child: _buildMetricCard(
                      context,
                      title: 'Active Orders',
                      value: '$activeCount',
                      subtitle: activeCount > 0 ? 'Needs Attention' : 'All Clear',
                      icon: Icons.inventory_2_rounded,
                      color: activeCount > 0 ? const Color(0xFFEA580C) : const Color(0xFF2563EB),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const OrdersScreen()),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),

                  // 2. Today's Revenue Card
                  Expanded(
                    child: _buildMetricCard(
                      context,
                      title: 'Today\'s Sales',
                      value: '₹${todayRevenue.toStringAsFixed(0)}',
                      subtitle: '$completedCount Delivered',
                      icon: Icons.currency_rupee_rounded,
                      color: const Color(0xFF16A34A),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const MerchantEarningsScreen()),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),

          // Total Active Products in Store
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('products')
                .where('merchantId', isEqualTo: user.uid)
                .snapshots(),
            builder: (context, snapshot) {
              final int productCount = snapshot.hasData ? snapshot.data!.docs.length : 0;

              return InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ManageProductsScreen()),
                  );
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.grid_view_rounded, color: Color(0xFF4F46E5), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Catalog & Stock Inventory',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            Text(
                              '$productCount items live in your store',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8), size: 20),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x06000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF64748B),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: color.withAlpha(31),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 10.5,
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
