import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ProductCardWidget extends StatelessWidget {
  final String docId;
  final QueryDocumentSnapshot rawDoc;
  final String name;
  final String brand;
  final dynamic price;
  final String unit;
  final dynamic stock;
  final List<dynamic> variants;
  final String category;
  final String imageBase64;
  final String imageUrl;
  final Function(String docId, Map<String, dynamic> data) onEdit;
  final Function(String docId, String name) onDelete;

  const ProductCardWidget({
    super.key,
    required this.docId,
    required this.rawDoc,
    required this.name,
    required this.brand,
    required this.price,
    required this.unit,
    required this.stock,
    required this.variants,
    required this.category,
    required this.imageBase64,
    required this.imageUrl,
    required this.onEdit,
    required this.onDelete,
  });

  static const Color cardGreenBorder = Color(0xFF16A34A);
  static const Color productNameGold = Color(0xFFFDE047);

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> rawData = rawDoc.data() is Map<String, dynamic> ? rawDoc.data() as Map<String, dynamic> : {};
    final bool isCombo = rawData['isCombo'] == true || category.toLowerCase().contains('combo');
    final String discountTag = (rawData['discountTag'] ?? '').toString().trim();
    final int stockQty = stock is int ? stock : int.tryParse('$stock') ?? 0;
    final bool isOutOfStock = stockQty <= 0;
    final bool isLowStock = stockQty > 0 && stockQty < 100;

    Widget imageWidget;
    if (imageBase64.isNotEmpty) {
      try {
        imageWidget = Image.memory(
          base64Decode(imageBase64),
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            color: const Color(0xFFE2E8F0),
            child: const Icon(Icons.broken_image, size: 28, color: Colors.grey),
          ),
        );
      } catch (_) {
        imageWidget = Container(
          color: const Color(0xFFE2E8F0),
          child: const Icon(Icons.broken_image, size: 28, color: Colors.grey),
        );
      }
    } else if (imageUrl.isNotEmpty) {
      imageWidget = Image.network(
        imageUrl,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          color: const Color(0xFFE2E8F0),
          child: const Icon(Icons.broken_image, size: 28, color: Colors.grey),
        ),
      );
    } else {
      imageWidget = Container(
        width: double.infinity,
        height: double.infinity,
        color: const Color(0xFFF1F5F9),
        child: const Center(
          child: Icon(Icons.storefront_rounded, color: Colors.grey, size: 36),
        ),
      );
    }

    Color stockBadgeBg = const Color(0xFF15803D);
    Color stockBadgeText = Colors.white;
    String stockText = 'Stock: $stockQty';

    if (isOutOfStock) {
      stockBadgeBg = const Color(0xFFDC2626);
      stockBadgeText = Colors.white;
      stockText = 'Out of Stock';
    } else if (isLowStock) {
      stockBadgeBg = const Color(0xFFD97706);
      stockBadgeText = Colors.white;
      stockText = 'Low: $stockQty left';
    }

    return GestureDetector(
      onTap: () => onEdit(docId, rawDoc.data() as Map<String, dynamic>),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: cardGreenBorder,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(15),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12.5),
          child: Stack(
            children: [
              Positioned.fill(
                child: imageWidget,
              ),
              Positioned(
                top: 6,
                left: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isCombo || discountTag.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 3),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE11D48), Color(0xFFF97316)],
                          ),
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: const [
                            BoxShadow(color: Colors.black38, blurRadius: 3),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.stars_rounded, size: 10, color: Colors.white),
                            const SizedBox(width: 3),
                            Text(
                              isCombo ? '🎁 COMBO${discountTag.isNotEmpty ? ' • $discountTag' : ''}' : discountTag,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (brand.isNotEmpty || category.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(199),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white24, width: 0.6),
                        ),
                        child: Text(
                          brand.isNotEmpty ? brand : category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () => onEdit(docId, rawDoc.data() as Map<String, dynamic>),
                      child: Container(
                        padding: const EdgeInsets.all(4.5),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(191),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF60A5FA), width: 0.8),
                        ),
                        child: const Icon(
                          Icons.edit_rounded,
                          size: 13,
                          color: Color(0xFF60A5FA),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => onDelete(docId, name),
                      child: Container(
                        padding: const EdgeInsets.all(4.5),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(191),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.redAccent.withAlpha(204), width: 0.8),
                        ),
                        child: const Icon(
                          Icons.delete_outline_rounded,
                          size: 13,
                          color: Colors.redAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withAlpha(245),
                        Colors.black.withAlpha(217),
                        Colors.black.withAlpha(128),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.4, 0.8, 1.0],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          color: productNameGold,
                          shadows: [
                            Shadow(color: Colors.black, blurRadius: 4, offset: Offset(0, 1)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '₹$price',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14.5,
                              color: Color(0xFF4ADE80),
                              shadows: [
                                Shadow(color: Colors.black, blurRadius: 4),
                              ],
                            ),
                          ),
                          if (unit.isNotEmpty) ...[
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                '/ $unit',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFE2E8F0),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: stockBadgeBg,
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withAlpha(77), blurRadius: 2),
                          ],
                        ),
                        child: Text(
                          stockText,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: stockBadgeText,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}