import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

// Variant Model with Market Price, Flash2Mart Price & Discount Calculation
class ProductVariantItem {
  final TextEditingController unitController;
  final TextEditingController marketPriceController; // Market Price (MRP)
  final TextEditingController priceController; // Flash2Mart Price
  final TextEditingController stockController;
  int presentStock;

  ProductVariantItem({
    String unit = '1 kg',
    String marketPrice = '',
    String price = '',
    String stock = '',
    this.presentStock = 0,
  })  : unitController = TextEditingController(text: unit),
        marketPriceController = TextEditingController(text: marketPrice),
        priceController = TextEditingController(text: price),
        stockController = TextEditingController(text: stock);

  int get enteredStock => int.tryParse(stockController.text.trim()) ?? 0;
  int get totalStock =>
      presentStock > 0 ? (presentStock + enteredStock) : enteredStock;

  // Percentage Offer Calculation
  double get marketPriceVal =>
      double.tryParse(marketPriceController.text.trim()) ?? 0.0;
  double get flash2martPriceVal =>
      double.tryParse(priceController.text.trim()) ?? 0.0;

  int get discountPercentage {
    if (marketPriceVal > 0 &&
        flash2martPriceVal > 0 &&
        marketPriceVal > flash2martPriceVal) {
      double discount =
          ((marketPriceVal - flash2martPriceVal) / marketPriceVal) * 100;
      return discount.round();
    }
    return 0;
  }

  void dispose() {
    unitController.dispose();
    marketPriceController.dispose();
    priceController.dispose();
    stockController.dispose();
  }
}

class AddProductScreen extends StatefulWidget {
  final String? editDocId;
  final Map<String, dynamic>? editData;

  const AddProductScreen({
    super.key,
    this.editDocId,
    this.editData,
  });

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _brandController = TextEditingController();
  final _categoryController =
      TextEditingController(text: 'Grocery / Supermarket');
  final _descriptionController = TextEditingController();
  final _comboItemsController = TextEditingController();
  final FocusNode _nameFocusNode = FocusNode();

  String? _selectedExistingDocId;
  bool _isComboOffer = false;

  List<ProductVariantItem> _variants = [
    ProductVariantItem(
        unit: '1 kg', marketPrice: '', price: '', stock: '100', presentStock: 0),
  ];

  List<QueryDocumentSnapshot> _allProducts = [];
  String _topStockFilter = 'All';
  bool _isLoadingProducts = true;

  Uint8List? _primaryImageBytes;
  final List<Uint8List> _extraImageBytesList = [];
  bool _isLoading = false;

  final ImagePicker _picker = ImagePicker();

  // Theme Colors
  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color primaryPurple = Color(0xFF4F46E5);
  static const Color bgGrey = Color(0xFFF8FAFC);
  static const Color textDark = Color(0xFF1E293B);

  // 100% Synced Categories matching Customer App
  static const List<String> standardCategories = [
    'Grocery / Supermarket',
    'Vegetables & Fruits',
    'Combo Offers & Deals',
    'Medicines & Pharmacy',
    'Electronics Store',
  ];

  final List<String> _popularBrands = [
    'Aashirvaad',
    'Heritage',
    'Amul',
    'Freedom',
    'Tata',
    'Fortune',
    'Dodla',
    'Tirumala',
  ];

  @override
  void initState() {
    super.initState();
    _initEditModeOrFetchAll();
  }

