// lib/home_page.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:getwidget/getwidget.dart';
import 'package:animations/animations.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'modifier/fancy_routes.dart';

// pages
import 'health_input_page.dart';
import 'medication_input_page.dart';
import 'medication_list_page.dart';
import 'health_analytics_page.dart';
import 'ai_assistant_page.dart';
import 'login_page.dart';
import 'pharmacy_page.dart';
import 'cart_page.dart';
import 'order_history_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late final AnimationController _bg = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();

  Box get _authBox => Hive.box('auth_box');

  @override
  void dispose() {
    _bg.dispose();
    super.dispose();
  }

  /// ✅ 本地用户名（Hive）
  String get _helloName {
    final name = (_authBox.get('currentName') ?? '').toString().trim();
    if (name.isNotEmpty) return name;

    final email = (_authBox.get('currentEmail') ?? '').toString().trim();
    if (email.contains('@')) return email.split('@').first;

    return 'currentName';
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      await _authBox.put('isLoggedIn', false);
      await _authBox.delete('currentEmail');
      await _authBox.delete('currentName');

      if (!context.mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sign out failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Home'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => _signOut(context),
          ),
        ],
      ),
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _bg,
            builder: (_, __) {
              final t = _bg.value * 2 * math.pi;
              final bgStops = isDark
                  ? [
                cs.surfaceVariant.withOpacity(.18),
                cs.surface.withOpacity(.16),
                Colors.black.withOpacity(.20),
              ]
                  : [
                cs.primaryContainer.withOpacity(.32),
                cs.secondaryContainer.withOpacity(.28),
                cs.tertiaryContainer.withOpacity(.24),
              ];

              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: bgStops,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    _blob(
                      220,
                      Offset(90 * math.sin(t), 60 * math.cos(t)),
                      cs.primary.withOpacity(isDark ? .12 : .18),
                    ),
                    _blob(
                      280,
                      Offset(-110 * math.cos(t), 70 * math.sin(t)),
                      cs.secondary.withOpacity(isDark ? .10 : .14),
                    ),
                    _blob(
                      180,
                      Offset(60 * math.cos(t * .8), -90 * math.sin(t * .9)),
                      cs.tertiary.withOpacity(isDark ? .08 : .12),
                    ),
                  ],
                ),
              );
            },
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ✅ 用 ValueListenableBuilder 确保登录名变更会刷新
                  ValueListenableBuilder(
                    valueListenable: _authBox.listenable(keys: const [
                      'currentName',
                      'currentEmail',
                    ]),
                    builder: (context, box, _) {
                      return Text(
                        'Hello, $_helloName',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      );
                    },
                  ),
                  const SizedBox(height: 14),

                  // ✅ Mini stats（已移除 Sleep）
                  Row(
                    children: [
                      Expanded(
                        child: _MiniStatGF(
                          icon: Icons.favorite_rounded,
                          label: 'Well-being',
                          value: 'Stable',
                          color: cs.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MiniStatGF(
                          icon: Icons.show_chart_rounded,
                          label: 'Analytics',
                          value: 'Ready',
                          color: cs.secondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  _ActionCardGF(
                    heroTag: 'hero-health',
                    icon: Icons.favorite_border_rounded,
                    title: 'Health Data Input',
                    subtitle: 'Enter BP / Height / Weight; auto-calc BMI',
                    onTap: () => pushSharedAxis(context, const HealthInputPage()),
                  ),
                  const SizedBox(height: 12),

                  _ActionCardGF(
                    heroTag: 'hero-meds',
                    icon: Icons.medication_liquid_outlined,
                    title: 'Medication Records & Reminders',
                    subtitle: 'Add meds and set local reminders',
                    onTap: () => pushSlideFancy(
                      context,
                      const MedicationInputPage(),
                      from: AxisDirection.right,
                    ),
                    trailing: IconButton(
                      tooltip: 'View list',
                      icon: const Icon(Icons.list_rounded),
                      onPressed: () =>
                          pushFadeScale(context, const MedicationListPage()),
                    ),
                  ),
                  const SizedBox(height: 12),

                  _ActionCardGF(
                    heroTag: 'hero-pharmacy',
                    icon: Icons.local_pharmacy_outlined,
                    title: 'Pharmacy Store',
                    subtitle: 'Shop health products and manage cart',
                    onTap: () => pushSharedAxis(context, const PharmacyPage()),
                  ),
                  const SizedBox(height: 12),

                  OpenContainer(
                    transitionDuration: const Duration(milliseconds: 520),
                    openColor: Theme.of(context).colorScheme.surface,
                    closedElevation: 0,
                    closedShape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    openBuilder: (_, __) => const HealthAnalyticsPage(),
                    closedBuilder: (_, open) => _ActionCardGF(
                      heroTag: 'hero-analytics',
                      icon: Icons.show_chart_rounded,
                      title: 'Health Analytics',
                      subtitle: 'View charts based on local data',
                      onTap: open,
                    ),
                  ),
                  const SizedBox(height: 12),

                  _ActionCardGF(
                    heroTag: 'hero-ai',
                    icon: Icons.smart_toy_outlined,
                    title: 'AI Assistant',
                    subtitle: 'Chat with AI (local data context supported)',
                    onTap: () => pushFadeScale(context, const AiAssistantPage()),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _blob(double size, Offset offset, Color color) => Align(
    alignment: Alignment.center,
    child: Transform.translate(
      offset: offset,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(.35),
              blurRadius: 80,
              spreadRadius: 10,
            ),
          ],
        ),
      ),
    ),
  );
}

/* ---------------- UI widgets ---------------- */

class _ActionCardGF extends StatelessWidget {
  const _ActionCardGF({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    required this.heroTag,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final String heroTag;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GFCard(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      color: cs.surface.withOpacity(.70),
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      content: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Hero(
                tag: heroTag,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: cs.primary),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(' ', style: TextStyle(height: 0)),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              trailing ??
                  Icon(
                    Icons.chevron_right_rounded,
                    color: cs.onSurfaceVariant.withOpacity(.8),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStatGF extends StatelessWidget {
  const _MiniStatGF({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GFCard(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.all(0),
      elevation: 1.5,
      margin: EdgeInsets.zero,
      content: Container(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(value, style: TextStyle(fontSize: 12, color: color)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}