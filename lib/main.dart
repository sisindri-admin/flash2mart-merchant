import 'services/navigation_service.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'constants/app_colors.dart';
import 'screens/merchant_splash_screen.dart';
import 'screens/merchant_auth_screen.dart';
import 'screens/merchant_dashboard.dart';
import 'screens/orders_screen.dart';
import 'screens/add_product_screen.dart';
import 'screens/manage_products_screen.dart';
import 'screens/combo_offers_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const Flash2MartMerchantApp());
}

class Flash2MartMerchantApp extends StatelessWidget {
  const Flash2MartMerchantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: NavigationService.navigatorKey,
      title: 'Flash2Mart Merchant',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: AppColors.primaryGreen,
        scaffoldBackgroundColor: AppColors.bgLight,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primaryGreen,
          primary: AppColors.primaryGreen,
          secondary: AppColors.accentBlue,
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textDark,
          elevation: 0.5,
          centerTitle: false,
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const MerchantSplashScreen(),
        '/auth': (context) => const MerchantAuthScreen(),
        '/dashboard': (context) => const MerchantDashboard(),
        '/orders': (context) => const OrdersScreen(),
        '/add_product': (context) => const AddProductScreen(),
        '/manage_products': (context) => const ManageProductsScreen(),
        '/combos': (context) => const ComboOffersScreen(),
      },
    );
  }
}
