// lib/local_store.dart
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

class LocalStore {
  // ✅ 统一 box 名字（所有页面只能用这里）
  static const String healthBoxName = 'health_records';
  static const String medsBoxName = 'medications';
  static const String usersBoxName = 'users';
  static const String authBoxName = 'auth_box';
  static const String cartBoxName = 'cart_items';
  static const String ordersBoxName = 'orders';

  static Future<void> init() async {
    await Hive.initFlutter();

    // ✅ 打开 box（名字必须完全一致）
    await Hive.openBox<Map>(healthBoxName);
    await Hive.openBox<Map>(medsBoxName);
    await Hive.openBox<Map>(usersBoxName);
    await Hive.openBox(authBoxName);
    await Hive.openBox<Map>(cartBoxName);
    await Hive.openBox<Map>(ordersBoxName);
  }

  // --- getters ---
  static Box<Map> get healthBox => Hive.box<Map>(healthBoxName);
  static Box<Map> get medsBox => Hive.box<Map>(medsBoxName);
  static Box<Map> get usersBox => Hive.box<Map>(usersBoxName);
  static Box get authBox => Hive.box(authBoxName);
  static Box<Map> get cartBox => Hive.box<Map>(cartBoxName);
  static Box<Map> get ordersBox => Hive.box<Map>(ordersBoxName);

