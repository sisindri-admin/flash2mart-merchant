import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Central Firestore Service for Flash2Mart Merchant App
/// Synchronized 100% with Customer App & Delivery Partner App
class FirestoreService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Generate secure 4-digit Pickup OTP for Delivery Partner Handover
  static String generatePickupOtp() {
    final rand = Random();
    return (1000 + rand.nextInt(9000)).toString();
  }

  /// Merchant Order Accept Logic
  static Future<void> acceptOrder({
    required String orderId,
    required Map<String, dynamic> orderData,
  }) async {
    try {
      final pickupOtp = (orderData['pickupOtp'] ?? generatePickupOtp()).toString();

      await _db.collection('order_accept_merchant').doc(orderId).set({
        ...orderData,
        'orderId': orderId,
        'pickupOtp': pickupOtp,
        'acceptedAt': FieldValue.serverTimestamp(),
        'status': 'Preparing',
        'orderStatus': 'Preparing',
      });

      await _db.collection('orders').doc(orderId).set({
        'status': 'Preparing',
        'orderStatus': 'Preparing',
        'currentStatus': 'Preparing',
        'pickupOtp': pickupOtp,
        'acceptedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'trackingHistory': FieldValue.arrayUnion([
          {
            'status': 'Preparing',
            'title': 'Store accepted order & packing started',
            'updatedBy': 'Merchant',
            'timestamp': DateTime.now().toIso8601String(),
          }
        ]),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Error accepting order: $e");
      rethrow;
    }
  }

  /// Multi-Order Batch Accept Logic (1-Tap Accept All incoming orders)
  static Future<void> acceptAllOrders({
    required List<Map<String, dynamic>> orders,
  }) async {
    try {
      final batch = _db.batch();
      for (var orderData in orders) {
        final orderId = (orderData['orderId'] ?? orderData['id'] ?? '').toString();
        if (orderId.isEmpty) continue;

        final pickupOtp = (orderData['pickupOtp'] ?? generatePickupOtp()).toString();

        final acceptRef = _db.collection('order_accept_merchant').doc(orderId);
        batch.set(acceptRef, {
          ...orderData,
          'orderId': orderId,
          'pickupOtp': pickupOtp,
          'acceptedAt': FieldValue.serverTimestamp(),
          'status': 'Preparing',
          'orderStatus': 'Preparing',
        });

        final orderRef = _db.collection('orders').doc(orderId);
        batch.set(orderRef, {
          'status': 'Preparing',
          'orderStatus': 'Preparing',
          'currentStatus': 'Preparing',
          'pickupOtp': pickupOtp,
          'acceptedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'trackingHistory': FieldValue.arrayUnion([
            {
              'status': 'Preparing',
              'title': 'Store batch accepted order & packing started',
              'updatedBy': 'Merchant',
              'timestamp': DateTime.now().toIso8601String(),
            }
          ]),
        }, SetOptions(merge: true));
      }
      await batch.commit();
    } catch (e) {
      debugPrint("Error batch accepting orders: $e");
      rethrow;
    }
  }

  /// Toggle item packed checkbox during kitchen packing
  static Future<void> updateItemPackedStatus({
    required String orderId,
    required List<dynamic> items,
    required int itemIndex,
    required bool isPacked,
  }) async {
    try {
      final updatedItems = List<Map<String, dynamic>>.from(
        items.map((it) => Map<String, dynamic>.from(it as Map)),
      );

      if (itemIndex >= 0 && itemIndex < updatedItems.length) {
        updatedItems[itemIndex]['isPacked'] = isPacked;
      }

      final allPacked = updatedItems.every((it) => it['isPacked'] == true);

      await _db.collection('orders').doc(orderId).update({
        'items': updatedItems,
        'allPacked': allPacked,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Error updating item packed status: $e");
    }
  }

  /// Update Order Status to Packing Ready (Notifies Delivery Partner to Pickup!)
  static Future<void> markOrderPackingReady(String orderId) async {
    await updateOrderStatusWithTracking(
      orderId: orderId,
      newStatus: 'Packing_Ready',
      title: 'Order Packed & Waiting for Delivery Partner Pickup',
      updatedBy: 'Merchant',
    );
  }

  /// Confirm Handover to Delivery Partner (with OTP check or 1-tap confirm)
  static Future<bool> confirmDeliveryPartnerPickup({
    required String orderId,
    required String actualOtp,
    required String enteredOtp,
  }) async {
    if (actualOtp.trim().isNotEmpty && enteredOtp.trim() != actualOtp.trim()) {
      return false;
    }

    await updateOrderStatusWithTracking(
      orderId: orderId,
      newStatus: 'Out_for_Delivery',
      title: 'Handed over to Delivery Partner & Out for Delivery',
      updatedBy: 'Merchant',
    );
    return true;
  }

  /// Merchant Order Reject Logic
  static Future<void> rejectOrder({
    required String orderId,
    required Map<String, dynamic> orderData,
    required String reason,
  }) async {
    try {
      await _db.collection('rejected_orders').doc(orderId).set({
        ...orderData,
        'orderId': orderId,
        'rejectReason': reason,
        'rejectedAt': FieldValue.serverTimestamp(),
        'status': 'Cancelled',
        'orderStatus': 'Cancelled',
      });

      await updateOrderStatusWithTracking(
        orderId: orderId,
        newStatus: 'Cancelled',
        title: 'Order Cancelled: $reason',
        updatedBy: 'Merchant',
      );
    } catch (e) {
      debugPrint("Error rejecting order: $e");
      rethrow;
    }
  }

  /// Generic Order Status updater with Tracking History
  static Future<void> updateOrderStatusWithTracking({
    required String orderId,
    required String newStatus,
    required String title,
    required String updatedBy,
  }) async {
    try {
      await _db.collection('orders').doc(orderId).set({
        'status': newStatus,
        'orderStatus': newStatus,
        'currentStatus': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
        'trackingHistory': FieldValue.arrayUnion([
          {
            'status': newStatus,
            'title': title,
            'updatedBy': updatedBy,
            'timestamp': DateTime.now().toIso8601String(),
          }
        ]),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Error updating order tracking: $e");
    }
  }
}
