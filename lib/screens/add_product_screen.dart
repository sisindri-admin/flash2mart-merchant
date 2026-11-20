import 'dart:ui' as ui;
import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/master_catalog_service.dart';
import '../widgets/dashboard/barcode_scanner_simulator_dialog.dart';

// Variant Model with Market Price, Flash2Mart Price & Discount Calculation
class ProductVariantItem {
  final TextEditingController unitController;
  final TextEditingController marketPriceController; // Market Price (MRP)
  final TextEditingController priceController; // Flash2Mart Selling Price
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
  final _subCategoryController = TextEditingController();
  final _childCategoryController = TextEditingController();
  final Map<String, List<String>> _subCategoriesByCat = {};
  final Map<String, List<String>> _childCategoriesBySub = {};
  final _descriptionController = TextEditingController();
  final _comboItemsController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _masterSearchController = TextEditingController();
  final FocusNode _nameFocusNode = FocusNode();

  String? _selectedExistingDocId;
  bool _isComboOffer = false;
  String _networkImageUrl = '';

  List<ProductVariantItem> _variants = [
    ProductVariantItem(
        unit: '1 kg', marketPrice: '', price: '', stock: '100', presentStock: 0),
  ];

  List<QueryDocumentSnapshot> _allProducts = [];
  String _topStockFilter = 'All';

  // Primary image bytes + Multi-image support (more than 1 image)
  Uint8List? _primaryImageBytes;
  final List<Uint8List> _comboMultipleImageBytesList = [];
  bool _isLoading = false;

  final ImagePicker _picker = ImagePicker();

  // Master Catalog Search Results
  List<MasterProductItem> _searchedMasterItems = [];
  bool _showMasterSuggestions = false;

  // Theme Colors
  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color primaryPurple = Color(0xFF4F46E5);
  static const Color accentGreen = Color(0xFF16A34A);
  static const Color bgGrey = Color(0xFFF8FAFC);
  static const Color cardBorder = Color(0xFFE2E8F0);
  static const Color textDark = Color(0xFF0F172A);

  List<String> _quickCategories = [
    'Grocery / Supermarket',
    'Vegetables & Fruits',
    'Dairy, Bread & Eggs',
    'Atta, Rice & Dals',
    'Oils & Ghee',
    'Snacks & Munchies',
    'Beverages & Drinks',
    'Instant & Frozen Food',
    'Combo Offers & Deals',
    'Medicines & Pharmacy',
    'Cleaning & Household',
    'Electronics & Home',
  ];

  final List<String> _quickBrands = const [
    'Amul',
    'Aashirvaad',
    'Fortune',
    'Tata',
    'Britannia',
    'Nestle',
    'Farm Fresh',
    'Dettol',
    'Parle',
    'Colgate',
  ];

  @override
  void initState() {
    super.initState();
    _fetchAllStoreProducts();
    _fetchCategoriesFromFirestore();

    if (widget.editDocId != null && widget.editData != null) {
      _loadProductForEditing(widget.editDocId!, widget.editData!);
    }

    _nameController.addListener(_autoDetectCategoryFromName);
  }

  @override
  void dispose() {
    _nameController.removeListener(_autoDetectCategoryFromName);
    _nameController.dispose();
    _brandController.dispose();
    _categoryController.dispose();
    _subCategoryController.dispose();
    _childCategoryController.dispose();
    _descriptionController.dispose();
    _comboItemsController.dispose();
    _barcodeController.dispose();
    _masterSearchController.dispose();
    _nameFocusNode.dispose();
    for (final v in _variants) {
      v.dispose();
    }
    super.dispose();
  }

