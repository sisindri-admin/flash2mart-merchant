import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../constants/app_colors.dart';

class ComboOffersScreen extends StatefulWidget {
  const ComboOffersScreen({super.key});

  @override
  State<ComboOffersScreen> createState() => _ComboOffersScreenState();
}

class _ComboOffersScreenState extends State<ComboOffersScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _itemsController = TextEditingController();
  final _merchantPriceController = TextEditingController();
  final _mrpController = TextEditingController();
  final _stockController = TextEditingController(text: '20');
  final _descController = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  final List<Uint8List> _selectedImages = [];
  bool _isSubmitting = false;
  String? _editingDocId;

  @override
  void dispose() {
    _titleController.dispose();
    _itemsController.dispose();
    _merchantPriceController.dispose();
    _mrpController.dispose();
    _stockController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<Uint8List> _compressImage(Uint8List rawBytes, {int targetWidth = 350}) async {
    try {
      final ui.Codec codec = await ui.instantiateImageCodec(rawBytes, targetWidth: targetWidth);
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ByteData? byteData = await frameInfo.image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        return byteData.buffer.asUint8List();
      }
    } catch (e) {
      debugPrint('Combo image compression error: $e');
    }
    return rawBytes;
  }

  Future<void> _pickComboImage(ImageSource source) async {
    if (_selectedImages.length >= 3) {
      _showSnack('Maximum 3 images allowed per combo offer.', isError: true);
      return;
    }
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        imageQuality: 60,
        maxWidth: 400,
        maxHeight: 400,
      );
      if (file == null) return;
      final Uint8List rawBytes = await file.readAsBytes();
      Uint8List compressed = await _compressImage(rawBytes, targetWidth: 320);
      if (compressed.lengthInBytes > 90000) {
        compressed = await _compressImage(compressed, targetWidth: 220);
      }
      setState(() {
        _selectedImages.add(compressed);
      });
    } catch (e) {
      _showSnack('Failed to pick image: $e', isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.redAccent : AppColors.primaryGreen,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _submitComboOffer() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedImages.isEmpty && _editingDocId == null) {
      _showSnack('Please upload at least 1 combo image.', isError: true);
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isSubmitting = true);
    try {
      String storeName = 'Flash2Mart Partner';
      String locationAddress = 'Nellore, AP';
      GeoPoint? storeGeoPoint;

      final merchantDoc = await FirebaseFirestore.instance.collection('merchants').doc(user.uid).get();
      if (merchantDoc.exists && merchantDoc.data() != null) {
        final mData = merchantDoc.data()!;
        storeName = (mData['storeName'] ?? mData['shopName'] ?? mData['name'] ?? storeName).toString();
        locationAddress = (mData['address'] ?? mData['location'] ?? locationAddress).toString();
        if (mData['storeLocation'] is GeoPoint) {
          storeGeoPoint = mData['storeLocation'] as GeoPoint;
        }
      }

      final double mPrice = double.tryParse(_merchantPriceController.text.trim()) ?? 0.0;
      final double mrp = double.tryParse(_mrpController.text.trim()) ?? (mPrice * 1.25).ceilToDouble();
      final int stock = int.tryParse(_stockController.text.trim()) ?? 20;
      final int discount = mrp > mPrice && mrp > 0 ? (((mrp - mPrice) / mrp) * 100).round() : 0;

      final List<String> encodedImages = _selectedImages
          .map((b) => 'data:image/jpeg;base64,${base64Encode(b)}')
          .toList();

      final Map<String, dynamic> comboData = {
        'merchantId': user.uid,
        'storeName': storeName,
        'shopName': storeName,
        'location': locationAddress,
        if (storeGeoPoint != null) 'storeLocation': storeGeoPoint,
        'name': _titleController.text.trim(),
        'title': _titleController.text.trim(),
        'category': 'Combo Offers & Deals',
        'comboItems': _itemsController.text.trim(),
        'description': _descController.text.trim(),
        'merchantPrice': mPrice,
        'price': mPrice,
        'marketPrice': mrp,
        'discountPercent': discount,
        'discountTag': '$discount% OFF COMBO DEAL',
        'unit': 'Combo Pack',
        'weight': 'Combo Pack',
        'stock': stock,
        'isCombo': true,
        'isComboOffer': true,
        // Strictly pending until Admin verifies images & approves
        'isApproved': false,
        'isApprovedByAdmin': false,
        'status': 'pending_approval',
        'approvalStatus': 'pending_approval',
        'adminApprovalStatus': 'pending_approval',
        'verificationStatus': 'Pending Admin Approval',
        if (encodedImages.isNotEmpty) 'imageBase64': encodedImages.first,
        if (encodedImages.isNotEmpty) 'imageUrl': encodedImages.first,
        if (encodedImages.isNotEmpty) 'images': encodedImages,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (_editingDocId != null) {
        await FirebaseFirestore.instance.collection('products').doc(_editingDocId).set(comboData, SetOptions(merge: true));
        _showSnack('✅ Combo updated and sent for Admin verification!');
      } else {
        final ref = FirebaseFirestore.instance.collection('products').doc();
        comboData['productId'] = ref.id;
        comboData['id'] = ref.id;
        comboData['createdAt'] = FieldValue.serverTimestamp();
        await ref.set(comboData);
        _showSnack('🎉 Combo Offer submitted! Live in Customer App once Admin approves.');
      }

      _resetForm();
    } catch (e) {
      _showSnack('Failed to submit combo: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _resetForm() {
    setState(() {
      _editingDocId = null;
      _titleController.clear();
      _itemsController.clear();
      _merchantPriceController.clear();
      _mrpController.clear();
      _stockController.text = '20';
      _descController.clear();
      _selectedImages.clear();
    });
  }

  Widget _buildImagePreview(String imgStr) {
    final trimmed = imgStr.trim();
    if (trimmed.isEmpty) {
      return const Icon(Icons.local_offer_rounded, color: Colors.deepPurple, size: 28);
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return Image.network(trimmed, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image));
    }
    try {
      final clean = trimmed.contains(',') ? trimmed.split(',').last : trimmed;
      return Image.memory(base64Decode(clean.trim()), fit: BoxFit.cover);
    } catch (_) {
      return const Icon(Icons.image_not_supported, color: Colors.grey);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Please login first.')));
    }

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.local_offer_rounded, color: Color(0xFF7C3AED), size: 22),
            SizedBox(width: 8),
            Text('Combo Offers Manager', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textDark,
        elevation: 0.5,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Create / Edit Combo Offer Form Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF7C3AED).withAlpha(60), width: 1.3),
                boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _editingDocId == null ? '✨ Create New Combo Offer' : '✏️ Edit Combo Offer',
                          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900, color: Color(0xFF4C1D95)),
                        ),
                        if (_editingDocId != null)
                          TextButton(
                            onPressed: _resetForm,
                            child: const Text('Cancel Edit', style: TextStyle(color: Colors.redAccent)),
                          ),
                      ],
                    ),
                    const Text(
                      'Admin will verify your combo images & price before publishing to Customer App.',
                      style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 14),

                    TextFormField(
                      controller: _titleController,
                      decoration: InputDecoration(
                        labelText: 'Combo Offer Title *',
                        hintText: 'e.g. Sunday Chicken Biryani Combo Pack',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        prefixIcon: const Icon(Icons.title_rounded, color: Color(0xFF7C3AED)),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter combo title' : null,
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _itemsController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Combo Items Included *',
                        hintText: 'e.g. 1kg Basmati Rice, 500g Chicken, Masala Pack, 500g Curd',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        prefixIcon: const Icon(Icons.list_alt_rounded, color: Color(0xFF7C3AED)),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'List items in this combo' : null,
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _merchantPriceController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Your Combo Price (₹) *',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              prefixText: '₹',
                            ),
                            validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0 ? 'Enter price' : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: _mrpController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Actual MRP (₹)',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              prefixText: '₹',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 85,
                          child: TextFormField(
                            controller: _stockController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Stock',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _descController,
                      decoration: InputDecoration(
                        labelText: 'Offer Description (Optional)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Combo Multi-Image Upload
                    const Text('Combo Images (Max 3 Photos) *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        ..._selectedImages.asMap().entries.map((entry) {
                          return Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.memory(entry.value, width: 74, height: 74, fit: BoxFit.cover),
                              ),
                              Positioned(
                                top: 2,
                                right: 2,
                                child: GestureDetector(
                                  onTap: () => setState(() => _selectedImages.removeAt(entry.key)),
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
                                    child: const Icon(Icons.close, color: Colors.white, size: 14),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }),
                        if (_selectedImages.length < 3) ...[
                          InkWell(
                            onTap: () => _pickComboImage(ImageSource.gallery),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              width: 74,
                              height: 74,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF5F3FF),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFF7C3AED).withAlpha(100)),
                              ),
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.photo_library_rounded, color: Color(0xFF7C3AED), size: 22),
                                  SizedBox(height: 4),
                                  Text('Gallery', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF7C3AED))),
                                ],
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () => _pickComboImage(ImageSource.camera),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              width: 74,
                              height: 74,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF5F3FF),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFF7C3AED).withAlpha(100)),
                              ),
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.camera_alt_rounded, color: Color(0xFF7C3AED), size: 22),
                                  SizedBox(height: 4),
                                  Text('Camera', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF7C3AED))),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 18),

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7C3AED),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _isSubmitting ? null : _submitComboOffer,
                        icon: _isSubmitting
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.cloud_upload_rounded),
                        label: Text(
                          _isSubmitting ? 'SUBMITTING...' : 'SUBMIT COMBO FOR ADMIN APPROVAL',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 22),
            const Text('Your Submitted Combo Offers', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.textDark)),
            const SizedBox(height: 10),

            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('products')
                  .where('merchantId', isEqualTo: user.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFF7C3AED)));
                }
                final docs = (snapshot.hasData ? snapshot.data!.docs : <QueryDocumentSnapshot>[]).where((d) {
                  final data = d.data() as Map<String, dynamic>;
                  return data['isCombo'] == true || data['isComboOffer'] == true;
                }).toList();

                if (docs.isEmpty) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.local_offer_outlined, size: 40, color: AppColors.textMuted),
                        SizedBox(height: 8),
                        Text('No combo offers submitted yet.', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: docs.length,
                  itemBuilder: (context, idx) {
                    final doc = docs[idx];
                    final data = doc.data() as Map<String, dynamic>;
                    final title = (data['name'] ?? data['title'] ?? 'Combo Deal').toString();
                    final items = (data['comboItems'] ?? '').toString();
                    final double mPrice = ((data['merchantPrice'] ?? data['price'] ?? 0) as num).toDouble();
                    final bool isApproved = data['isApproved'] == true && data['status'] == 'approved';
                    final String status = (data['status'] ?? 'pending_approval').toString().toLowerCase();
                    final String img = (data['imageBase64'] ?? data['imageUrl'] ?? '').toString();

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      elevation: 0.5,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: isApproved ? AppColors.primaryGreen.withAlpha(80) : const Color(0xFFF59E0B).withAlpha(100)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                width: 62,
                                height: 62,
                                color: const Color(0xFFF5F3FF),
                                child: _buildImagePreview(img),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                                  if (items.isNotEmpty)
                                    Text(items, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Text('Your Price: ₹${mPrice.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: Color(0xFF7C3AED))),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isApproved
                                              ? const Color(0xFFDCFCE7)
                                              : (status == 'rejected' ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7)),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          isApproved ? 'LIVE ✅' : (status == 'rejected' ? 'REJECTED ❌' : 'PENDING ⏳'),
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w900,
                                            color: isApproved ? const Color(0xFF16A34A) : (status == 'rejected' ? Colors.red : const Color(0xFFD97706)),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                              onPressed: () => FirebaseFirestore.instance.collection('products').doc(doc.id).delete(),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