  // ---------------- CART ----------------
  /// 获取购物车中的所有商品
  static List<Map<String, dynamic>> getCartItems() {
    return cartBox.values.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// 添加商品到购物车或增加数量
  static Future<void> addToCart(Map<String, dynamic> item) async {
    final name = item['name'] as String;
    final existing = cartBox.values.where((e) => e['name'] == name).toList();

    if (existing.isNotEmpty) {
      final key = cartBox.keys.firstWhere((k) => cartBox.get(k)?['name'] == name);
      final current = Map<String, dynamic>.from(cartBox.get(key)!);
      current['quantity'] = (current['quantity'] as int) + 1;
      await cartBox.put(key, current);
    } else {
      await cartBox.add({
        ...item,
        'quantity': 1,
      });
    }
  }

  /// 更新购物车商品数量
  static Future<void> updateCartQuantity(String name, int delta) async {
    final key = cartBox.keys.firstWhere((k) => cartBox.get(k)?['name'] == name, orElse: () => null);
    if (key != null) {
      final current = Map<String, dynamic>.from(cartBox.get(key)!);
      final newQty = (current['quantity'] as int) + delta;
      if (newQty <= 0) {
        await cartBox.delete(key);
      } else {
        current['quantity'] = newQty;
        await cartBox.put(key, current);
      }
    }
  }

  /// 清空购物车
  static Future<void> clearCart() async {
    await cartBox.clear();
  }

  // ---------------- ORDERS ----------------
  /// 获取所有订单并按时间降序排序
  static List<Map<String, dynamic>> getAllOrders() {
    final list = ordersBox.values.map((e) => Map<String, dynamic>.from(e)).toList();
    list.sort((a, b) => ((b['timestamp'] ?? 0) as int).compareTo((a['timestamp'] ?? 0) as int));
    return list;
  }

  /// 创建新订单
  static Future<void> createOrder(List<Map<String, dynamic>> items, double total) async {
    await ordersBox.add({
      'items': items,
      'total': total,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'orderId': 'ORD-${DateTime.now().millisecondsSinceEpoch}',
    });
    await clearCart();
  }

  // ---------------- AUTH (session) ----------------
  static bool isLoggedIn() =>
      authBox.get('loggedIn', defaultValue: false) == true;

  static Future<void> setLoggedIn(bool v) => authBox.put('loggedIn', v);

  /// 保存当前登录用户的 session（注意：这里只存“当前登录的谁”，不是账号库）
  static Future<void> saveSession({
    required String email,
    required String displayName,
  }) async {
    await authBox.put('email', email.toLowerCase());
    await authBox.put('displayName', displayName);
    await authBox.put('loggedIn', true);
  }

  static Future<void> clearSession() async {
    await authBox.put('loggedIn', false);
    await authBox.delete('email');
    await authBox.delete('displayName');
  }

  static String get helloName {
    final n = (authBox.get('displayName') as String?)?.trim();
    if (n != null && n.isNotEmpty) return n;
    final e = (authBox.get('email') as String?)?.trim();
    if (e != null && e.contains('@')) return e.split('@').first;
    return 'User';
  }

  static String? get sessionEmail => authBox.get('email') as String?;

  // ---------------- USERS (multi accounts) ----------------
  /// 账号库：用 email 当 key
  /// data 里包含：email / name / passwordHash / createdAt / updatedAt
  static Future<void> createUser({
    required String email,
    required String name,
    required String passwordHash,
  }) async {
    final key = email.toLowerCase();
    final existed = usersBox.get(key);
    if (existed != null) {
      throw StateError('EMAIL_EXISTS');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    await usersBox.put(key, {
      'email': key,
      'name': name,
      'passwordHash': passwordHash,
      'createdAt': now,
      'updatedAt': now,
    });
  }

  static Future<void> upsertUser({
    required String email,
    required String name,
    String? passwordHash, // 可选：需要改密码时再传
  }) async {
    final key = email.toLowerCase();
    final now = DateTime.now().millisecondsSinceEpoch;
    final old = usersBox.get(key);

    final merged = <String, dynamic>{
      'email': key,
      'name': name,
      'updatedAt': now,
      // 保留旧 createdAt
      if (old is Map && old['createdAt'] != null) 'createdAt': old['createdAt'],
      // 如果传了新密码就覆盖
      if (passwordHash != null) 'passwordHash': passwordHash,
      // 没传新密码则保留旧密码
      if (old is Map && passwordHash == null && old['passwordHash'] != null)
        'passwordHash': old['passwordHash'],
      // createdAt 兜底
      if (old is Map && old['createdAt'] == null) 'createdAt': now,
      if (old == null) 'createdAt': now,
    };

    await usersBox.put(key, merged);
  }

  static Map<String, dynamic>? getUser(String email) {
    final v = usersBox.get(email.toLowerCase());
    if (v == null) return null;
    return Map<String, dynamic>.from(v);
  }

  static bool userExists(String email) =>
      usersBox.containsKey(email.toLowerCase());

  // ---------------- HEALTH RECORDS ----------------
  static Future<void> addHealthRecord({
    required double heightCm,
    required double weightKg,
    required int systolic,
    required int diastolic,
    required double bmi,
    DateTime? time,
  }) async {
    await healthBox.add({
      'height': heightCm,
      'weight': weightKg,
      'systolic': systolic,
      'diastolic': diastolic,
      'bmi': double.parse(bmi.toStringAsFixed(2)),
      'ts': (time ?? DateTime.now()).millisecondsSinceEpoch,
    });
  }

  /// ✅ 推荐使用的新方法名
  static List<Map<String, dynamic>> getAllHealthRecordsDesc() {
    final list = healthBox.values.map((e) => Map<String, dynamic>.from(e)).toList();
    list.sort((a, b) =>
        ((b['ts'] ?? 0) as int).compareTo((a['ts'] ?? 0) as int));
    return list;
  }

  /// ✅ 兼容旧页面：如果你旧页面叫 getAllHealthRecords()，也能用
  static List<Map<String, dynamic>> getAllHealthRecords() =>
      getAllHealthRecordsDesc();

  // ---------------- MEDICATIONS ----------------
  /// ✅ 取出所有 meds 并按 startDate 新→旧排序
  /// 重要：这里统一用 startDate（与你 MedicationInput 保存字段一致）
  static List<Map<String, dynamic>> getAllMedsDesc() {
    final out = <Map<String, dynamic>>[];

    for (final k in medsBox.keys) {
      final v = medsBox.get(k);
      if (v == null) continue;
      final m = Map<String, dynamic>.from(v);
      m['_key'] = k; // Hive key（编辑/删除要用）
      out.add(m);
    }

    int sd(Map<String, dynamic> m) {
      final v = m['startDate'];
      if (v is int) return v;
      if (v is DateTime) return v.millisecondsSinceEpoch;
      if (v is String) return DateTime.tryParse(v)?.millisecondsSinceEpoch ?? 0;
      return 0;
    }

    out.sort((a, b) => sd(b).compareTo(sd(a)));
    return out;
  }

  /// 新增/更新 medication
  /// - key == null：新增（Hive 会自动分配 int key）
  /// - key != null：更新指定 key
  /// 新增 / 更新 medication
  /// 返回 Hive key（用于生成通知ID）
  static Future<dynamic> upsertMed({
    dynamic key,
    required Map<String, dynamic> data,
  }) async {
    if (key == null) {
      final newKey = await medsBox.add(data);
      return newKey;
    } else {
      await medsBox.put(key, data);
      return key;
    }
  }

  static Future<void> deleteMed(dynamic key) async {
    await medsBox.delete(key);
  }
}