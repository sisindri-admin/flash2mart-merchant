import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class FirestoreService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ==================== 1. PRODUCT METHODS ====================
  Future<void> addProduct({
    required String merchantId,
    required String name,
    required double price,
    required int stock,
    required String category,
    required String description,
  }) async {
    final docRef = _db.collection('products').doc();

    await docRef.set({
      'productId': docRef.id,
      'merchantId': merchantId,
      'name': name,
      'price': price,
      'stock': stock,
      'category': category,
      'description': description,
      'imageUrl': '',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot> getProducts(String merchantId) {
    return _db
        .collection('products')
        .where('merchantId', isEqualTo: merchantId)
        .snapshots();
  }

  // ==================== 2. MERCHANT PROFILE METHODS ====================
  Future<Map<String, dynamic>?> getMerchantProfile(String uid) async {
    final doc = await _db.collection('merchants').doc(uid).get();
    if (doc.exists) {
      return doc.data();
    }
    return null;
  }

  // ==================== 3. ORDER CREATION & FETCH METHODS ====================
  Future<void> addOrder({
    required String merchantId,
    required String customerName,
    required String customerPhone,
    required double totalAmount,
  }) async {
    final docRef = _db.collection('orders').doc();

    await docRef.set({
      'orderId': docRef.id,
      'merchantId': merchantId,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'totalAmount': totalAmount,
      'status': 'Pending',
      'orderStatus': 'Pending',
      'currentStatus': 'Pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot> getOrders(String merchantId) {
    return _db
        .collection('orders')
        .where('merchantId', isEqualTo: merchantId)
        .snapshots();
  }

  // ==================== 4. REAL-TIME TRACKING & STATUS METHODS ====================

  // 4 Apps (Customer, Merchant, Delivery, Admin) Instant Sync కోసం trackingHistory Array ఉపయోగించబడుతుంది
  static Future<void> updateOrderStatusWithTracking({
    required String orderId,
    required String newStatus,
    required String title,
    required String updatedBy,
  }) async {
    try {
      final orderRef = _db.collection('orders').doc(orderId);

      await orderRef.update({
        'orderStatus': newStatus,
        'status': newStatus,
        'currentStatus': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
        'trackingHistory': FieldValue.arrayUnion([
          {
            'status': newStatus,
            'title': title,
            'timestamp': DateTime.now().toIso8601String(),
            'updatedBy': updatedBy,
          }
        ]),
      });
    } catch (e) {
      debugPrint("Error updating order tracking: $e");
      rethrow;
    }
  }

  // A. Merchant Order Accept Logic (సపరేట్ కలెక్షన్ తీసేసి నేరుగా 'orders' కలెక్షన్ లోనే 'Preparing' గా మార్చడం)
  static Future<void> acceptOrder({
    required String orderId,
    Map<String, dynamic>? orderData,
  }) async {
    try {
      final orderRef = _db.collection('orders').doc(orderId);

      await orderRef.update({
        'status': 'Preparing',
        'orderStatus': 'Preparing',
        'currentStatus': 'Preparing',
        'acceptedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'trackingHistory': FieldValue.arrayUnion([
          {
            'status': 'Preparing',
            'title': 'Order Accepted & Preparing',
            'timestamp': DateTime.now().toIso8601String(),
            'updatedBy': 'Merchant',
          }
        ]),
      });
    } catch (e) {
      debugPrint("Error accepting order: $e");
      rethrow;
    }
  }

  // B. Merchant Order Reject Logic (సపరేట్ 'rejected_orders' కలెక్షన్ లేకుండా నేరుగా 'orders' లోనే 'Cancelled' చేయడం)
  static Future<void> rejectOrder({
    required String orderId,
    required String reason,
    Map<String, dynamic>? orderData,
  }) async {
    try {
      final orderRef = _db.collection('orders').doc(orderId);

      await orderRef.update({
        'status': 'Cancelled',
        'orderStatus': 'Cancelled',
        'currentStatus': 'Cancelled',
        'rejectReason': reason,
        'rejectedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'trackingHistory': FieldValue.arrayUnion([
          {
            'status': 'Cancelled',
            'title': 'Order Cancelled: $reason',
            'timestamp': DateTime.now().toIso8601String(),
            'updatedBy': 'Merchant',
          }
        ]),
      });
    } catch (e) {
      debugPrint("Error rejecting order: $e");
      rethrow;
    }
  }

  // C. Update Order Status to Packing Ready (Delivery Partner App కి వెంటనే పంపడానికి 'Ready_For_Pickup' గా మార్చడం)
  static Future<void> markOrderPackingReady(String orderId) async {
    try {
      final orderRef = _db.collection('orders').doc(orderId);

      await orderRef.update({
        'status': 'Ready_For_Pickup',
        'orderStatus': 'Ready_For_Pickup',
        'currentStatus': 'Ready_For_Pickup',
        'packingReadyAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'trackingHistory': FieldValue.arrayUnion([
          {
            'status': 'Ready_For_Pickup',
            'title': 'Packing Completed & Ready for Pickup',
            'timestamp': DateTime.now().toIso8601String(),
            'updatedBy': 'Merchant',
          }
        ]),
      });
    } catch (e) {
      debugPrint("Error marking packing ready: $e");
      rethrow;
    }
  }
}