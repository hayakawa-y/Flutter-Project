import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import 'modifier/auth_animations.dart';
import 'home_page.dart';
import 'local_store.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String _hash(String s) => sha256.convert(utf8.encode(s)).toString();

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _name.text.trim();
    final email = _email.text.trim().toLowerCase();
    final pwd = _password.text.trim();
    final confirm = _confirm.text.trim();

    if (pwd != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match.')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      // ✅ 不允许重复 email
      if (LocalStore.userExists(email)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This email is already registered.')),
        );
        return;
      }

      // ✅ 创建用户（多账号：存入 usersBox，包含 passwordHash）
      await LocalStore.createUser(
        email: email,
        name: name,
        passwordHash: _hash(pwd),
      );

      // ✅ 写入当前 session（auth_box 只保存“当前登录的用户”）
      await LocalStore.saveSession(email: email, displayName: name);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account created 🎉')),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
    } catch (e) {
      if (!mounted) return;

      // LocalStore.createUser 里如果抛 EMAIL_EXISTS，也给友好提示
      final msg = e.toString().contains('EMAIL_EXISTS')
          ? 'This email is already registered.'
          : 'Registration failed: $e';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _dec(String label, {Widget? suffix}) => InputDecoration(
    labelText: label,
    filled: true,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(
        color: Theme.of(context).colorScheme.outline.withOpacity(.4),
      ),
    ),
    suffixIcon: suffix,
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: FancyAuthBackground(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 12,
              ),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),
                        FadeSlideIn(
                          child: GlowTitle(
                            'Create account',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(height: 4),
                        FadeSlideIn(
                          delayMs: 80,
                          child: Text(
                            'Join and start tracking your health',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ),
                        const SizedBox(height: 18),
                        FadeSlideIn(
                          delayMs: 120,
                          child: TextFormField(
                            controller: _name,
                            decoration: _dec('Full name'),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Name is required'
                                : null,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FadeSlideIn(
                          delayMs: 160,
                          child: TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            decoration: _dec('Email'),
                            validator: (v) {
                              final s = (v ?? '').trim();
                              if (s.isEmpty) return 'Email is required';
                              if (!s.contains('@')) return 'Enter a valid email';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        FadeSlideIn(
                          delayMs: 200,
                          child: TextFormField(
                            controller: _password,
                            obscureText: _obscure,
                            decoration: _dec(
                              'Password',
                              suffix: IconButton(
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                ),
                              ),
                            ),
                            validator: (v) {
                              final s = (v ?? '').trim();
                              if (s.length < 6) return 'At least 6 characters';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        FadeSlideIn(
                          delayMs: 240,
                          child: TextFormField(
                            controller: _confirm,
                            obscureText: _obscure,
                            decoration: _dec('Confirm password'),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Confirm your password'
                                : null,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ScaleIn(
                          delayMs: 280,
                          child: BreathingButton(
                            onPressed: _loading ? null : _register,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_loading)
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                else
                                  const Icon(Icons.person_add),
                                const SizedBox(width: 8),
                                const Text('Create account'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        FadeSlideIn(
                          delayMs: 320,
                          child: GradientOutlineButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Back to sign in'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}