  // Fetch real-time approved categories from Firestore
  Future<void> _fetchCategoriesFromFirestore() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('categories').get();
      final List<String> fetched = [];
      for (var doc in snap.docs) {
        final data = doc.data();
        final name = (data['name'] ?? data['categoryName'] ?? '').toString().trim();
        if (name.isNotEmpty) {
          if (!fetched.contains(name)) fetched.add(name);
          if (data['subCategories'] is List) {
            final List<String> subs = [];
            for (final m in (data['subCategories'] as List).whereType<Map>()) {
              final sName = (m['name'] ?? '').toString().trim();
              if (sName.isNotEmpty) {
                subs.add(sName);
                if (m['childCategories'] is List) {
                  final kids = (m['childCategories'] as List)
                      .whereType<Map>()
                      .map((k) => (k['name'] ?? '').toString().trim())
                      .where((s) => s.isNotEmpty)
                      .toList();
                  if (kids.isNotEmpty) {
                    _childCategoriesBySub["$name::$sName"] = kids;
                  }
                }
              }
            }
            if (subs.isNotEmpty) {
              _subCategoriesByCat[name] = subs;
            }
          }
        }
      }
      if (fetched.isNotEmpty && mounted) {
        setState(() {
          for (var c in fetched) {
            if (!_quickCategories.contains(c)) {
              _quickCategories.add(c);
            }
          }
        });
      }
    } catch (e) {
      debugPrint("Error loading categories: $e");
    }
  }

  // Dialog for Merchant to add new Custom Category with Image Upload
  void _openAddCustomCategoryDialog() {
    final catNameController = TextEditingController();
    final catUrlController = TextEditingController();
    Uint8List? categoryImageBytes;
    bool isSubmittingCat = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.category_rounded, color: primaryBlue, size: 22),
                SizedBox(width: 8),
                Text(
                  'Add New Category',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Category Name:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textDark),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: catNameController,
                    decoration: InputDecoration(
                      hintText: 'e.g. Nellore Sweets, Millets, Festive',
                      hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 14),

                  const Text(
                    'Category Image:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textDark),
                  ),
                  const SizedBox(height: 6),

                  if (categoryImageBytes != null)
                    Stack(
                      children: [
                        Container(
                          width: double.infinity,
                          height: 120,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                            image: DecorationImage(
                              image: MemoryImage(categoryImageBytes!),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: InkWell(
                            onTap: () {
                              setDialogState(() {
                                categoryImageBytes = null;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, color: Colors.white, size: 16),
                            ),
                          ),
                        ),
                      ],
                    )
                  else ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () async {
                              final xFile = await _picker.pickImage(
                                source: ImageSource.gallery,
                                maxWidth: 250,
                                maxHeight: 250,
                                imageQuality: 55,
                              );
                              if (xFile != null) {
                                final bytes = await xFile.readAsBytes();
                                setDialogState(() {
                                  categoryImageBytes = bytes;
                                });
                              }
                            },
                            icon: const Icon(Icons.photo_library_outlined, size: 16),
                            label: const Text('Gallery', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () async {
                              final xFile = await _picker.pickImage(
                                source: ImageSource.camera,
                                maxWidth: 250,
                                maxHeight: 250,
                                imageQuality: 55,
                              );
                              if (xFile != null) {
                                final bytes = await xFile.readAsBytes();
                                setDialogState(() {
                                  categoryImageBytes = bytes;
                                });
                              }
                            },
                            icon: const Icon(Icons.camera_alt_outlined, size: 16),
                            label: const Text('Camera', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: catUrlController,
                      decoration: InputDecoration(
                        hintText: 'Or paste image URL (https://...)',
                        hintStyle: const TextStyle(fontSize: 11, color: Colors.grey),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Color(0xFFB45309)),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Category will be submitted to Admin for approval and selected immediately.',
                            style: TextStyle(fontSize: 10.5, color: Color(0xFF92400E)),
                          ),
                        ),
                      ],
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
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: isSubmittingCat
                    ? null
                    : () async {
                        final String catName = catNameController.text.trim();
                        if (catName.isEmpty) {
                          _showMessage('Please enter category name');
                          return;
                        }

                        setDialogState(() => isSubmittingCat = true);

                        try {
                          final user = FirebaseAuth.instance.currentUser;
                          String imageString = '';
                          final newCatRef = FirebaseFirestore.instance.collection('categories').doc();
                          if (categoryImageBytes != null) {
                            Uint8List cBytes = categoryImageBytes!;
                            if (cBytes.lengthInBytes > 80000) {
                              cBytes = await _compressImage(cBytes, targetWidth: 200);
                            }
                            imageString = 'data:image/jpeg;base64,${base64Encode(cBytes)}';
                          } else if (catUrlController.text.trim().isNotEmpty) {
                            imageString = catUrlController.text.trim();
                          }

                          // Check if admin auto-accept is enabled
                          bool autoAccept = false;
                          try {
                            final adminSettings = await FirebaseFirestore.instance
                                .collection('admin_settings')
                                .doc('catalog_rules')
                                .get();
                            if (adminSettings.exists) {
                              autoAccept = adminSettings.data()?['autoAcceptCategories'] == true;
                            }
                          } catch (_) {}

                          await newCatRef.set({
                            'id': newCatRef.id,
                            'categoryId': newCatRef.id,
                            'name': catName,
                            'categoryName': catName,
                            'imageUrl': imageString,
                            'image': imageString,
                            'status': autoAccept ? 'approved' : 'pending',
                            'approvalStatus': autoAccept ? 'approved' : 'pending',
                            'merchantId': user?.uid ?? 'unknown',
                            'createdAt': FieldValue.serverTimestamp(),
                            'source': 'merchant_app',
                          });

                          if (mounted) {
                            setState(() {
                              if (!_quickCategories.contains(catName)) {
                                _quickCategories.insert(0, catName);
                              }
                              _categoryController.text = catName;
                            });
                            Navigator.pop(ctx);
                            _showMessage(
                              autoAccept
                                  ? 'Category "$catName" auto-approved & selected!'
                                  : 'Category "$catName" submitted for Admin approval & selected!',
                            );
                          }
                        } catch (e) {
                          setDialogState(() => isSubmittingCat = false);
                          _showMessage('Error submitting category: $e');
                        }
                      },
                child: isSubmittingCat
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('Submit Category', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _fetchAllStoreProducts() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection('products')
          .where('merchantId', isEqualTo: user.uid)
          .get();
      if (mounted) {
        setState(() {
          _allProducts = snap.docs;
        });
      }
    } catch (_) {
    }
  }

  // Multi-image picker for products & combo bundles
  Future<Uint8List> _compressImage(Uint8List rawBytes, {int targetWidth = 350}) async {
    try {
      final ui.Codec codec = await ui.instantiateImageCodec(
        rawBytes,
        targetWidth: targetWidth,
      );
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ByteData? byteData = await frameInfo.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData != null) {
        return byteData.buffer.asUint8List();
      }
    } catch (e) {
      debugPrint('Image compression error: $e');
    }
    return rawBytes;
  }

  Future<void> _pickImage(ImageSource source, {bool isMultipleCombo = false}) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        imageQuality: 60,
        maxWidth: 400,
        maxHeight: 400,
      );
      if (file == null) return;
      final Uint8List rawBytes = await file.readAsBytes();
      // Auto-compress down to 350px width for fast cloud sync and 0 Firestore byte-overflow
      final Uint8List bytes = await _compressImage(rawBytes, targetWidth: 350);

      setState(() {
        if (isMultipleCombo) {
          if (_comboMultipleImageBytesList.length < 3) {
            _comboMultipleImageBytesList.add(bytes);
            if (_primaryImageBytes == null) {
              _primaryImageBytes = bytes;
            }
          } else {
            _showMessage('Maximum 3 images allowed for bundle.');
          }
        } else {
          _primaryImageBytes = bytes;
          _networkImageUrl = '';
          if (_comboMultipleImageBytesList.isEmpty) {
            _comboMultipleImageBytesList.add(bytes);
          }
        }
      });
    } catch (e) {
      _showMessage('Failed to pick image: $e');
    }
  }

  void _autoDetectCategoryFromName() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    if (_categoryController.text.isEmpty ||
        _categoryController.text == 'Grocery / Supermarket') {
      final matchedCat = _suggestCategory(name);
      if (matchedCat.isNotEmpty && matchedCat != _categoryController.text) {
        setState(() {
          _categoryController.text = matchedCat;
        });
      }
    }
  }

  String _suggestCategory(String name) {
    try {
      final dynamic s = MasterCatalogService.instance;
      final res = s.suggestCategory(name);
      if (res is String && res.isNotEmpty) return res;
    } catch (_) {}

    final lower = name.toLowerCase();
    if (lower.contains('milk') || lower.contains('curd') || lower.contains('paneer') || lower.contains('butter') || lower.contains('cheese') || lower.contains('egg')) {
      return 'Dairy, Bread & Eggs';
    } else if (lower.contains('tomato') || lower.contains('onion') || lower.contains('potato') || lower.contains('apple') || lower.contains('banana') || lower.contains('fruit') || lower.contains('veg')) {
      return 'Vegetables & Fruits';
    } else if (lower.contains('atta') || lower.contains('rice') || lower.contains('dal') || lower.contains('wheat') || lower.contains('flour')) {
      return 'Atta, Rice & Dals';
    } else if (lower.contains('oil') || lower.contains('ghee')) {
      return 'Oils & Ghee';
    } else if (lower.contains('biscuit') || lower.contains('chips') || lower.contains('snack') || lower.contains('cookie') || lower.contains('namkeen')) {
      return 'Snacks & Munchies';
    } else if (lower.contains('coke') || lower.contains('pepsi') || lower.contains('juice') || lower.contains('drink') || lower.contains('tea') || lower.contains('coffee')) {
      return 'Beverages & Drinks';
    } else if (lower.contains('maggi') || lower.contains('noodle') || lower.contains('pasta') || lower.contains('instant')) {
      return 'Instant & Frozen Food';
    } else if (lower.contains('combo') || lower.contains('saver') || lower.contains('bundle') || lower.contains('deal')) {
      return 'Combo Offers & Deals';
    }
    return 'Grocery / Supermarket';
  }

  void _loadProductForEditing(String docId, Map<String, dynamic> data) {
    setState(() {
      _selectedExistingDocId = docId;
      _nameController.text = (data['name'] ?? data['title'] ?? '').toString();
      _brandController.text = (data['brand'] ?? '').toString();
      _categoryController.text =
          (data['category'] ?? 'Grocery / Supermarket').toString();
      _subCategoryController.text = (data['subCategory'] ?? '').toString();
      _childCategoryController.text = (data['childCategory'] ?? '').toString();
      _descriptionController.text = (data['description'] ?? '').toString();
      _comboItemsController.text = (data['comboItems'] ?? '').toString();
      _barcodeController.text = (data['barcode'] ?? '').toString();
      _isComboOffer = data['isCombo'] == true || data['isComboOffer'] == true;
      _networkImageUrl =
          (data['imageUrl'] ?? data['image'] ?? data['imageBase64'] ?? '')
              .toString();
      _primaryImageBytes = null;
      _comboMultipleImageBytesList.clear();

      // Load multiple combo images if stored
      if (data['images'] is List) {
        // Handled via URLs
      }

      final dynamic rawVariants = data['variants'];
      if (rawVariants is List && rawVariants.isNotEmpty) {
        _variants = rawVariants.map((v) {
          final map = v as Map<String, dynamic>;
          final u = (map['unit'] ?? '1 kg').toString();
          final mp = (map['marketPrice'] ?? '').toString();
          final p = (map['price'] ?? '').toString();
          final s = (map['stock'] ?? '0').toString();
          return ProductVariantItem(
            unit: u,
            marketPrice: mp,
            price: p,
            stock: s,
            presentStock: int.tryParse(s) ?? 0,
          );
        }).toList();
      } else {
        final p = (data['price'] ?? '').toString();
        final mp = (data['marketPrice'] ?? '').toString();
        final u = (data['unit'] ?? '1 kg').toString();
        final s = (data['stock'] ?? '0').toString();
        _variants = [
          ProductVariantItem(
            unit: u,
            marketPrice: mp,
            price: p,
            stock: s,
            presentStock: int.tryParse(s) ?? 0,
          )
        ];
      }
    });
  }

  void _applyMasterProduct(MasterProductItem master) {
    setState(() {
      final dynamic m = master;
      final String u = (m.unit ?? m.defaultUnit ?? '1 kg').toString();
      final double pr = (m.price ?? m.sellingPrice ?? m.suggestedSellingPrice ?? m.mrp ?? 0).toDouble();

      _nameController.text = master.name;
      _brandController.text = master.brand;
      _categoryController.text = master.category;
      _barcodeController.text = master.barcode;
      _networkImageUrl = master.imageUrl;
      _primaryImageBytes = null;

      _variants = [
        ProductVariantItem(
          unit: u,
          marketPrice: master.mrp.toStringAsFixed(0),
          price: pr > 0 ? pr.toStringAsFixed(0) : master.mrp.toStringAsFixed(0),
          stock: '100',
          presentStock: 0,
        )
      ];

      _showMasterSuggestions = false;
      _masterSearchController.clear();
    });

    _showMessage(
        'Selected ${master.name}! Verified barcode & HD image attached.');
  }

  void _openBarcodeScannerModal() {
    showDialog(
      context: context,
      builder: (_) => BarcodeScannerSimulatorDialog(
        onBarcodeScanned: (barcode) {
          _handleScannedBarcode(barcode);
        },
        onScanned: (barcode) {
          _handleScannedBarcode(barcode);
        },
      ),
    );
  }

  void _handleScannedBarcode(String barcode) {
    setState(() {
      _barcodeController.text = barcode;
    });

    try {
      final dynamic service = MasterCatalogService.instance;
      final matched = service.findByBarcode(barcode);
      if (matched != null) {
        _applyMasterProduct(matched);
      } else {
        _showMessage('Barcode scanned: $barcode (No master match found, enter details)');
      }
    } catch (_) {
      _showMessage('Barcode scanned: $barcode');
    }
  }

  Future<void> _saveProduct() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showMessage('Please login as a merchant first.');
      return;
    }

    if (!_formKey.currentState!.validate()) {
      _showMessage('Please fill all required product details.');
      return;
    }

    if (_nameController.text.trim().isEmpty) {
      _showMessage('Please enter product / combo offer title.');
      return;
    }

    for (int i = 0; i < _variants.length; i++) {
      final v = _variants[i];
      if (v.flash2martPriceVal <= 0) {
        _showMessage('Variant #${i + 1} selling price must be greater than 0.');
        return;
      }
      if (v.marketPriceVal > 0 && v.flash2martPriceVal > v.marketPriceVal) {
        _showMessage(
          'Selling price (₹${v.flash2martPriceVal.toInt()}) cannot exceed MRP (₹${v.marketPriceVal.toInt()}) in Variant #${i + 1}.',
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      // 2. Fetch merchant store info
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
        storeLat = rawStoreLoc.latitude;
        storeLng = rawStoreLoc.longitude;
      }

      // 3. Resolve images with strict size-reduction & compression
      String primaryImageString = _networkImageUrl;
      if (_primaryImageBytes != null) {
        Uint8List compressed = _primaryImageBytes!;
        if (compressed.lengthInBytes > 120000) {
          compressed = await _compressImage(compressed, targetWidth: 260);
        }
        primaryImageString = 'data:image/jpeg;base64,${base64Encode(compressed)}';
      }

      final List<String> multipleImagesList = [];
      if (_isComboOffer && _comboMultipleImageBytesList.isNotEmpty) {
        for (final b in _comboMultipleImageBytesList.take(3)) {
          Uint8List cBytes = b;
          if (cBytes.lengthInBytes > 90000) {
            cBytes = await _compressImage(cBytes, targetWidth: 200);
          }
          multipleImagesList.add('data:image/jpeg;base64,${base64Encode(cBytes)}');
        }
      }

      // 4. Variant Calculations
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
      final String barcode = _barcodeController.text.trim();

      // All merchant-added products strictly require Admin Approval before appearing in Customer App
      final bool isApproved = widget.editData != null &&
          widget.editData?['isApproved'] == true &&
          widget.editData?['status'] == 'approved';
      final String approvalStatus = isApproved ? 'approved' : 'pending_approval';

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
        if (_subCategoryController.text.trim().isNotEmpty) 'subCategory': _subCategoryController.text.trim(),
        if (_childCategoryController.text.trim().isNotEmpty) 'childCategory': _childCategoryController.text.trim(),
        'description': _descriptionController.text.trim(),
        'barcode': barcode,
        'isApproved': isApproved,
        'isApprovedByAdmin': isApproved,
        'isMasterVerified': false,
        'verificationStatus': isApproved ? 'Approved' : 'Pending Admin Approval',
        'approvalStatus': approvalStatus,
        'status': approvalStatus,
        'adminApprovalStatus': approvalStatus,
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
            ? '$primaryDiscount% OFF COMBO DEAL'
            : '$primaryDiscount% OFF',
        if (primaryImageString.isNotEmpty) 'imageBase64': primaryImageString,
        if (primaryImageString.isNotEmpty) 'imageUrl': primaryImageString,
        if (multipleImagesList.isNotEmpty) 'images': multipleImagesList,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (_selectedExistingDocId != null) {
        await FirebaseFirestore.instance
            .collection('products')
            .doc(_selectedExistingDocId)
            .set(docData, SetOptions(merge: true));
        _showMessage('Product/Combo updated & saved successfully!');
      } else {
        final newDocRef =
            FirebaseFirestore.instance.collection('products').doc();
        docData['productId'] = newDocRef.id;
        docData['id'] = newDocRef.id;
        docData['createdAt'] = FieldValue.serverTimestamp();
        await newDocRef.set(docData);
        _showMessage('🎉 Product submitted! It will appear in Customer App once approved by Admin.');
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

  void _resetFormForNewProduct() {
    setState(() {
      _selectedExistingDocId = null;
      _nameController.clear();
      _brandController.clear();
      _categoryController.text = 'Grocery / Supermarket';
      _subCategoryController.clear();
      _childCategoryController.clear();
      _descriptionController.clear();
      _comboItemsController.clear();
      _barcodeController.clear();
      _masterSearchController.clear();
      _primaryImageBytes = null;
      _comboMultipleImageBytesList.clear();
      _networkImageUrl = '';
      _isComboOffer = false;
      _variants = [
        ProductVariantItem(
            unit: '1 kg',
            marketPrice: '',
            price: '',
            stock: '100',
            presentStock: 0),
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgGrey,
      appBar: AppBar(
        title: Text(
          widget.editDocId != null ? 'Edit Product / Deal' : 'Add Product & Combos',
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 17,
            letterSpacing: 0.3,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: textDark,
        elevation: 0.5,
        actions: [
          IconButton(
            tooltip: 'Barcode Scanner',
            onPressed: _openBarcodeScannerModal,
            icon: const Icon(Icons.qr_code_scanner_rounded, color: primaryBlue),
          ),
          IconButton(
            tooltip: 'Reset Form',
            onPressed: _resetFormForNewProduct,
            icon: const Icon(Icons.refresh_rounded, color: Colors.grey),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: primaryBlue),
            )
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                children: [
                  // 1. FLASH2MART MASTER CATALOG & BARCODE SCANNER BANNER
                  _buildMasterCatalogHeader(),
                  const SizedBox(height: 14),

                  // 2. EXISTING PRODUCTS QUICK SELECT CHIPS
                  if (_allProducts.isNotEmpty) ...[
                    _buildExistingProductsSelector(),
                    const SizedBox(height: 14),
                  ],

                  // 3. MAIN PRODUCT / COMBO INFORMATION CARD
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cardBorder),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0x06000000),
                            blurRadius: 8,
                            offset: Offset(0, 2)),
                      ],
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.inventory_2_outlined,
                                color: primaryBlue, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Product & Category Details',
                              style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.bold,
                                  color: textDark),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Title / Name Field
                        _buildTextField(
                          controller: _nameController,
                          label: _isComboOffer ? 'Combo Offer Title *' : 'Product Name *',
                          hint: _isComboOffer
                              ? 'e.g. Atta 5kg + Fortune Oil 1L Super Saver Combo'
                              : 'e.g. Aashirvaad Superior MP Shuddh Chakki Atta',
                          icon: Icons.title_rounded,
                          focusNode: _nameFocusNode,
                          validator: (val) => val == null || val.trim().isEmpty
                              ? 'Please enter product or combo name'
                              : null,
                        ),
                        const SizedBox(height: 10),

                        // Brand Field with Quick Brand Chips
                        _buildTextField(
                          controller: _brandController,
                          label: 'Brand Name',
                          hint: 'e.g. Amul, Aashirvaad, Tata, Flash2Mart Combo',
                          icon: Icons.verified_outlined,
                        ),
                        const SizedBox(height: 8),

                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _quickBrands.map((brand) {
                            return InkWell(
                              onTap: () {
                                setState(() {
                                  _brandController.text = brand;
                                });
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEEF2FF),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: const Color(0xFFC7D2FE)),
                                ),
                                child: Text(
                                  brand,
                                  style: const TextStyle(
                                    color: primaryPurple,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),

                        // Category Header + Add Category Action
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Select Category (Flash2Mart Catalog):',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: textDark),
                            ),
                            InkWell(
                              onTap: _openAddCustomCategoryDialog,
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEEF2FF),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: const Color(0xFFC7D2FE)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.add_circle_outline,
                                        size: 13, color: primaryPurple),
                                    SizedBox(width: 4),
                                    Text(
                                      '+ Add Category',
                                      style: TextStyle(
                                        color: primaryPurple,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _quickCategories.map((cat) {
                            final isSelected =
                                _categoryController.text.trim() == cat;
                            return ChoiceChip(
                              label: Text(cat),
                              labelStyle: TextStyle(
                                color: isSelected ? Colors.white : textDark,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                fontSize: 11.5,
                              ),
                              selected: isSelected,
                              selectedColor: primaryBlue,
                              backgroundColor: const Color(0xFFF1F5F9),
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() {
                                    _categoryController.text = cat;
                                    _subCategoryController.clear();
      _childCategoryController.clear();
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
                          label: 'Category Name',
                          hint: 'Category',
                          icon: Icons.category_outlined,
                        ),
                        const SizedBox(height: 10),
                        if ((_subCategoriesByCat[_categoryController.text.trim()] ?? const <String>[]).isNotEmpty) ...[
                          const Text(
                            'Select Sub-Category:',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textDark),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: (_subCategoriesByCat[_categoryController.text.trim()] ?? const <String>[]).map((sub) {
                              final isSubSel = _subCategoryController.text.trim() == sub;
                              return ChoiceChip(
                                label: Text(sub),
                                labelStyle: TextStyle(
                                  color: isSubSel ? Colors.white : textDark,
                                  fontWeight: isSubSel ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 11,
                                ),
                                selected: isSubSel,
                                selectedColor: primaryPurple,
                                backgroundColor: const Color(0xFFF1F5F9),
                                onSelected: (sel) {
                                  setState(() {
                                    _subCategoryController.text = sel ? sub : '';
                                    _childCategoryController.clear();
                                  });
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 8),
                        ],
                        _buildTextField(
                          controller: _subCategoryController,
                          label: 'Sub-Category (Optional)',
                          hint: 'e.g. Fresh Fruits, Leafy Greens',
                          icon: Icons.subdirectory_arrow_right_rounded,
                        ),
                        const SizedBox(height: 10),
                        if ((_childCategoriesBySub["${_categoryController.text.trim()}::${_subCategoryController.text.trim()}"] ?? const <String>[]).isNotEmpty) ...[
                          const Text(
                            'Select Child Sub-Item (e.g. Mango, Apple):',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textDark),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: (_childCategoriesBySub["${_categoryController.text.trim()}::${_subCategoryController.text.trim()}"] ?? const <String>[]).map((kid) {
                              final isKidSel = _childCategoryController.text.trim() == kid;
                              return ChoiceChip(
                                label: Text(kid),
                                labelStyle: TextStyle(
                                  color: isKidSel ? Colors.white : textDark,
                                  fontWeight: isKidSel ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 11,
                                ),
                                selected: isKidSel,
                                selectedColor: accentGreen,
                                backgroundColor: const Color(0xFFF1F5F9),
                                onSelected: (sel) {
                                  setState(() {
                                    _childCategoryController.text = sel ? kid : '';
                                  });
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 8),
                        ],
                        _buildTextField(
                          controller: _childCategoryController,
                          label: 'Child Sub-Item (Optional)',
                          hint: 'e.g. Mango, Apple, Banana',
                          icon: Icons.local_florist_outlined,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 4. COMBO OFFERS & SUPER SAVERS BUILDER CARD
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: _isComboOffer
                              ? const Color(0xFFF43F5E)
                              : cardBorder,
                          width: _isComboOffer ? 1.5 : 1),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0x06000000),
                            blurRadius: 8,
                            offset: Offset(0, 2)),
                      ],
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.stars_rounded,
                                    color: Color(0xFFF43F5E), size: 22),
                                SizedBox(width: 8),
                                Text(
                                  'Combo Offer & Super Deal',
                                  style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.bold,
                                      color: textDark),
                                ),
                              ],
                            ),
                            Switch(
                              value: _isComboOffer,
                              activeThumbColor: const Color(0xFFF43F5E),
                              onChanged: (val) {
                                setState(() {
                                  _isComboOffer = val;
                                  if (val &&
                                      _categoryController.text ==
                                          'Grocery / Supermarket') {
                                    _categoryController.text =
                                        'Combo Offers & Deals';
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                        if (_isComboOffer) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF1F2),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: const Color(0xFFFECDD3)),
                            ),
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '🌟 Combo Deal Features Activated:',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFBE123C)),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  '• Add multiple items list below (e.g. Rice 5kg + Oil 1L)\n• Upload more than 1 image below (Images scroll in Customer Bottom Bar!)\n• Highlighted with special Super Saver badge in customer app',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF9F1239)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildTextField(
                            controller: _comboItemsController,
                            label: 'Items Included in this Combo *',
                            hint: 'e.g. 1x Aashirvaad Atta 5kg + 1x Fortune Sunlite 1L + 1x Tata Salt 1kg',
                            icon: Icons.checklist_rounded,
                            maxLines: 2,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 5. PRODUCT & COMBO MULTI-IMAGES UPLOAD CARD
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cardBorder),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0x06000000),
                            blurRadius: 8,
                            offset: Offset(0, 2)),
                      ],
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.add_photo_alternate_rounded,
                                    color: primaryPurple, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  _isComboOffer
                                      ? 'Combo Images (More than 1 Image)'
                                      : 'Product Images',
                                  style: const TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.bold,
                                      color: textDark),
                                ),
                              ],
                            ),
                            Text(
                              '${_comboMultipleImageBytesList.length} / 5',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: primaryPurple,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _isComboOffer
                              ? 'Upload 2 to 5 images showing the bundle items. These images scroll dynamically in the Customer App bottom bar!'
                              : 'Upload primary and additional pack images.',
                          style: TextStyle(
                              fontSize: 11.5, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 12),

                        // Image Thumbnails Grid / Row
                        if (_comboMultipleImageBytesList.isNotEmpty) ...[
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ..._comboMultipleImageBytesList.asMap().entries.map((entry) {
                                final idx = entry.key;
                                final b = entry.value;
                                return Stack(
                                  children: [
                                    Container(
                                      width: 76,
                                      height: 76,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: cardBorder),
                                        image: DecorationImage(
                                          image: MemoryImage(b),
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                    if (idx == 0)
                                      Positioned(
                                        bottom: 0,
                                        left: 0,
                                        right: 0,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(vertical: 2),
                                          decoration: const BoxDecoration(
                                            color: primaryBlue,
                                            borderRadius: BorderRadius.vertical(bottom: Radius.circular(10)),
                                          ),
                                          child: const Text(
                                            'MAIN',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 8.5,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                      ),
                                    Positioned(
                                      top: 2,
                                      right: 2,
                                      child: InkWell(
                                        onTap: () {
                                          setState(() {
                                            _comboMultipleImageBytesList.removeAt(idx);
                                            if (_comboMultipleImageBytesList.isNotEmpty) {
                                              _primaryImageBytes = _comboMultipleImageBytesList.first;
                                            } else {
                                              _primaryImageBytes = null;
                                            }
                                          });
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: const BoxDecoration(
                                            color: Colors.black54,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.close, color: Colors.white, size: 14),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }),

                              // Add more button
                              if (_comboMultipleImageBytesList.length < 5)
                                InkWell(
                                  onTap: () => _pickImage(ImageSource.gallery, isMultipleCombo: true),
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    width: 76,
                                    height: 76,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFFCBD5E1), style: BorderStyle.solid),
                                    ),
                                    child: const Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.add_photo_alternate_rounded, color: primaryPurple, size: 24),
                                        SizedBox(height: 2),
                                        Text(
                                          '+ Add',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: primaryPurple,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ] else ...[
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    side: const BorderSide(color: primaryPurple),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onPressed: () => _pickImage(ImageSource.gallery, isMultipleCombo: true),
                                  icon: const Icon(Icons.photo_library_rounded, color: primaryPurple, size: 18),
                                  label: const Text(
                                    'Upload Gallery Images',
                                    style: TextStyle(color: primaryPurple, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    side: const BorderSide(color: primaryBlue),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onPressed: () => _pickImage(ImageSource.camera, isMultipleCombo: true),
                                  icon: const Icon(Icons.camera_alt_rounded, color: primaryBlue, size: 18),
                                  label: const Text(
                                    'Take Camera Photo',
                                    style: TextStyle(color: primaryBlue, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 6. PRICE, MRP & DISCOUNT VARIANT BUILDER
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cardBorder),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0x06000000),
                            blurRadius: 8,
                            offset: Offset(0, 2)),
                      ],
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.sell_outlined,
                                    color: accentGreen, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  _isComboOffer ? 'Combo Pricing & Stock' : 'Pricings & Pack Sizes',
                                  style: const TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.bold,
                                      color: textDark),
                                ),
                              ],
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFEEF2FF),
                                foregroundColor: primaryPurple,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () {
                                setState(() {
                                  _variants.add(ProductVariantItem(
                                      unit: 'Pack of 1',
                                      marketPrice: '',
                                      price: '',
                                      stock: '50'));
                                });
                              },
                              icon: const Icon(Icons.add, size: 14),
                              label: const Text(
                                '+ Add Size',
                                style: TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _variants.length,
                          itemBuilder: (context, idx) => _buildVariantRow(idx),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 7. DESCRIPTION CARD
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cardBorder),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.description_outlined,
                                color: textDark, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Product / Combo Description',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: textDark),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _buildTextField(
                          controller: _descriptionController,
                          label: 'Short Description',
                          hint: 'Describe freshness, quality, expiration or contents...',
                          icon: Icons.notes_rounded,
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 8. SUBMIT ACTION BUTTON
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isComboOffer ? const Color(0xFFE11D48) : accentGreen,
                        foregroundColor: Colors.white,
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _saveProduct,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(_isComboOffer ? Icons.stars_rounded : Icons.check_circle_rounded, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            _isComboOffer ? 'SAVE & PUBLISH COMBO DEAL' : 'SAVE & PUBLISH PRODUCT',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildMasterCatalogHeader() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.auto_awesome, color: Color(0xFF38BDF8), size: 18),
                  SizedBox(width: 6),
                  Text(
                    'Flash2Mart Master Catalog',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),

              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _openBarcodeScannerModal,
                icon: const Icon(Icons.qr_code_scanner_rounded, size: 14),
                label: const Text(
                  'SCAN BARCODE',
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          TextField(
            controller: _masterSearchController,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            onChanged: (val) {
              setState(() {
                if (val.trim().isNotEmpty) {
                  _searchedMasterItems =
                      MasterCatalogService.instance.searchMasterCatalog(val);
                  _showMasterSuggestions = true;
                } else {
                  _showMasterSuggestions = false;
                }
              });
            },
            decoration: InputDecoration(
              hintText: 'Search 5,000+ Master FMCG items (e.g. Amul, Maggi, Atta)...',
              hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11.5),
              prefixIcon: const Icon(Icons.search_rounded,
                  color: Color(0xFF38BDF8), size: 18),
              filled: true,
              fillColor: const Color(0xFF1E293B),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF334155)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF334155)),
              ),
            ),
          ),

          if (_showMasterSuggestions && _searchedMasterItems.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _searchedMasterItems.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: Color(0xFF334155)),
                itemBuilder: (context, idx) {
                  final item = _searchedMasterItems[idx];
                  return ListTile(
                    dense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    title: Text(
                      item.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5),
                    ),
                    subtitle: Text(
                      (() { final dynamic dyn = item; final String u = (dyn.unit ?? dyn.defaultUnit ?? '1 kg').toString(); return '${item.brand} • $u • MRP: ₹${item.mrp.toInt()}'; })(),
                      style: const TextStyle(
                          color: Color(0xFF94A3B8), fontSize: 11),
                    ),
                    trailing: const Icon(Icons.add_circle_outline,
                        color: Color(0xFF38BDF8), size: 18),
                    onTap: () => _applyMasterProduct(item),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExistingProductsSelector() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Your Store Products (${_allProducts.length})',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold, color: textDark),
              ),
              Text(
                _topStockFilter,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: primaryBlue),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 38,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _allProducts.length,
              itemBuilder: (context, idx) {
                final doc = _allProducts[idx];
                final data = doc.data() as Map<String, dynamic>;
                final String pName =
                    (data['name'] ?? data['title'] ?? 'Product').toString();
                final bool isSelected = _selectedExistingDocId == doc.id;

                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(pName),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : textDark,
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    ),
                    selected: isSelected,
                    selectedColor: primaryPurple,
                    backgroundColor: const Color(0xFFF1F5F9),
                    onSelected: (selected) {
                      if (selected) {
                        _loadProductForEditing(doc.id, data);
                      } else {
                        _resetFormForNewProduct();
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

  Widget _buildVariantRow(int idx) {
    final v = _variants[idx];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Pack / Size #${idx + 1}',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold, color: textDark),
              ),
              if (_variants.length > 1)
                InkWell(
                  onTap: () {
                    setState(() {
                      v.dispose();
                      _variants.removeAt(idx);
                    });
                  },
                  child: const Icon(Icons.delete_outline,
                      size: 18, color: Colors.redAccent),
                ),
            ],
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                flex: 4,
                child: _buildTextField(
                  controller: v.unitController,
                  label: 'Pack / Size',
                  hint: 'e.g. 1 kg / Combo',
                  icon: Icons.scale_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: _buildTextField(
                  controller: v.marketPriceController,
                  label: 'Market MRP (₹)',
                  hint: 'MRP',
                  icon: Icons.currency_rupee,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: _buildTextField(
                  controller: v.priceController,
                  label: 'Deal Price (₹)*',
                  hint: 'Price',
                  icon: Icons.sell_rounded,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Real-Time Discount & Savings Badge
          if (v.discountPercentage > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF86EFAC)),
              ),
              child: Text(
                '💰 ${v.discountPercentage}% OFF Deal (Customer Saves ₹${(v.marketPriceVal - v.flash2martPriceVal).toInt()})',
                style: const TextStyle(
                  color: Color(0xFF15803D),
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    TextInputType? keyboardType,
    FocusNode? focusNode,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      focusNode: focusNode,
      validator: validator,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 13, color: textDark),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 18, color: const Color(0xFF64748B)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: primaryBlue, width: 1.5),
        ),
      ),
    );
  }
}