  void _initEditModeOrFetchAll() {
    if (widget.editDocId != null && widget.editData != null) {
      _selectedExistingDocId = widget.editDocId;
      final data = widget.editData!;
      _nameController.text = data['name'] ?? '';
      _brandController.text = data['brand'] ?? '';
      _categoryController.text = data['category'] ?? 'Grocery / Supermarket';
      _descriptionController.text = data['description'] ?? '';

      _isComboOffer = data['isCombo'] == true ||
          data['isComboOffer'] == true ||
          _categoryController.text.contains('Combo');
      _comboItemsController.text = data['comboItems'] ?? '';

      final String img = data['imageBase64'] ?? data['imageUrl'] ?? '';
      if (img.isNotEmpty) {
        try {
          final clean = img.contains(',') ? img.split(',').last : img;
          _primaryImageBytes = base64Decode(clean.trim());
        } catch (_) {}
      }

      if (data['images'] is List) {
        for (var extra in data['images'] as List) {
          if (extra != null && extra.toString().trim().isNotEmpty) {
            try {
              final clean = extra.toString().contains(',')
                  ? extra.toString().split(',').last
                  : extra.toString();
              _extraImageBytesList.add(base64Decode(clean.trim()));
            } catch (_) {}
          }
        }
      }

      final rawVariants = data['variants'] as List<dynamic>?;
      if (rawVariants != null && rawVariants.isNotEmpty) {
        _variants.clear();
        for (var item in rawVariants) {
          final m = item as Map<String, dynamic>;
          final int existingStock = (m['stock'] is int
                  ? m['stock']
                  : int.tryParse('${m['stock']}')) ??
              0;
          _variants.add(
            ProductVariantItem(
              unit: m['unit'] ?? '1 kg',
              marketPrice: '${m['marketPrice'] ?? m['price'] ?? ''}',
              price: '${m['price'] ?? ''}',
              stock: '',
              presentStock: existingStock,
            ),
          );
        }
      } else {
        final int existingStock = (data['stock'] is int
                ? data['stock']
                : int.tryParse('${data['stock']}')) ??
            0;
        _variants = [
          ProductVariantItem(
            unit: data['unit'] ?? '1 kg',
            marketPrice: '${data['marketPrice'] ?? data['price'] ?? ''}',
            price: '${data['price'] ?? ''}',
            stock: '',
            presentStock: existingStock,
          ),
        ];
      }
    }

    _fetchAllStoreProducts();
  }

  Future<void> _fetchAllStoreProducts() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('products')
          .where('merchantId', isEqualTo: user.uid)
          .get();

      if (mounted) {
        setState(() {
          _allProducts = snapshot.docs;
          _isLoadingProducts = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingProducts = false);
    }
  }

