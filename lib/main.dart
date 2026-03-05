// lib/main.dart
import 'package:flutter/material.dart';
import 'local_store.dart';
import 'home_page.dart';
import 'login_page.dart';
import 'notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ 先初始化本地存储
  await LocalStore.init();

  // ✅ 再初始化通知（内部已包含 timezone 初始化）
  await NotificationService.init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Health App',
      theme: ThemeData(
        useMaterial3: true,
        // 可选：统一页面过渡更稳定（不改也行）
        // pageTransitionsTheme: const PageTransitionsTheme(builders: {
        //   TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        //   TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        // }),
      ),
      home: const SplashPage(),
    );
  }
}

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    // ✅ 给启动页一点展示时间，同时确保 init 都完成了
    await Future.delayed(const Duration(seconds: 2));

    final isLoggedIn = LocalStore.isLoggedIn();

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => isLoggedIn ? const HomePage() : const LoginPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/logo.png',
              width: 140,
              errorBuilder: (context, error, stackTrace) {
                // ✅ 避免 assets 路径/未声明导致红屏
                return const Icon(Icons.health_and_safety, size: 120);
              },
            ),
            const SizedBox(height: 20),
            const Text(
              "Health App",
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}