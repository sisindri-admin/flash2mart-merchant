import 'merchant_wallet_payout_screen.dart';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Merchant Daily Earnings, Accounts & Payouts Screen (Option 3)
/// Features:
/// 1. Today's Sales & Net Earnings breakdown
/// 2. UPI vs Cash on Delivery (COD) collection analytics
/// 3. Last 7 Days Interactive Sales Bar Chart
/// 4. Bank Account & Automated Nightly Settlement History
class MerchantEarningsScreen extends StatefulWidget {
  const MerchantEarningsScreen({super.key});

  @override
  State<MerchantEarningsScreen> createState() => _MerchantEarningsScreenState();
}

class _MerchantEarningsScreenState extends State<MerchantEarningsScreen> {

  void _showEditBankDialog(BuildContext context, Map<String, dynamic> currentBank) {
    final holderCtrl = TextEditingController(text: (currentBank['accountHolder'] ?? '').toString());
    final bankNameCtrl = TextEditingController(text: (currentBank['bankName'] ?? 'State Bank of India').toString());
    final accCtrl = TextEditingController(text: (currentBank['accountNumber'] ?? '').toString());
    final ifscCtrl = TextEditingController(text: (currentBank['ifsc'] ?? 'SBIN0001234').toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.account_balance_rounded, color: AppColors.primaryGreen, size: 22),
            SizedBox(width: 8),
            Text('Bank Account for Payouts', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Daily sales are automatically transferred to this bank account every night at 11:30 PM.',
                style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: holderCtrl,
                decoration: InputDecoration(
                  labelText: 'Account Holder Name',
                  hintText: 'e.g. Ramesh Reddy',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: bankNameCtrl,
                decoration: InputDecoration(
                  labelText: 'Bank Name',
                  hintText: 'e.g. HDFC Bank / SBI',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: accCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Account Number',
                  hintText: 'e.g. 5010048291029',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ifscCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'IFSC Code',
                  hintText: 'e.g. HDFC0001234',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final user = FirebaseAuth.instance.currentUser;
              if (user != null) {
                await FirebaseFirestore.instance.collection('merchants').doc(user.uid).set({
                  'bankDetails': {
                    'accountHolder': holderCtrl.text.trim(),
                    'bankName': bankNameCtrl.text.trim(),
                    'accountNumber': accCtrl.text.trim(),
                    'ifsc': ifscCtrl.text.trim().toUpperCase(),
                    'updatedAt': FieldValue.serverTimestamp(),
                  },
                }, SetOptions(merge: true));
              }
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ Payout Bank Account updated successfully!'),
                    backgroundColor: AppColors.primaryGreen,
                  ),
                );
              }
            },
            child: const Text('Save Details', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Please log in.')));
    }

    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final sevenDaysAgo = todayMidnight.subtract(const Duration(days: 6));

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.account_balance_wallet_rounded, color: AppColors.primaryGreen, size: 22),
            SizedBox(width: 8),
            Text(
              'Earnings & Accounts',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: AppColors.textDark),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        foregroundColor: AppColors.textDark,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('merchants').doc(user.uid).snapshots(),
        builder: (context, merchantSnap) {
          final merchantData = merchantSnap.hasData && merchantSnap.data!.exists
              ? merchantSnap.data!.data() as Map<String, dynamic>
              : <String, dynamic>{};
          final bankDetails = (merchantData['bankDetails'] as Map<String, dynamic>?) ?? {};

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('orders')
                .where('merchantId', isEqualTo: user.uid)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
              }

              final allDocs = snapshot.hasData ? snapshot.data!.docs : <QueryDocumentSnapshot>[];

              // Aggregation Variables
              double todayGross = 0;
              int todayOrders = 0;
              double todayUpi = 0;
              double todayCod = 0;

              // Last 7 days bucket: key = YYYY-MM-DD
              final Map<String, double> last7DaysSales = {};
              final Map<String, int> last7DaysCounts = {};
              for (int i = 0; i < 7; i++) {
                final d = sevenDaysAgo.add(Duration(days: i));
                final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                last7DaysSales[key] = 0.0;
                last7DaysCounts[key] = 0;
              }

              for (var doc in allDocs) {
                final data = doc.data() as Map<String, dynamic>;
                final status = (data['orderStatus'] ?? data['status'] ?? '').toString().toLowerCase();
                final bool isDelivered = status == 'delivered' || status == 'completed';

                final double amount = (data['grandTotal'] ?? data['totalAmount'] ?? data['itemsTotal'] ?? 0).toDouble();
                final String payment = (data['paymentMethod'] ?? 'COD').toString().toUpperCase();
                final bool isOnline = payment.contains('ONLINE') || payment.contains('UPI');

                DateTime? orderDate;
                final dynamic ts = data['createdAt'] ?? data['acceptedAt'];
                if (ts is Timestamp) {
                  orderDate = ts.toDate();
                }

                if (orderDate != null && isDelivered) {
                  // Check Today
                  if (orderDate.isAfter(todayMidnight)) {
                    todayGross += amount;
                    todayOrders++;
                    if (isOnline) {
                      todayUpi += amount;
                    } else {
                      todayCod += amount;
                    }
                  }

                  // Check 7 Days Bucket
                  final key = '${orderDate.year}-${orderDate.month.toString().padLeft(2, '0')}-${orderDate.day.toString().padLeft(2, '0')}';
                  if (last7DaysSales.containsKey(key)) {
                    last7DaysSales[key] = (last7DaysSales[key] ?? 0.0) + amount;
                    last7DaysCounts[key] = (last7DaysCounts[key] ?? 0) + 1;
                  }
                }
              }

              final double aov = todayOrders > 0 ? (todayGross / todayOrders) : 0;
              final double upiPercent = todayGross > 0 ? (todayUpi / todayGross) : 0.5;

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // 1. TODAY'S SALES & NET REVENUE HERO CARD
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withAlpha(25), blurRadius: 12, offset: const Offset(0, 4)),
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
                                Icon(Icons.wb_sunny_rounded, color: AppColors.accentYellow, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  "TODAY'S BUSINESS",
                                  style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.8),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF16A34A).withAlpha(40),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFF22C55E)),
                              ),
                              child: const Text(
                                'LIVE SETTLING',
                                style: TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.w900, fontSize: 10),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          '₹${todayGross.toStringAsFixed(0)}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 32, letterSpacing: -0.5),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '100% Direct Store Net Revenue (No Hidden Deductions)',
                          style: TextStyle(color: Colors.white60, fontSize: 11),
                        ),
                        const Divider(height: 24, color: Colors.white12),

                        // Stats Row
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Delivered Orders', style: TextStyle(color: Colors.white60, fontSize: 11)),
                                  const SizedBox(height: 2),
                                  Text('$todayOrders Orders', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                ],
                              ),
                            ),
                            Container(width: 1, height: 28, color: Colors.white12),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Avg Order Value (AOV)', style: TextStyle(color: Colors.white60, fontSize: 11)),
                                  const SizedBox(height: 2),
                                  Text('₹${aov.toStringAsFixed(0)}', style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 14)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 42,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryGreen,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const MerchantWalletPayoutScreen()),
                              );
                            },
                            icon: const Icon(Icons.payments_rounded, size: 18),
                            label: const Text('REQUEST WITHDRAWAL & WALLET →', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. UPI vs CASH ON DELIVERY (COD) BREAKDOWN CARD
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
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('PAYMENT MODES (UPI vs COD)', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: AppColors.textDark, letterSpacing: 0.3)),
                            Text('Realtime Collection', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Progress Bar showing % UPI vs % COD
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Row(
                            children: [
                              Expanded(
                                flex: (upiPercent * 100).round().clamp(5, 95),
                                child: Container(height: 10, color: const Color(0xFF2563EB)),
                              ),
                              Expanded(
                                flex: ((1 - upiPercent) * 100).round().clamp(5, 95),
                                child: Container(height: 10, color: const Color(0xFFF59E0B)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        Row(
                          children: [
                            // Online UPI Card
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFBFDBFE)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(Icons.qr_code_2_rounded, size: 16, color: Color(0xFF2563EB)),
                                        SizedBox(width: 4),
                                        Text('Online / UPI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Color(0xFF1E40AF))),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text('₹${todayUpi.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF1E3A8A))),
                                    Text('Direct Bank Transfer', style: TextStyle(fontSize: 10, color: Colors.blue.shade700)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),

                            // Cash on Delivery Card
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFFDE68A)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(Icons.payments_rounded, size: 16, color: Color(0xFFB45309)),
                                        SizedBox(width: 4),
                                        Text('Cash on Delivery', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Color(0xFF92400E))),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text('₹${todayCod.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF78350F))),
                                    Text('Collected by Rider', style: TextStyle(fontSize: 10, color: Colors.amber.shade900)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 3. LAST 7 DAYS SALES BAR CHART
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
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('LAST 7 DAYS SALES TREND', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: AppColors.textDark, letterSpacing: 0.3)),
                            Icon(Icons.bar_chart_rounded, color: AppColors.primaryGreen, size: 20),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildWeeklyBarChart(last7DaysSales),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 4. BANK ACCOUNT & AUTOMATED SETTLEMENTS
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
                            const Row(
                              children: [
                                Icon(Icons.account_balance_rounded, color: AppColors.accentBlue, size: 20),
                                SizedBox(width: 8),
                                Text('BANK ACCOUNT & PAYOUTS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: AppColors.textDark, letterSpacing: 0.3)),
                              ],
                            ),
                            TextButton.icon(
                              onPressed: () => _showEditBankDialog(context, bankDetails),
                              icon: const Icon(Icons.edit, size: 14),
                              label: const Text('Edit', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryGreenLight,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.account_balance_rounded, color: AppColors.primaryGreen, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (bankDetails['bankName'] ?? 'State Bank of India').toString(),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'A/c: ${_maskAccount(bankDetails['accountNumber']?.toString())} • IFSC: ${(bankDetails['ifsc'] ?? 'SBIN0001234')}',
                                      style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Holder: ${(bankDetails['accountHolder'] ?? user.displayName ?? 'Store Manager')}',
                                      style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Automated Settlement Note
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF86EFAC)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.check_circle_rounded, color: AppColors.primaryGreen, size: 18),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Automated Daily Payout: Net sales are transferred to your bank account every night at 11:30 PM.',
                                  style: TextStyle(fontSize: 11, color: Color(0xFF15803D), fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  String _maskAccount(String? acc) {
    if (acc == null || acc.length < 4) return '•••• 4821';
    return '•••• ${acc.substring(acc.length - 4)}';
  }

  Widget _buildWeeklyBarChart(Map<String, double> salesData) {
    final values = salesData.values.toList();
    final double maxVal = values.isNotEmpty ? values.reduce(math.max) : 0.0;
    final double ceiling = maxVal > 0 ? maxVal : 1000.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: salesData.entries.map((entry) {
        final dateKey = entry.key; // YYYY-MM-DD
        final sales = entry.value;
        final double heightFraction = (sales / ceiling).clamp(0.08, 1.0);

        // Day label (e.g. Mon, Tue)
        final parts = dateKey.split('-');
        final dt = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
        final dayName = _getDayName(dt.weekday);
        final bool isToday = dt.day == DateTime.now().day && dt.month == DateTime.now().month;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              sales > 0 ? '₹${sales.toStringAsFixed(0)}' : '₹0',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: isToday ? FontWeight.w900 : FontWeight.w600,
                color: isToday ? AppColors.primaryGreen : AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: 32,
              height: 110 * heightFraction,
              decoration: BoxDecoration(
                color: isToday ? AppColors.primaryGreen : const Color(0xFF93C5FD),
                borderRadius: BorderRadius.circular(8),
                gradient: LinearGradient(
                  colors: isToday
                      ? [const Color(0xFF16A34A), const Color(0xFF22C55E)]
                      : [const Color(0xFF3B82F6), const Color(0xFF60A5FA)],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isToday ? 'Today' : dayName,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: isToday ? FontWeight.w900 : FontWeight.w600,
                color: isToday ? AppColors.primaryGreen : AppColors.textDark,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  String _getDayName(int weekday) {
    switch (weekday) {
      case 1:
        return 'Mon';
      case 2:
        return 'Tue';
      case 3:
        return 'Wed';
      case 4:
        return 'Thu';
      case 5:
        return 'Fri';
      case 6:
        return 'Sat';
      case 7:
        return 'Sun';
      default:
        return '';
    }
  }
}
