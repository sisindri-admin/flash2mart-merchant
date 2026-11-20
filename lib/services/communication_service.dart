import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Communication Helper Service for Delivery Partner & Customer
/// 1. 1-Tap Phone Dialer Launcher (pre-fills mobile number on phone dialer pad)
/// 2. 1-Tap WhatsApp Chat Launcher (opens WhatsApp chat with pre-filled message)
class CommunicationService {
  /// Opens device native Phone Dialer Pad with pre-filled phone number
  static Future<void> callPhoneNumber(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleanPhone.isEmpty) return;

    final uri = Uri.parse('tel:$cleanPhone');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error launching phone dialer: $e');
    }
  }

  /// Opens WhatsApp Chat with pre-filled message
  static Future<void> openWhatsApp({
    required String phone,
    required String message,
  }) async {
    String cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanPhone.isEmpty) return;

    // Default India country code if 10 digits
    if (cleanPhone.length == 10) {
      cleanPhone = '91$cleanPhone';
    }

    final encodedMsg = Uri.encodeComponent(message);
    final urlStr = 'https://wa.me/$cleanPhone?text=$encodedMsg';
    final uri = Uri.parse(urlStr);

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      debugPrint('Error launching WhatsApp: $e');
    }
  }
}
