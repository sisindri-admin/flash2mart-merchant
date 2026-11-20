import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'add_product_screen.dart';

/// Quick Inventory & Instant Price Manager (Option 2)
/// Features:
/// 1. 1-Tap Out of Stock / In Stock toggle (instantly syncs with Customer App)
/// 2. Instant Daily Price & Stock Editor (updates vegetable & grocery rates in 3 seconds)
/// 3. Low Stock Alerts (Red warning badge when stock <= 5)
/// 4. Filter Chips: All, In Stock, Out of Stock, Low Stock (< 5)
class ManageProductsScreen extends StatefulWidget {
  const ManageProductsScreen({super.key});

  @override
  State<ManageProductsScreen> createState() => _ManageProductsScreenState();
}

class _ManageProductsScreenState extends State<ManageProductsScreen> {
  String _searchQuery = '';
  String _selectedFilter = 'All'; // 'All', 'In Stock', 'Out of Stock', 'Low Stock'

  Widget _buildProductImage(String imgStr) {
    if (imgStr.startsWith('data:image')) {
      try {
        final b64 = imgStr.split(',').last;
        return Image.memory(base64Decode(b64), fit: BoxFit.cover);
      } catch (_) {
        return const Icon(Icons.inventory_2_outlined, color: Colors.grey);
      }
    } else if (imgStr.startsWith('http')) {
      return Image.network(
        imgStr,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported_rounded, color: Colors.grey),
      );
    }
    return const Icon(Icons.inventory_2_outlined, color: Colors.grey);
  }

  /// 1-Tap Instant Daily Rate & Stock Editor Dialog
  void _showInstantPriceEditor(BuildContext context, String docId, Map<String, dynamic> data) {
    final String name = (data['name'] ?? data['title'] ?? 'Product').toString();
    final double currentPrice = (data['price'] ?? data['sellingPrice'] ?? 0).toDouble();
    final double currentMrp = (data['marketPrice'] ?? data['mrp'] ?? currentPrice).toDouble();
    final int currentStock = (data['stock'] ?? 0) is num ? (data['stock'] as num).toInt() : 0;
    final String unit = (data['unit'] ?? '1 unit').toString();

    final priceCtrl = TextEditingController(text: currentPrice > 0 ? currentPrice.toStringAsFixed(0) : '');
    final mrpCtrl = TextEditingController(text: currentMrp > 0 ? currentMrp.toStringAsFixed(0) : '');
    final stockCtrl = TextEditingController(text: currentStock.toString());

    bool isUpdating = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final pVal = double.tryParse(priceCtrl.text.trim()) ?? 0;
          final mVal = double.tryParse(mrpCtrl.text.trim()) ?? 0;
          int discount = 0;
          if (mVal > 0 && pVal > 0 && mVal > pVal) {
            discount = (((mVal - pVal) / mVal) * 100).round();
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.edit_note_rounded, color: AppColors.accentBlue, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Quick Rate & Stock Editor', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                      Text(name, style: const TextStyle(fontSize: 12, color: AppColors.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Unit: $unit', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.accentBlue)),
                  const SizedBox(height: 12),

                  // Flash2Mart Selling Price
                  TextField(
                    controller: priceCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Selling Price (₹) *',
                      prefixText: '₹ ',
                      hintText: 'e.g. 45',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Market Price / MRP
                  TextField(
                    controller: mrpCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Market Price / MRP (₹)',
                      prefixText: '₹ ',
                      hintText: 'e.g. 60',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Stock Count
                  TextField(
                    controller: stockCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Available Stock Count *',
                      prefixIcon: const Icon(Icons.inventory_2_outlined, size: 18),
                      hintText: 'e.g. 50',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Discount Preview
                  if (discount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '🔥 Customer Saves: $discount% OFF',
                        style: const TextStyle(color: Color(0xFF15803D), fontWeight: FontWeight.w900, fontSize: 11.5),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: isUpdating
                    ? null
                    : () async {
                        final newPrice = double.tryParse(priceCtrl.text.trim()) ?? 0;
                        final newMrp = double.tryParse(mrpCtrl.text.trim()) ?? newPrice;
                        final newStock = int.tryParse(stockCtrl.text.trim()) ?? 0;

                        if (newPrice <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please enter a valid selling price.')),
                          );
                          return;
                        }

                        setDialogState(() => isUpdating = true);
                        try {
                          await FirebaseFirestore.instance.collection('products').doc(docId).update({
                            'price': newPrice,
                            'sellingPrice': newPrice,
                            'marketPrice': newMrp,
                            'mrp': newMrp,
                            'stock': newStock,
                            'inStock': newStock > 0,
                            'isAvailable': newStock > 0,
                            'discount': discount,
                            'updatedAt': FieldValue.serverTimestamp(),
                          });

                          if (context.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('✅ $name rate updated to ₹${newPrice.toStringAsFixed(0)} (Stock: $newStock)'),
                                backgroundColor: AppColors.primaryGreen,
                              ),
                            );
                          }
                        } catch (e) {
                          setDialogState(() => isUpdating = false);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error updating rate: $e')),
                            );
                          }
                        }
                      },
                icon: isUpdating
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.bolt_rounded, size: 16),
                label: const Text('UPDATE RATE NOW', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 1-Tap Out of Stock / In Stock Toggle
  Future<void> _toggleStockStatus(String docId, String productName, bool currentlyInStock) async {
    final bool newInStock = !currentlyInStock;
    final int newStock = newInStock ? 50 : 0;

    try {
      await FirebaseFirestore.instance.collection('products').doc(docId).update({
        'stock': newStock,
        'inStock': newInStock,
        'isAvailable': newInStock,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newInStock ? '🟢 $productName is now IN STOCK (50 units)' : '🔴 $productName is now OUT OF STOCK',
            ),
            backgroundColor: newInStock ? AppColors.primaryGreen : Colors.red.shade700,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _confirmDelete(BuildContext context, String docId, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Product?'),
        content: Text('Are you sure you want to remove "$name" from your store?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () async {
              await FirebaseFirestore.instance.collection('products').doc(docId).delete();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Delete'),
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

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: const Text('Quick Stock & Rates', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: AppColors.textDark)),
        backgroundColor: Colors.white,
        elevation: 0.5,
        foregroundColor: AppColors.textDark,
        actions: [
          IconButton(
            tooltip: 'Add Product',
            icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.primaryGreen),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AddProductScreen()));
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Filter Header
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              children: [
                // Search Input
                TextField(
                  onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Search vegetables, fruits, groceries...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.cardBorder)),
                  ),
                ),
                const SizedBox(height: 10),

                // Quick Filter Chips (All, In Stock, Out of Stock, Low Stock)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('All'),
                      const SizedBox(width: 8),
                      _buildFilterChip('In Stock'),
                      const SizedBox(width: 8),
                      _buildFilterChip('Out of Stock'),
                      const SizedBox(width: 8),
                      _buildFilterChip('⚠️ Low Stock (<5)'),
                      const SizedBox(width: 8),
                      _buildFilterChip('⏳ Pending Admin'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Real-Time Products Stream
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('products')
                  .where('merchantId', isEqualTo: user.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.inventory_2_outlined, size: 56, color: Colors.grey),
                        const SizedBox(height: 10),
                        const Text('No products added yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 4),
                        const Text('Add daily vegetables & groceries to start selling.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryGreen, foregroundColor: Colors.white),
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddProductScreen())),
                          icon: const Icon(Icons.add),
                          label: const Text('Add Product'),
                        ),
                      ],
                    ),
                  );
                }

                // Filter docs based on search and selected filter chip
                final docs = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final name = (data['name'] ?? data['title'] ?? '').toString().toLowerCase();
                  final int stock = (data['stock'] ?? 0) is num ? (data['stock'] as num).toInt() : 0;
                  final bool isInStock = (data['inStock'] == true || stock > 0) && data['isAvailable'] != false;

                  if (_searchQuery.isNotEmpty && !name.contains(_searchQuery)) {
                    return false;
                  }

                  final String status = (data['status'] ?? data['approvalStatus'] ?? '').toString().toLowerCase();
                  final bool isPendingAdmin = data['isApproved'] == false ||
                      status == 'pending' ||
                      status == 'pending_approval';

                  if (_selectedFilter == 'In Stock' && !isInStock) return false;
                  if (_selectedFilter == 'Out of Stock' && isInStock) return false;
                  if (_selectedFilter == '⚠️ Low Stock (<5)' && (stock > 5 || stock <= 0)) return false;
                  if (_selectedFilter == '⏳ Pending Admin' && !isPendingAdmin) return false;

                  return true;
                }).toList();

                if (docs.isEmpty) {
                  return Center(
                    child: Text('No products match "$_selectedFilter" filter', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final String name = (data['name'] ?? data['title'] ?? 'Product').toString();
                    final double price = (data['price'] ?? data['sellingPrice'] ?? 0).toDouble();
                    final double mrp = (data['marketPrice'] ?? data['mrp'] ?? price).toDouble();
                    final String unit = (data['unit'] ?? '1 unit').toString();
                    final String img = (data['imageUrl'] ?? data['image'] ?? data['imageBase64'] ?? '').toString();
                    final int stock = (data['stock'] ?? 0) is num ? (data['stock'] as num).toInt() : 0;
                    final bool isInStock = (data['inStock'] == true || stock > 0) && data['isAvailable'] != false;
                    final bool isLowStock = isInStock && stock <= 5;
                    final bool isCombo = data['isCombo'] == true;
                    final String status = (data['status'] ?? data['approvalStatus'] ?? '').toString().toLowerCase();
                    final bool isPendingAdmin = data['isApproved'] == false ||
                        status == 'pending' ||
                        status == 'pending_approval';

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isLowStock ? const Color(0xFFFCA5A5) : AppColors.cardBorder,
                          width: isLowStock ? 1.5 : 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 6, offset: const Offset(0, 2)),
                        ],
                      ),
                      child: Row(
                        children: [
                          // Product Image
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(width: 54, height: 54, child: _buildProductImage(img)),
                          ),
                          const SizedBox(width: 12),

                          // Product Info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    if (isCombo)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        margin: const EdgeInsets.only(right: 6),
                                        decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(4)),
                                        child: const Text('COMBO', style: TextStyle(color: Color(0xFFE11D48), fontSize: 8.5, fontWeight: FontWeight.bold)),
                                      ),
                                    Expanded(
                                      child: Text(
                                        name,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13.5,
                                          color: isInStock ? AppColors.textDark : Colors.grey.shade500,
                                          decoration: isInStock ? null : TextDecoration.lineThrough,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),

                                // Unit & MRP
                                Text('$unit • MRP ₹${mrp.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                const SizedBox(height: 3),

                                // Selling Price + Quick Edit Pencil Icon
                                InkWell(
                                  onTap: () => _showInstantPriceEditor(context, doc.id, data),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '₹${price.toStringAsFixed(0)}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 15,
                                          color: isInStock ? AppColors.primaryGreen : Colors.grey,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.edit_note_rounded, size: 16, color: AppColors.accentBlue),
                                      const Text('Edit Rate', style: TextStyle(fontSize: 10.5, color: AppColors.accentBlue, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),

                                // Pending Admin Approval Badge
                                if (isPendingAdmin) ...[
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEF3C7),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFFFDE68A)),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.hourglass_top_rounded, size: 11, color: Color(0xFFD97706)),
                                        SizedBox(width: 3),
                                        Text(
                                          'Pending Admin Approval (Hidden from App)',
                                          style: TextStyle(color: Color(0xFF92400E), fontWeight: FontWeight.bold, fontSize: 10),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],

                                // Low Stock Alert Badge
                                if (isLowStock) ...[
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEE2E2),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.warning_amber_rounded, size: 11, color: Color(0xFFDC2626)),
                                        const SizedBox(width: 3),
                                        Text('Only $stock left! Restock soon', style: const TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.bold, fontSize: 10)),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),

                          const SizedBox(width: 8),

                          // 1-Tap Out of Stock Switch & Delete Icon
                          Column(
                            children: [
                              Switch(
                                value: isInStock,
                                activeThumbColor: AppColors.primaryGreen,
                                inactiveThumbColor: Colors.grey,
                                onChanged: (_) => _toggleStockStatus(doc.id, name, isInStock),
                              ),
                              Text(
                                isInStock ? 'In Stock ($stock)' : 'Out of Stock',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: isInStock ? (isLowStock ? Colors.orange.shade800 : AppColors.primaryGreen) : Colors.red,
                                ),
                              ),
                              const SizedBox(height: 4),
                              InkWell(
                                onTap: () => _confirmDelete(context, doc.id, name),
                                child: const Padding(
                                  padding: EdgeInsets.all(4.0),
                                  child: Icon(Icons.delete_outline_rounded, size: 16, color: Colors.grey),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    final bool isSelected = _selectedFilter == label;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (val) {
        if (val) setState(() => _selectedFilter = label);
      },
      selectedColor: AppColors.primaryGreenLight,
      labelStyle: TextStyle(
        fontSize: 11.5,
        fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
        color: isSelected ? AppColors.primaryGreen : AppColors.textDark,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: isSelected ? AppColors.primaryGreen : const Color(0xFFE2E8F0)),
      ),
      backgroundColor: Colors.white,
    );
  }
}
