import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';
import 'screens/splash_screen.dart';
import 'screens/citizen_home_screen.dart';
import 'screens/complaint_screen.dart';
import 'screens/compliance_result_screen.dart';
import 'screens/login_screen.dart';
import 'screens/officer_dashboard_screen.dart';
import 'screens/rules_chat_screen.dart';
import 'screens/scan_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: NirikshakApp()));
}

final _router = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(
      path: '/splash',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/home',
      builder: (context, state) => const CitizenHomeScreen(),
    ),
    GoRoute(
      path: '/scan',
      builder: (context, state) => const ScanScreen(),
    ),
    GoRoute(
      path: '/result',
      builder: (context, state) {
        final result = (state.extra as Map<String, dynamic>?) ?? {};
        return ComplianceResultScreen(result: result);
      },
    ),
    GoRoute(
      path: '/officer',
      builder: (context, state) => const OfficerDashboardScreen(),
    ),
    GoRoute(
      path: '/complaint',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return ComplaintScreen(
          initialMrp: (extra?['mrp'] as num?)?.toDouble(),
          initialProductName: extra?['product_name'] as String?,
          initialManufacturer: extra?['manufacturer_name'] as String?,
          initialShopkeeperName: extra?['shopkeeper_name'] as String?,
          initialProductImagePath: extra?['product_image_path'] as String?,
          scanId: extra?['scan_id'] as String?,
        );
      },
    ),
    GoRoute(
      path: '/rules',
      builder: (context, state) {
        final extra = (state.extra as Map<String, dynamic>?) ?? {};
        return RulesChatScreen(
          initialTabIndex: extra['tabIndex'] as int? ?? 0,
          initialQuery: extra['initialQuery'] as String?,
          quotedRuleCode: extra['ruleCode'] as String?,
          quotedRuleTitle: extra['ruleTitle'] as String?,
          violationReason: extra['reason'] as String?,
          violationPenalty: extra['penalty'] as String?,
        );
      },
    ),
  ],
);

class NirikshakApp extends StatelessWidget {
  const NirikshakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'NIRIKSHAK AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routerConfig: _router,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: mediaQuery.textScaler.clamp(minScaleFactor: 0.85, maxScaleFactor: 1.15),
          ),
          child: child ?? const SizedBox(),
        );
      },
    );
  }
}
