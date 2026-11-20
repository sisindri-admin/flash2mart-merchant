class MasterProductItem {
  final String barcode;
  final String name;
  final String brand;
  final String category;
  final String unit;
  final double mrp;
  final double price;
  final String imageUrl;

  const MasterProductItem({
    required this.barcode,
    required this.name,
    required this.brand,
    required this.category,
    required this.unit,
    required this.mrp,
    required this.price,
    required this.imageUrl,
  });

  String get defaultUnit => unit;
  double get suggestedSellingPrice => price;
  double get sellingPrice => price;
}

class MasterCatalogService {
  MasterCatalogService._();
  static final MasterCatalogService instance = MasterCatalogService._();

  String suggestCategory(String name) {
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

  MasterProductItem? findByBarcode(String barcode) {
    final clean = barcode.trim();
    if (clean.isEmpty) return null;
    for (final item in masterFMCGProducts) {
      if (item.barcode == clean) return item;
    }
    return null;
  }

  List<MasterProductItem> searchMasterCatalog(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    return masterFMCGProducts.where((p) {
      return p.name.toLowerCase().contains(q) ||
          p.brand.toLowerCase().contains(q) ||
          p.barcode.contains(q) ||
          p.category.toLowerCase().contains(q);
    }).take(20).toList();
  }

  static const List<MasterProductItem> masterFMCGProducts = [
    MasterProductItem(
      barcode: '8901030383709',
      name: 'Aashirvaad Superior MP Shuddh Chakki Atta',
      brand: 'Aashirvaad',
      category: 'Atta, Rice & Dals',
      unit: '5 kg',
      mrp: 320.0,
      price: 275.0,
      imageUrl: 'https://images.unsplash.com/photo-1509440159596-0249088772ff?w=400',
    ),
    MasterProductItem(
      barcode: '8901262010054',
      name: 'Amul Taaza Homogenised Toned Milk',
      brand: 'Amul',
      category: 'Dairy, Bread & Eggs',
      unit: '1 L',
      mrp: 72.0,
      price: 68.0,
      imageUrl: 'https://images.unsplash.com/photo-1550583724-b2692b85b150?w=400',
    ),
    MasterProductItem(
      barcode: '8901063142274',
      name: 'Fortune Sunlite Refined Sunflower Oil',
      brand: 'Fortune',
      category: 'Oils & Ghee',
      unit: '1 L',
      mrp: 155.0,
      price: 138.0,
      imageUrl: 'https://images.unsplash.com/photo-1474979266404-7eaacbcd87c5?w=400',
    ),
    MasterProductItem(
      barcode: '8901058852355',
      name: 'Maggi 2-Minute Masala Instant Noodles',
      brand: 'Nestle',
      category: 'Instant & Frozen Food',
      unit: '280g (Pack of 4)',
      mrp: 56.0,
      price: 50.0,
      imageUrl: 'https://images.unsplash.com/photo-1612927601601-6638404737ce?w=400',
    ),
    MasterProductItem(
      barcode: '8901030775313',
      name: 'Tata Salt Vacuum Evaporated Iodised Salt',
      brand: 'Tata',
      category: 'Atta, Rice & Dals',
      unit: '1 kg',
      mrp: 28.0,
      price: 25.0,
      imageUrl: 'https://images.unsplash.com/photo-1518110925495-5fe2fda0442c?w=400',
    ),
  ];
}