  void _selectProductFromInventory(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    setState(() {
      _selectedExistingDocId = doc.id;
      _nameController.text = data['name'] ?? '';
      _brandController.text = data['brand'] ?? '';
      _categoryController.text = data['category'] ?? 'Grocery / Supermarket';
      _descriptionController.text = data['description'] ?? '';

      _isComboOffer = data['isCombo'] == true ||
          data['isComboOffer'] == true ||
          _categoryController.text.contains('Combo');
      _comboItemsController.text = data['comboItems'] ?? '';

      final String imageBase64 = data['imageBase64'] ?? data['imageUrl'] ?? '';
      if (imageBase64.isNotEmpty) {
        try {
          final clean = imageBase64.contains(',')
              ? imageBase64.split(',').last
              : imageBase64;
          _primaryImageBytes = base64Decode(clean.trim());
        } catch (_) {
          _primaryImageBytes = null;
        }
      } else {
        _primaryImageBytes = null;
      }

      for (var v in _variants) {
        v.dispose();
      }
      _variants.clear();

      final rawVariants = data['variants'] as List<dynamic>?;
      if (rawVariants != null && rawVariants.isNotEmpty) {
        for (var item in rawVariants) {
          final m = item as Map<String, dynamic>;
          final int existingStock = (m['stock'] is int
                  ? m['stock']
                  : int.tryParse('${m['stock']}')) ??
              0;
          _variants.add(
            ProductVariantItem(
              unit: m['unit'] ?? '1 kg',
              marketPrice: '${m['marketPrice'] ?? m['price'] ?? ''}',
              price: '${m['price'] ?? ''}',
              stock: '',
              presentStock: existingStock,
            ),
          );
        }
      } else {
        final int existingStock = (data['stock'] is int
                ? data['stock']
                : int.tryParse('${data['stock']}')) ??
            0;
        _variants.add(
          ProductVariantItem(
            unit: data['unit'] ?? '1 kg',
            marketPrice: '${data['marketPrice'] ?? data['price'] ?? ''}',
            price: '${data['price'] ?? ''}',
            stock: '',
            presentStock: existingStock,
          ),
        );
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Loaded "${data['name']}". Edit details & save!'),
        backgroundColor: Colors.teal,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _resetFormForNewProduct() {
    setState(() {
      _selectedExistingDocId = null;
      _isComboOffer = false;
      _comboItemsController.clear();
      _nameController.clear();
      _brandController.clear();
      _categoryController.text = 'Grocery / Supermarket';
      _descriptionController.clear();
      _primaryImageBytes = null;
      _extraImageBytesList.clear();
      for (var v in _variants) {
        v.dispose();
      }
      _variants = [
        ProductVariantItem(
            unit: '1 kg', marketPrice: '', price: '', stock: '100', presentStock: 0),
      ];
    });
  }

  void _addVariant() {
    setState(() {
      _variants.add(ProductVariantItem(
          unit: '500 gm', marketPrice: '', price: '', stock: '50', presentStock: 0));
    });
  }

  void _removeVariant(int index) {
    if (_variants.length > 1) {
      setState(() {
        _variants[index].dispose();
        _variants.removeAt(index);
      });
    }
  }

  Future<void> _pickImage(ImageSource source, {bool isExtra = false}) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        maxWidth: 650,
        maxHeight: 650,
        imageQuality: 70,
      );

      if (file != null) {
        final bytes = await file.readAsBytes();
        if (mounted) {
          setState(() {
            if (isExtra) {
              if (_extraImageBytesList.length < 3) {
                _extraImageBytesList.add(bytes);
              }
            } else {
              _primaryImageBytes = bytes;
            }
          });
          _showMessage(isExtra
              ? 'Extra carousel image added!'
              : 'Product image selected successfully!');
        }
      }
    } catch (e) {
      _showMessage('Unable to access camera or gallery: $e');
    }
  }

  void _onImageUploaderTap({bool isExtra = false}) {
    FocusScope.of(context).unfocus();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (bottomSheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isExtra ? 'Add Extra Carousel Photo' : 'Upload Product Photo',
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: textDark),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        size: 20, color: Colors.grey),
                    onPressed: () => Navigator.pop(bottomSheetContext),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        Navigator.pop(bottomSheetContext);
                        await Future.delayed(const Duration(milliseconds: 200));
                        _pickImage(ImageSource.camera, isExtra: isExtra);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFC7D2FE)),
                        ),
                        child: const Column(
                          children: [
                            Icon(Icons.camera_alt_rounded,
                                color: primaryBlue, size: 30),
                            SizedBox(height: 8),
                            Text('Take Photo',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: primaryBlue,
                                    fontSize: 13.5)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        Navigator.pop(bottomSheetContext);
                        await Future.delayed(const Duration(milliseconds: 200));
                        _pickImage(ImageSource.gallery, isExtra: isExtra);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: const Column(
                          children: [
                            Icon(Icons.photo_library_rounded,
                                color: textDark, size: 30),
                            SizedBox(height: 8),
                            Text('From Gallery',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: textDark,
                                    fontSize: 13.5)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  // 100% Synchronization with Customer App: Saves storeLocation, storeName, combo offers & multi-images
  Future<void> _submitProduct() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showMessage('Please login first.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Fetch current merchant profile to attach storeLocation GeoPoint and storeName
      final merchantDoc = await FirebaseFirestore.instance
          .collection('merchants')
          .doc(user.uid)
          .get();
      final mData = merchantDoc.data() ?? {};
      final String storeName = (mData['storeName'] ??
              mData['shopName'] ??
              mData['name'] ??
              'Flash2Mart Partner Store')
          .toString();
      final String locationAddress =
          (mData['location'] ?? mData['address'] ?? 'Nellore, Andhra Pradesh')
              .toString();

      final dynamic rawStoreLoc =
          mData['storeLocation'] ?? mData['merchantLocation'];
      GeoPoint? storeGeoPoint;
      double? storeLat = (mData['latitude'] ?? mData['storeLat']) is num
          ? (mData['latitude'] ?? mData['storeLat']).toDouble()
          : null;
      double? storeLng = (mData['longitude'] ?? mData['storeLng']) is num
          ? (mData['longitude'] ?? mData['storeLng']).toDouble()
          : null;

      if (rawStoreLoc is GeoPoint) {
        storeGeoPoint = rawStoreLoc;
        storeLat ??= rawStoreLoc.latitude;
        storeLng ??= rawStoreLoc.longitude;
      } else if (storeLat != null && storeLng != null) {
        storeGeoPoint = GeoPoint(storeLat, storeLng);
      }

      // 2. Primary image and extra carousel images
      String primaryBase64 = '';
      if (_primaryImageBytes != null) {
        primaryBase64 = base64Encode(_primaryImageBytes!);
      }

      final List<String> extraBase64Images = [];
      for (final extraBytes in _extraImageBytesList) {
        extraBase64Images.add(base64Encode(extraBytes));
      }

      // 3. Variants & Pricing
      final List<Map<String, dynamic>> variantDataList = _variants.map((v) {
        final mPrice = v.marketPriceVal;
        final fPrice = v.flash2martPriceVal;
        return {
          'unit': v.unitController.text.trim(),
          'marketPrice': mPrice > 0 ? mPrice : (fPrice * 1.18).ceilToDouble(),
          'price': fPrice,
          'discountPercent': v.discountPercentage,
          'stock': v.totalStock,
        };
      }).toList();

      final double primaryPrice = variantDataList.isNotEmpty
          ? (variantDataList.first['price'] as num).toDouble()
          : 0.0;
      final double primaryMarketPrice = variantDataList.isNotEmpty
          ? (variantDataList.first['marketPrice'] as num).toDouble()
          : (primaryPrice * 1.18).ceilToDouble();
      final String primaryUnit = variantDataList.isNotEmpty
          ? variantDataList.first['unit'].toString()
          : '1 kg';
      final int totalStock = variantDataList.fold<int>(
          0, (sum, v) => sum + ((v['stock'] as int?) ?? 0));

      final int primaryDiscount = primaryMarketPrice > primaryPrice &&
              primaryMarketPrice > 0
          ? (((primaryMarketPrice - primaryPrice) / primaryMarketPrice) * 100)
              .round()
          : 0;

      final bool isCombo = _isComboOffer ||
          _categoryController.text.toLowerCase().contains('combo');
      final String comboItems = _comboItemsController.text.trim();

      // 4. Construct Full Synchronized Document Data
      final Map<String, dynamic> docData = {
        'merchantId': user.uid,
        'storeName': storeName,
        'shopName': storeName,
        'location': locationAddress,
        'merchantLocationAddress': locationAddress,
        if (storeGeoPoint != null) 'storeLocation': storeGeoPoint,
        if (storeGeoPoint != null) 'merchantLocation': storeGeoPoint,
        if (storeLat != null) 'storeLat': storeLat,
        if (storeLng != null) 'storeLng': storeLng,
        if (storeLat != null) 'latitude': storeLat,
        if (storeLng != null) 'longitude': storeLng,
        'name': _nameController.text.trim(),
        'title': _nameController.text.trim(),
        'brand': _brandController.text.trim(),
        'category': _categoryController.text.trim(),
        'description': _descriptionController.text.trim(),
        'price': primaryPrice,
        'marketPrice': primaryMarketPrice,
        'discountPercent': primaryDiscount,
        'unit': primaryUnit,
        'weight': primaryUnit,
        'stock': totalStock,
        'variants': variantDataList,
        'isCombo': isCombo,
        'isComboOffer': isCombo,
        'comboItems': comboItems,
        'discountTag': isCombo
            ? '$primaryDiscount% OFF COMBO'
            : '$primaryDiscount% OFF',
        if (primaryBase64.isNotEmpty) 'imageBase64': primaryBase64,
        if (primaryBase64.isNotEmpty) 'imageUrl': primaryBase64,
        if (primaryBase64.isNotEmpty) 'image': primaryBase64,
        if (extraBase64Images.isNotEmpty) 'images': extraBase64Images,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (_selectedExistingDocId != null) {
        await FirebaseFirestore.instance
            .collection('products')
            .doc(_selectedExistingDocId)
            .set(docData, SetOptions(merge: true));
        _showMessage('Product updated & saved successfully!');
      } else {
        final newDocRef =
            FirebaseFirestore.instance.collection('products').doc();
        docData['productId'] = newDocRef.id;
        docData['createdAt'] = FieldValue.serverTimestamp();
        await newDocRef.set(docData);
        _showMessage('New product added successfully!');
      }

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      _showMessage('Failed to save: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    _comboItemsController.dispose();
    _nameFocusNode.dispose();
    for (var v in _variants) {
      v.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isEditMode = _selectedExistingDocId != null;

    return Scaffold(
      backgroundColor: bgGrey,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: textDark,
        centerTitle: true,
        title: Text(
          isEditMode ? 'Edit / Update Product' : 'Add Product & Combos',
          style: const TextStyle(
              fontWeight: FontWeight.w800, fontSize: 18, color: textDark),
        ),
        actions: [
          if (isEditMode)
            TextButton.icon(
              onPressed: _resetFormForNewProduct,
              icon: const Icon(Icons.add, size: 16, color: primaryBlue),
              label: const Text('New Product',
                  style: TextStyle(
                      color: primaryBlue,
                      fontWeight: FontWeight.bold,
                      fontSize: 12)),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryBlue))
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAllStoreStockSelector(),
                    const SizedBox(height: 14),

                    // 1. PRODUCT DETAILS & CATEGORY SELECTOR CARD
                    _buildFormCard(
                      title: isEditMode
                          ? 'Product Details (Editing)'
                          : 'Product, Category & Combos',
                      icon: Icons.inventory_2_outlined,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTextField(
                            controller: _nameController,
                            focusNode: _nameFocusNode,
                            label: 'Product Name',
                            hint: 'e.g. Heritage Toned Milk, Fresh Tomatoes',
                            icon: Icons.shopping_basket_outlined,
                            validator: (val) => val == null || val.trim().isEmpty
                                ? 'Enter product name'
                                : null,
                          ),
                          const SizedBox(height: 14),

                          _buildTextField(
                            controller: _brandController,
                            label: 'Brand Name',
                            hint: 'e.g. Heritage, Aashirvaad, Amul, Tata',
                            icon: Icons.branding_watermark_outlined,
                          ),
                          const SizedBox(height: 8),

                          const Text(
                            'Quick Brands:',
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF64748B)),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: _popularBrands.map((b) {
                              return InkWell(
                                onTap: () =>
                                    setState(() => _brandController.text = b),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3.5),
                                  decoration: BoxDecoration(
                                    color: _brandController.text == b
                                        ? primaryPurple.withAlpha(28)
                                        : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _brandController.text == b
                                          ? primaryPurple
                                          : Colors.transparent,
                                    ),
                                  ),
                                  child: Text(
                                    b,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: _brandController.text == b
                                          ? primaryPurple
                                          : const Color(0xFF475569),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 14),

                          // Standard Customer App Categories Selector
                          const Text(
                            'Category (100% Synced with Customer App):',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E293B)),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: standardCategories.map((cat) {
                              final bool isSelected =
                                  _categoryController.text == cat;
                              return ChoiceChip(
                                label: Text(cat),
                                labelStyle: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.w600,
                                  color: isSelected ? Colors.white : textDark,
                                ),
                                selected: isSelected,
                                selectedColor: primaryBlue,
                                backgroundColor: const Color(0xFFF1F5F9),
                                onSelected: (selected) {
                                  if (selected) {
                                    setState(() {
                                      _categoryController.text = cat;
                                      if (cat == 'Combo Offers & Deals') {
                                        _isComboOffer = true;
                                      }
                                    });
                                  }
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 10),

                          _buildTextField(
                            controller: _categoryController,
                            label: 'Custom Category Name',
                            hint: 'Category',
                            icon: Icons.category_outlined,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 2. COMBO OFFERS & SUPER SAVERS BUILDER CARD
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFFBEB), Color(0xFFFEF3C7)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFFDE68A),
                          width: 1.2,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.celebration_rounded,
                                      color: Color(0xFFD97706), size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'Combo Offer / Super Saver Pack',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF92400E),
                                    ),
                                  ),
                                ],
                              ),
                              Switch(
                                value: _isComboOffer,
                                activeColor: const Color(0xFFD97706),
                                onChanged: (val) {
                                  setState(() {
                                    _isComboOffer = val;
                                    if (val) {
                                      _categoryController.text =
                                          'Combo Offers & Deals';
                                    }
                                  });
                                },
                              ),
                            ],
                          ),
                          const Text(
                            'మీరు కాంబో ఆఫర్స్ క్రియేట్ చేస్తే అది కస్టమర్ యాప్‌లో "Today Offer" మరియు కాంబో బ్యానర్స్ లో ఆటోమేటిక్‌గా కనిపిస్తుంది.',
                            style: TextStyle(
                                fontSize: 11, color: Color(0xFF78350F)),
                          ),
                          if (_isComboOffer) ...[
                            const SizedBox(height: 10),
                            _buildTextField(
                              controller: _comboItemsController,
                              label: 'Included Items in Combo',
                              hint:
                                  'e.g. 1L Heritage Milk + 500g Curd + Bread',
                              icon: Icons.check_circle_outline_rounded,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 3. MULTI-IMAGE CAROUSEL UPLOADER
                    _buildSquareImageUploader(),
                    const SizedBox(height: 14),

                    // 4. QUANTITIES, PRICES & INVENTORY
                    _buildFormCard(
                      title: 'Quantities, Prices & Stock',
                      icon: Icons.layers_outlined,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ధర మరియు స్టాక్ మార్పులు చేయండి:',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF64748B)),
                          ),
                          const SizedBox(height: 12),

                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _variants.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final variant = _variants[index];
                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: const Color(0xFFE2E8F0)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Option ${index + 1}',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              color: primaryBlue),
                                        ),
                                        if (_variants.length > 1)
                                          InkWell(
                                            onTap: () => _removeVariant(index),
                                            child: const Icon(
                                                Icons.delete_outline_rounded,
                                                color: Colors.redAccent,
                                                size: 20),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),

                                    Row(
                                      children: [
                                        Expanded(
                                          flex: 5,
                                          child: _buildTextField(
                                            controller: variant.unitController,
                                            label: 'Qty/Unit',
                                            hint: '1 kg, 500gm',
                                            icon: Icons.scale_outlined,
                                            validator: (val) => val == null ||
                                                    val.trim().isEmpty
                                                ? 'Enter qty'
                                                : null,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          flex: 5,
                                          child: _buildTextField(
                                            controller:
                                                variant.marketPriceController,
                                            label: 'MRP (₹)',
                                            hint: '120',
                                            icon: Icons.money_off_csred_rounded,
                                            keyboardType: TextInputType.number,
                                            onChanged: (_) => setState(() {}),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),

                                    Row(
                                      children: [
                                        Expanded(
                                          flex: 5,
                                          child: _buildTextField(
                                            controller: variant.priceController,
                                            label: 'Offer Price (₹)',
                                            hint: '95',
                                            icon: Icons.currency_rupee_rounded,
                                            keyboardType: TextInputType.number,
                                            validator: (val) => val == null ||
                                                    val.trim().isEmpty
                                                ? 'Enter price'
                                                : null,
                                            onChanged: (_) => setState(() {}),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          flex: 5,
                                          child: _buildTextField(
                                            controller: variant.stockController,
                                            label: variant.presentStock > 0
                                                ? 'Add Stock'
                                                : 'Total Stock',
                                            hint: '50',
                                            icon: Icons.inventory_rounded,
                                            keyboardType: TextInputType.number,
                                            validator: (val) {
                                              if (variant.presentStock <= 0 &&
                                                  (val == null ||
                                                      val.trim().isEmpty)) {
                                                return 'Enter stock';
                                              }
                                              return null;
                                            },
                                          ),
                                        ),
                                      ],
                                    ),

                                    // Real-time % OFF pill
                                    if (variant.discountPercentage > 0)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFDCFCE7),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            '🎉 ${variant.discountPercentage}% OFF (Customer App లో గ్రీన్ కలర్ లో కనిపిస్తుంది)',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF15803D),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 10),

                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: primaryBlue,
                              side: const BorderSide(color: primaryBlue),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: _addVariant,
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Add Another Size / Pack',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12.5)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 5. DESCRIPTION
                    _buildFormCard(
                      title: 'Description & Highlights (Optional)',
                      icon: Icons.description_outlined,
                      child: _buildTextField(
                        controller: _descriptionController,
                        label: 'Description',
                        hint: 'Fresh local grocery item delivered in 15 mins.',
                        maxLines: 2,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // SUBMIT BUTTON
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryBlue,
                          foregroundColor: Colors.white,
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _submitProduct,
                        icon: const Icon(Icons.cloud_upload_rounded, size: 20),
                        label: Text(
                          isEditMode
                              ? 'UPDATE PRODUCT & SYNC'
                              : 'SAVE & SYNC TO CUSTOMER APP',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14.5,
                              letterSpacing: 0.3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildAllStoreStockSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x05000000),
              blurRadius: 6,
              offset: Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: primaryBlue.withAlpha(24),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.inventory_2_rounded,
                    size: 16, color: primaryBlue),
              ),
              const SizedBox(width: 8),
              const Text(
                'Select from Existing Products',
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: textDark),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _stockFilterTab('All'),
                _stockFilterTab('Grocery'),
                _stockFilterTab('Vegetables'),
                _stockFilterTab('Combos'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_isLoadingProducts)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(strokeWidth: 2)))
          else if (_allProducts.isEmpty)
            const Text('No products in store yet. Add your first item below.',
                style: TextStyle(fontSize: 12, color: Colors.grey))
          else
            SizedBox(
              height: 38,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _allProducts.length,
                itemBuilder: (context, index) {
                  final doc = _allProducts[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final name = data['name'] ?? '';
                  final isSelected = _selectedExistingDocId == doc.id;

                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(name),
                      labelStyle: TextStyle(
                        fontSize: 11,
                        color: isSelected ? Colors.white : textDark,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      selected: isSelected,
                      selectedColor: primaryBlue,
                      backgroundColor: const Color(0xFFF1F5F9),
                      onSelected: (selected) {
                        if (selected) {
                          _selectProductFromInventory(doc);
                        }
                      },
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _stockFilterTab(String label) {
    final isSelected = _topStockFilter == label;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: () => setState(() => _topStockFilter = label),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: isSelected ? primaryBlue : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : const Color(0xFF475569),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSquareImageUploader() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x05000000),
              blurRadius: 6,
              offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Product Images (Multi-Image Carousel)',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: textDark),
              ),
              Text('Up to 4 images',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // 1. Primary Photo
              InkWell(
                onTap: () => _onImageUploaderTap(isExtra: false),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _primaryImageBytes != null
                          ? const Color(0xFF22C55E)
                          : const Color(0xFFCBD5E1),
                      width: 1.5,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _primaryImageBytes != null
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.memory(_primaryImageBytes!, fit: BoxFit.cover),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.edit,
                                    size: 11, color: Colors.white),
                              ),
                            ),
                          ],
                        )
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_a_photo_rounded,
                                size: 24, color: primaryBlue),
                            SizedBox(height: 4),
                            Text('Primary',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: primaryBlue)),
                          ],
                        ),
                ),
              ),
              const SizedBox(width: 10),

              // 2. Extra Carousel Images
              Expanded(
                child: SizedBox(
                  height: 90,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      ...List.generate(_extraImageBytesList.length, (idx) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.memory(
                                  _extraImageBytesList[idx],
                                  width: 80,
                                  height: 90,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 2,
                                right: 2,
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      _extraImageBytesList.removeAt(idx);
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: const BoxDecoration(
                                      color: Colors.redAccent,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.close,
                                        size: 12, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      if (_extraImageBytesList.length < 3)
                        InkWell(
                          onTap: () => _onImageUploaderTap(isExtra: true),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 80,
                            height: 90,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFCBD5E1),
                                style: BorderStyle.solid,
                              ),
                            ),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_photo_alternate_outlined,
                                    size: 20, color: Color(0xFF64748B)),
                                SizedBox(height: 3),
                                Text('+ Extra',
                                    style: TextStyle(
                                        fontSize: 9.5,
                                        color: Color(0xFF64748B))),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x05000000),
              blurRadius: 6,
              offset: Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: primaryBlue),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: textDark),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    IconData? icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    String? Function(String?)? validator,
    FocusNode? focusNode,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 13, color: textDark),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
        prefixIcon: icon != null
            ? Icon(icon, size: 18, color: const Color(0xFF64748B))
            : null,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: primaryBlue, width: 1.5),
        ),
      ),
    );
  }
}