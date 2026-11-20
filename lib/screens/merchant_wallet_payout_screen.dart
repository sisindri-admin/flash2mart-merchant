import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Comprehensive Merchant Wallet, Payout Requests & Bank Settlements Screen
/// Features:
/// 1. 4 Metric Cards: Today's Sales, Available Wallet Balance, Pending Requests, Total Settled
/// 2. 1-Tap Payout / Withdrawal Request Bottom Sheet with custom amount or quick chips (₹500, ₹1000, Full)
/// 3. Bank Account & GooglePay/PhonePe UPI ID Editor
/// 4. Live Payout Tracking Queue (Pending Approval -> Processing -> Transferred with Bank UTR)
class MerchantWalletPayoutScreen extends StatefulWidget {
  const MerchantWalletPayoutScreen({super.key});

  @override
  State<MerchantWalletPayoutScreen> createState() => _MerchantWalletPayoutScreenState();
}

class _MerchantWalletPayoutScreenState extends State<MerchantWalletPayoutScreen> {
  final TextEditingController _amountController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _showWithdrawalSheet(
    BuildContext context, {
    required double availableBalance,
    required Map<String, dynamic> bankDetails,
    required String storeName,
  }) {
    _amountController.text = availableBalance > 0 ? availableBalance.toStringAsFixed(0) : '';

    final hasBankOrUpi = (bankDetails['accountNumber'] ?? '').toString().isNotEmpty ||
        (bankDetails['upiId'] ?? '').toString().isNotEmpty;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final enteredAmount = double.tryParse(_amountController.text.trim()) ?? 0.0;
          final bool isValidAmount = enteredAmount > 0 && enteredAmount <= availableBalance;

          return Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: EdgeInsets.fromLTRB(
              20,
              14,
              20,
              MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.currency_rupee_rounded, color: AppColors.primaryGreen, size: 24),
                          SizedBox(width: 8),
                          Text(
                            'Request Payout Transfer',
                            style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900, color: AppColors.textDark),
                          ),
                        ],
                      ),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Available Balance Reminder
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF86EFAC)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Available to Withdraw:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF15803D))),
                        Text('₹${availableBalance.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF15803D))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Amount Input
                  const Text('Enter Withdrawal Amount:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setSheetState(() {}),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: AppColors.textDark),
                    decoration: InputDecoration(
                      prefixText: '₹ ',
                      prefixStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: AppColors.primaryGreen),
                      hintText: 'e.g. 1000',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Quick Amount Chips
                  Wrap(
                    spacing: 8,
                    children: [500, 1000, 2000].map((amt) {
                      return ActionChip(
                        label: Text('₹$amt'),
                        onPressed: availableBalance >= amt
                            ? () {
                                setSheetState(() {
                                  _amountController.text = amt.toString();
                                });
                              }
                            : null,
                      );
                    }).toList()
                      ..add(
                        ActionChip(
                          label: const Text('Full Balance'),
                          backgroundColor: AppColors.primaryGreenLight,
                          labelStyle: const TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.bold),
                          onPressed: availableBalance > 0
                              ? () {
                                  setSheetState(() {
                                    _amountController.text = availableBalance.toStringAsFixed(0);
                                  });
                                }
                              : null,
                        ),
                      ),
                  ),
                  const SizedBox(height: 16),

                  // Destination Account Preview
                  const Text('Transferring To:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: hasBankOrUpi
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.account_balance_rounded, size: 18, color: AppColors.accentBlue),
                                  const SizedBox(width: 8),
                                  Text(
                                    (bankDetails['bankName'] ?? 'Bank Account').toString(),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'A/c: ${_maskAccount(bankDetails['accountNumber']?.toString())} • IFSC: ${(bankDetails['ifsc'] ?? '')}',
                                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                              ),
                              if ((bankDetails['upiId'] ?? '').toString().isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'UPI ID: ${bankDetails['upiId']}',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF2563EB), fontWeight: FontWeight.bold),
                                ),
                              ],
                            ],
                          )
                        : Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text('No Bank Account/UPI added. Please add details first.', style: TextStyle(fontSize: 12, color: Colors.redAccent)),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _showEditBankDialog(context, bankDetails);
                                },
                                child: const Text('Add Bank'),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 20),

                  // Submit Request Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 1,
                      ),
                      onPressed: !isValidAmount || !hasBankOrUpi || _isSubmitting
                          ? null
                          : () async {
                              final user = FirebaseAuth.instance.currentUser;
                              if (user == null) return;

                              setSheetState(() => _isSubmitting = true);
                              try {
                                final batch = FirebaseFirestore.instance.batch();

                                // 1. Create Payout Request document
                                final payoutRef = FirebaseFirestore.instance.collection('payout_requests').doc();
                                batch.set(payoutRef, {
                                  'requestId': payoutRef.id,
                                  'merchantId': user.uid,
                                  'storeName': storeName,
                                  'amount': enteredAmount,
                                  'bankDetails': bankDetails,
                                  'status': 'pending', // 'pending', 'processing', 'transferred', 'rejected'
                                  'requestedAt': FieldValue.serverTimestamp(),
                                  'updatedAt': FieldValue.serverTimestamp(),
                                });

                                // 2. Update Merchant Pending Payouts balance
                                final merchantRef = FirebaseFirestore.instance.collection('merchants').doc(user.uid);
                                batch.set(merchantRef, {
                                  'pendingPayoutAmount': FieldValue.increment(enteredAmount),
                                  'lastPayoutRequestAt': FieldValue.serverTimestamp(),
                                }, SetOptions(merge: true));

                                await batch.commit();

                                if (ctx.mounted) Navigator.pop(ctx);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('✅ Withdrawal request for ₹${enteredAmount.toStringAsFixed(0)} submitted to Flash2Mart Admin!'),
                                      backgroundColor: AppColors.primaryGreen,
                                    ),
                                  );
                                }
                              } catch (e) {
                                setSheetState(() => _isSubmitting = false);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                                }
                              }
                            },
                      icon: _isSubmitting
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.send_rounded, size: 18),
                      label: Text(
                        isValidAmount
                            ? 'SUBMIT PAYOUT REQUEST (₹${enteredAmount.toStringAsFixed(0)})'
                            : 'ENTER VALID AMOUNT',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showEditBankDialog(BuildContext context, Map<String, dynamic> currentBank) {
    final holderCtrl = TextEditingController(text: (currentBank['accountHolder'] ?? '').toString());
    final bankNameCtrl = TextEditingController(text: (currentBank['bankName'] ?? 'State Bank of India').toString());
    final accCtrl = TextEditingController(text: (currentBank['accountNumber'] ?? '').toString());
    final ifscCtrl = TextEditingController(text: (currentBank['ifsc'] ?? 'SBIN0001234').toString());
    final upiCtrl = TextEditingController(text: (currentBank['upiId'] ?? '').toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.account_balance_rounded, color: AppColors.primaryGreen, size: 22),
            SizedBox(width: 8),
            Text('Bank Account & UPI', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add your bank account & UPI ID to receive payouts directly from Flash2Mart:', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
              const SizedBox(height: 12),
              TextField(
                controller: holderCtrl,
                decoration: InputDecoration(
                  labelText: 'Account Holder Full Name',
                  hintText: 'As per Bank Passbook',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: bankNameCtrl,
                decoration: InputDecoration(
                  labelText: 'Bank Name',
                  hintText: 'e.g. State Bank of India / HDFC',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: accCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Bank Account Number',
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
                  hintText: 'e.g. SBIN0001234',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: upiCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'GooglePay / PhonePe UPI ID (Optional)',
                  hintText: 'e.g. 9876543210@ibl / store@okaxis',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  prefixIcon: const Icon(Icons.qr_code_2_rounded, size: 20),
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
                    'upiId': upiCtrl.text.trim(),
                    'updatedAt': FieldValue.serverTimestamp(),
                  },
                }, SetOptions(merge: true));
              }
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ Bank Account & UPI ID saved successfully!'),
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

  String _maskAccount(String? acc) {
    if (acc == null || acc.length < 4) return '•••• 4821';
    return '•••• ${acc.substring(acc.length - 4)}';
  }

  String _formatTime(dynamic ts) {
    if (ts is Timestamp) {
      final dt = ts.toDate();
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return '${dt.day}/${dt.month} at $hour:${dt.minute.toString().padLeft(2, '0')} $ampm';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Please log in.')));
    }

    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.account_balance_wallet_rounded, color: AppColors.primaryGreen, size: 22),
            SizedBox(width: 8),
            Text(
              'Merchant Wallet & Payouts',
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
          final storeName = (merchantData['storeName'] ?? merchantData['shopName'] ?? 'Store').toString();

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('orders')
                .where('merchantId', isEqualTo: user.uid)
                .snapshots(),
            builder: (context, ordersSnap) {
              final allOrders = ordersSnap.hasData ? ordersSnap.data!.docs : <QueryDocumentSnapshot>[];

              double todaySales = 0;
              double totalDeliveredLifetime = 0;

              for (var doc in allOrders) {
                final d = doc.data() as Map<String, dynamic>;
                final status = (d['orderStatus'] ?? d['status'] ?? '').toString().toLowerCase();
                final bool isDelivered = status == 'delivered' || status == 'completed';
                final double amount = (d['grandTotal'] ?? d['totalAmount'] ?? d['itemsTotal'] ?? 0).toDouble();

                if (isDelivered) {
                  totalDeliveredLifetime += amount;

                  DateTime? orderDate;
                  final dynamic ts = d['createdAt'] ?? d['acceptedAt'];
                  if (ts is Timestamp) orderDate = ts.toDate();

                  if (orderDate != null && orderDate.isAfter(todayMidnight)) {
                    todaySales += amount;
                  }
                }
              }

              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('payout_requests')
                    .where('merchantId', isEqualTo: user.uid)
                    .snapshots(),
                builder: (context, payoutSnap) {
                  final payoutDocs = payoutSnap.hasData ? payoutSnap.data!.docs : <QueryDocumentSnapshot>[];

                  double totalSettledTransferred = 0;
                  double pendingRequestAmount = 0;

                  for (var doc in payoutDocs) {
                    final pData = doc.data() as Map<String, dynamic>;
                    final status = (pData['status'] ?? 'pending').toString().toLowerCase();
                    final double pAmt = (pData['amount'] ?? 0).toDouble();

                    if (status == 'transferred' || status == 'settled' || status == 'approved') {
                      totalSettledTransferred += pAmt;
                    } else if (status == 'pending' || status == 'processing') {
                      pendingRequestAmount += pAmt;
                    }
                  }

                  // Available balance = Total Delivered Lifetime - Settled - Pending Requests
                  final double availableBalance = (totalDeliveredLifetime - totalSettledTransferred - pendingRequestAmount).clamp(0.0, double.infinity);

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // 1. HERO 4-METRIC GRID CARDS
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: const [
                            BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4)),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('WALLET BALANCE (READY TO WITHDRAW)', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 11.5, letterSpacing: 0.5)),
                                Icon(Icons.account_balance_wallet_rounded, color: AppColors.accentYellow, size: 20),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '₹${availableBalance.toStringAsFixed(0)}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 34, letterSpacing: -0.5),
                            ),
                            const SizedBox(height: 4),
                            Text('Lifetime Net Sales: ₹${totalDeliveredLifetime.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white60, fontSize: 11)),
                            const Divider(height: 24, color: Colors.white12),

                            // 3 Sub-Stats
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text("Today's Sales", style: TextStyle(color: Colors.white60, fontSize: 11)),
                                      const SizedBox(height: 2),
                                      Text('₹${todaySales.toStringAsFixed(0)}', style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 14)),
                                    ],
                                  ),
                                ),
                                Container(width: 1, height: 26, color: Colors.white12),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('In Request', style: TextStyle(color: Colors.white60, fontSize: 11)),
                                      const SizedBox(height: 2),
                                      Text('₹${pendingRequestAmount.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.accentYellow, fontWeight: FontWeight.bold, fontSize: 14)),
                                    ],
                                  ),
                                ),
                                Container(width: 1, height: 26, color: Colors.white12),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Settled to A/c', style: TextStyle(color: Colors.white60, fontSize: 11)),
                                      const SizedBox(height: 2),
                                      Text('₹${totalSettledTransferred.toStringAsFixed(0)}', style: const TextStyle(color: Color(0xFF60A5FA), fontWeight: FontWeight.bold, fontSize: 14)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 2. PRIMARY ACTION BUTTON: REQUEST WITHDRAWAL
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: availableBalance > 0 ? AppColors.primaryGreen : Colors.grey.shade400,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: availableBalance > 0 ? 2 : 0,
                          ),
                          onPressed: availableBalance > 0
                              ? () => _showWithdrawalSheet(
                                    context,
                                    availableBalance: availableBalance,
                                    bankDetails: bankDetails,
                                    storeName: storeName,
                                  )
                              : null,
                          icon: const Icon(Icons.payments_rounded, size: 20),
                          label: const Text('REQUEST WITHDRAWAL TRANSFER', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, letterSpacing: 0.3)),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // 3. BANK ACCOUNT & UPI CARD
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
                                    Text('PAYOUT DESTINATION DETAILS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: AppColors.textDark, letterSpacing: 0.3)),
                                  ],
                                ),
                                TextButton.icon(
                                  onPressed: () => _showEditBankDialog(context, bankDetails),
                                  icon: const Icon(Icons.edit, size: 14),
                                  label: const Text('Edit / Add', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
                                    decoration: BoxDecoration(color: AppColors.primaryGreenLight, borderRadius: BorderRadius.circular(10)),
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
                                        if ((bankDetails['upiId'] ?? '').toString().isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            'UPI ID: ${bankDetails['upiId']}',
                                            style: const TextStyle(fontSize: 11.5, color: Color(0xFF2563EB), fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // 4. LIVE PAYOUT REQUESTS & SETTLEMENT HISTORY QUEUE
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('WITHDRAWAL REQUESTS HISTORY', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppColors.textDark, letterSpacing: 0.3)),
                          Text('${payoutDocs.length} Total', style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 10),

                      if (payoutDocs.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.cardBorder),
                          ),
                          child: const Center(
                            child: Column(
                              children: [
                                Icon(Icons.receipt_long_outlined, size: 40, color: Color(0xFF94A3B8)),
                                SizedBox(height: 8),
                                Text('No withdrawal requests yet', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B), fontSize: 13)),
                                Text('When you request a payout, status and UTR will appear here.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                              ],
                            ),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: payoutDocs.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final doc = payoutDocs[index];
                            final p = doc.data() as Map<String, dynamic>;
                            final double amount = (p['amount'] ?? 0).toDouble();
                            final String status = (p['status'] ?? 'pending').toString().toLowerCase();
                            final String utr = (p['utrNumber'] ?? p['referenceId'] ?? '').toString();
                            final timeStr = _formatTime(p['requestedAt'] ?? p['updatedAt']);

                            Color statusBg = const Color(0xFFFEF3C7);
                            Color statusColor = const Color(0xFFB45309);
                            String statusLabel = 'PENDING APPROVAL';
                            IconData statusIcon = Icons.hourglass_top_rounded;

                            if (status == 'processing') {
                              statusBg = const Color(0xFFEFF6FF);
                              statusColor = const Color(0xFF1D4ED8);
                              statusLabel = 'BANK PROCESSING';
                              statusIcon = Icons.autorenew_rounded;
                            } else if (status == 'transferred' || status == 'settled' || status == 'approved') {
                              statusBg = const Color(0xFFDCFCE7);
                              statusColor = const Color(0xFF15803D);
                              statusLabel = 'TRANSFERRED TO BANK';
                              statusIcon = Icons.check_circle_rounded;
                            } else if (status == 'rejected') {
                              statusBg = const Color(0xFFFEE2E2);
                              statusColor = const Color(0xFFDC2626);
                              statusLabel = 'REJECTED';
                              statusIcon = Icons.cancel_rounded;
                            }

                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppColors.cardBorder),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '₹${amount.toStringAsFixed(0)}',
                                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: AppColors.textDark),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(6)),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(statusIcon, size: 12, color: statusColor),
                                            const SizedBox(width: 4),
                                            Text(statusLabel, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10, color: statusColor)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text('Requested: $timeStr', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                                  if (utr.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6)),
                                      child: Text(
                                        'Bank UTR Ref: $utr',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF334155), fontFamily: 'monospace'),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
