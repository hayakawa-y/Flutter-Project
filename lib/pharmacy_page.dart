// lib/pharmacy_page.dart
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'local_store.dart';
import 'cart_page.dart';

class PharmacyPage extends StatefulWidget {
  const PharmacyPage({super.key});

  @override
  State<PharmacyPage> createState() => _PharmacyPageState();
}

class _PharmacyPageState extends State<PharmacyPage> {
  /// 预定义的健康药品列表
  final List<Map<String, dynamic>> _medicines = [
    {'name': 'Vitamin C', 'price': 12.5, 'description': 'Supports immune health', 'category': 'Vitamins'},
    {'name': 'Omega-3 Fish Oil', 'price': 25.0, 'description': 'Heart and brain health', 'category': 'Supplements'},
    {'name': 'Probiotics', 'price': 18.0, 'description': 'Digestive health balance', 'category': 'Digestive'},
    {'name': 'Melatonin', 'price': 15.0, 'description': 'Supports restful sleep', 'category': 'Sleep Aid'},
    {'name': 'Magnesium Glycinate', 'price': 22.0, 'description': 'Muscle and nerve support', 'category': 'Minerals'},
    {'name': 'Vitamin D3', 'price': 10.5, 'description': 'Bone and immune support', 'category': 'Vitamins'},
    {'name': 'Zinc Gluconate', 'price': 14.0, 'description': 'Immune defense support', 'category': 'Minerals'},
    {'name': 'Iron Supplement', 'price': 16.5, 'description': 'Energy and blood health', 'category': 'Minerals'},
  ];

  /// 将药品添加到购物车
  /// [item] 包含药品信息的 Map
  Future<void> _addToCart(Map<String, dynamic> item) async {
    await LocalStore.addToCart(item);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added ${item['name']} to cart'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pharmacy Store'),
        actions: [
          // 购物车按钮，带红点提示数量
          ValueListenableBuilder(
            valueListenable: LocalStore.cartBox.listenable(),
            builder: (context, Box<Map> box, _) {
              final count = box.length;
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.shopping_cart_rounded),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const CartPage()),
                      );
                    },
                  ),
                  if (count > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: cs.error,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          '$count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _medicines.length,
        itemBuilder: (context, index) {
          final med = _medicines[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.medication_rounded, color: cs.primary),
              ),
              title: Text(
                med['name'],
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(med['description']),
                  const SizedBox(height: 8),
                  Text(
                    '\$${med['price']}',
                    style: TextStyle(
                      color: cs.primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              trailing: ElevatedButton(
                onPressed: () => _addToCart(med),
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Add'),
              ),
            ),
          );
        },
      ),
    );
  }
}
