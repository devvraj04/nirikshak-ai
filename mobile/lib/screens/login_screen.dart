import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/aura_background.dart';
import '../widgets/glass_card.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: AuraBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo Badge
                  Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppTheme.slate900,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x260F172A),
                            blurRadius: 16,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.asset(
                          'assets/images/nirikshak_logo.jpeg',
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => const Center(
                            child: Icon(
                              Icons.verified_user_rounded,
                              color: AppTheme.emerald400,
                              size: 34,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Title
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'निरीक्षक AI',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 24,
                          color: AppTheme.slate900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: AppTheme.emerald100,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppTheme.emerald200),
                        ),
                        child: const Text(
                          'LMPC 2011',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.emerald800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Legal Metrology Compliance Engine',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.slate500, fontSize: 13, fontWeight: FontWeight.w500),
                  ),

                  const SizedBox(height: 36),

                  const Text(
                    'SELECT USER ROLE',
                    style: TextStyle(
                      color: AppTheme.slate700,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 12),

                  _RoleCard(
                    title: 'Citizen / Consumer (Dev)',
                    subtitle: 'Scan products, check compliance & file complaints',
                    icon: Icons.person_outline_rounded,
                    isSelected: auth.role == UserRoleState.citizen,
                    onTap: () {
                      ref.read(authProvider.notifier).selectRole(UserRoleState.citizen);
                    },
                  ),

                  const SizedBox(height: 10),

                  _RoleCard(
                    title: 'Enforcement Officer (Raj)',
                    subtitle: 'Inspect products, review queue & verify evidence',
                    icon: Icons.badge_outlined,
                    isSelected: auth.role == UserRoleState.officer,
                    onTap: () {
                      ref.read(authProvider.notifier).selectRole(UserRoleState.officer);
                    },
                  ),

                  const SizedBox(height: 10),

                  _RoleCard(
                    title: 'System Administrator',
                    subtitle: 'Manage legal metrology rules & system analytics',
                    icon: Icons.admin_panel_settings_outlined,
                    isSelected: auth.role == UserRoleState.admin,
                    onTap: () {
                      ref.read(authProvider.notifier).selectRole(UserRoleState.admin);
                    },
                  ),

                  const SizedBox(height: 28),

                  ElevatedButton(
                    onPressed: () {
                      if (auth.role == UserRoleState.officer) {
                        context.go('/officer');
                      } else {
                        context.go('/home');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.slate900,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('CONTINUE TO PLATFORM', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ),

                  const SizedBox(height: 10),

                  Center(
                    child: TextButton.icon(
                      onPressed: () => context.go('/splash'),
                      icon: const Icon(Icons.radar_rounded, size: 14, color: AppTheme.emerald600),
                      label: const Text(
                        'View LMPC Splash Sequence',
                        style: TextStyle(
                          color: AppTheme.emerald700,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      borderRadius: 16,
      borderColor: isSelected ? AppTheme.emerald500 : AppTheme.glassBorder,
      borderWidth: isSelected ? 2 : 1,
      backgroundColor: isSelected ? Colors.white.withValues(alpha: 0.95) : AppTheme.glassFill,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.emerald100 : AppTheme.slate100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: isSelected ? AppTheme.emerald800 : AppTheme.slate700,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isSelected ? AppTheme.slate900 : AppTheme.slate800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: AppTheme.slate500, fontSize: 11),
                ),
              ],
            ),
          ),
          if (isSelected)
            const Icon(Icons.check_circle_rounded, color: AppTheme.emerald600, size: 20),
        ],
      ),
    );
  }
}
