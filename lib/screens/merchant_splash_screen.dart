import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'merchant_auth_screen.dart';
import 'merchant_dashboard.dart';

/// Animated Splash Screen with Auto-Login Verification
class MerchantSplashScreen extends StatefulWidget {
  const MerchantSplashScreen({super.key});

  @override
  State<MerchantSplashScreen> createState() => _MerchantSplashScreenState();
}

class _MerchantSplashScreenState extends State<MerchantSplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.05).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeIn),
    );

    _animController.forward();
    _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate() async {
    await Future.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // User already logged in -> Go directly to Dashboard
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MerchantDashboard()),
      );
    } else {
      // User not logged in -> Go to Login / Register Screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MerchantAuthScreen()),
      );
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryDark,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Glowing Lightning Bolt Icon Circle
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryGreen.withAlpha(102),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.electric_bolt_rounded,
                      color: AppColors.accentAmber,
                      size: 56,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Brand Title
                RichText(
                  text: const TextSpan(
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                    children: [
                      TextSpan(text: 'Flash', style: TextStyle(color: Color(0xFF4ADE80))),
                      TextSpan(text: '2', style: TextStyle(color: AppColors.accentAmber)),
                      TextSpan(text: 'Mart', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
                const SizedBox(height: 6),

                // Tagline Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceDark,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.storefront_rounded, color: AppColors.accentBlue, size: 14),
                      SizedBox(width: 5),
                      Text(
                        'MERCHANT PARTNER PORTAL',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),

                // Small sleek loading spinner
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: AppColors.primaryGreen,
                    strokeWidth: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
