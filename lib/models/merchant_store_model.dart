import 'package:cloud_firestore/cloud_firestore.dart';

/// Merchant Store Model synced with Firestore `merchants/{merchantId}` collection
class MerchantStoreModel {
  final String uid;
  final String storeName;
  final String ownerName;
  final String phone;
  final String email;
  final String address;
  final String category;
  final GeoPoint? location;
  final bool isOpen;
  final String? fcmToken;
  final DateTime? createdAt;

  const MerchantStoreModel({
    required this.uid,
    required this.storeName,
    required this.ownerName,
    required this.phone,
    required this.email,
    required this.address,
    required this.category,
    this.location,
    required this.isOpen,
    this.fcmToken,
    this.createdAt,
  });

  factory MerchantStoreModel.fromFirestore(String uid, Map<String, dynamic> data) {
    GeoPoint? geo;
    final dynamic rawLoc = data['storeLocation'] ?? data['location'];
    if (rawLoc is GeoPoint) {
      geo = rawLoc;
    } else if (data['latitude'] != null && data['longitude'] != null) {
      geo = GeoPoint(
        (data['latitude'] as num).toDouble(),
        (data['longitude'] as num).toDouble(),
      );
    }

    DateTime? created;
    final dynamic ts = data['createdAt'];
    if (ts is Timestamp) {
      created = ts.toDate();
    }

    return MerchantStoreModel(
      uid: uid,
      storeName: (data['storeName'] ?? data['shopName'] ?? data['name'] ?? 'Flash2Mart Store').toString(),
      ownerName: (data['ownerName'] ?? data['fullName'] ?? '').toString(),
      phone: (data['phone'] ?? data['mobile'] ?? '').toString(),
      email: (data['email'] ?? '').toString(),
      address: (data['address'] ?? data['locationAddress'] ?? 'Main Road, Nellore, Andhra Pradesh').toString(),
      category: (data['category'] ?? 'Grocery / Supermarket').toString(),
      location: geo,
      isOpen: data['isOpen'] == true,
      fcmToken: data['fcmToken']?.toString(),
      createdAt: created,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'merchantId': uid,
      'uid': uid,
      'storeName': storeName,
      'shopName': storeName,
      'name': storeName,
      'ownerName': ownerName,
      'phone': phone,
      'email': email,
      'address': address,
      'locationAddress': address,
      'category': category,
      if (location != null) 'storeLocation': location,
      if (location != null) 'location': location,
      if (location != null) 'latitude': location!.latitude,
      if (location != null) 'longitude': location!.longitude,
      'isOpen': isOpen,
      if (fcmToken != null) 'fcmToken': fcmToken,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
