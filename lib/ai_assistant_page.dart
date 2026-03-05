import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class AiAssistantPage extends StatefulWidget {
  const AiAssistantPage({
    super.key,
    this.initialPrompt,
    this.initialImagePng,
    this.autoSendInitial = false,
  });

  final String? initialPrompt;
  final Uint8List? initialImagePng;
  final bool autoSendInitial;

  @override
  State<AiAssistantPage> createState() => _AiAssistantPageState();
}

class _AiAssistantPageState extends State<AiAssistantPage>
    with TickerProviderStateMixin {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  bool _showBg = true;
  bool _sending = false;

  final List<_Msg> _messages = <_Msg>[
    _Msg.ai(
      "Hi! I'm your AI Assistant.\n"
      "You can chat with me freely. (This chat is NOT connected to any app data.)",
    ),
  ];

  final List<_Attachment> _pending = <_Attachment>[];

  // ===== Gemini config =====
  // flutter run --dart-define=GEMINI_API_KEY=xxxx
  // ===== Gemini config =====
  static const String _apiKey = 'AIzaSyA6iAhYCFQ4D384Gmfa8-vqS6tQyGtiAro';
  static const String _model = 'gemini-2.5-flash';

  static final Uri _endpoint = Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent',
  );

  @override
  void initState() {
    super.initState();

    if (widget.initialImagePng != null) {
      _pending.add(
        _Attachment.memory(
          name: 'image.png',
          bytes: widget.initialImagePng!,
          mime: 'image/png',
        ),
      );
    }

    if (widget.initialPrompt != null &&
        widget.initialPrompt!.trim().isNotEmpty) {
      _input.text = widget.initialPrompt!;
      if (widget.autoSendInitial) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _send());
      }
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickImage(ImageSource src) async {
    try {
      final picker = ImagePicker();
      final XFile? x = await picker.pickImage(
        source: src,
        imageQuality: 92,
        maxWidth: 2200,
      );
      if (x == null) return;

      final bytes = await x.readAsBytes();
      if (!mounted) return;

      setState(() {
        _pending.add(
          _Attachment.memory(
            name: x.name,
            bytes: bytes,
            mime: _guessMime(x.path) ?? 'image/jpeg',
          ),
        );
      });
    } catch (e) {
      // 常见：桌面端不支持、权限问题、厂商相册返回异常
      _snack('Image picker failed: $e');
    }
  }

  Future<void> _showPickSheet() async {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
          child: Row(
            children: [
              Expanded(
                child: _bigAction(
                  icon: Icons.photo_library_rounded,
                  label: 'Gallery',
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickImage(ImageSource.gallery);
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _bigAction(
                  icon: Icons.photo_camera_rounded,
                  label: 'Camera',
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickImage(ImageSource.camera);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bigAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: cs.primary),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Future<String> _callGemini({
    required String prompt,
    required List<_Attachment> atts,
  }) async {
    if (_apiKey.isEmpty) {
      throw Exception(
        'Missing GEMINI_API_KEY. Run with: flutter run --dart-define=GEMINI_API_KEY=xxxx',
      );
    }

    final parts = <Map<String, dynamic>>[];

    // ✅ 纯聊天：只发用户输入
    parts.add({'text': prompt});

    // 可选：图片一起发给 Gemini
    for (final a in atts) {
      final bytes = a.bytes ?? Uint8List(0);
      if (bytes.isEmpty) continue;
      final mime = a.mime ?? 'application/octet-stream';

      parts.add({
        'inline_data': {'mime_type': mime, 'data': base64Encode(bytes)},
      });
    }

    final body = jsonEncode({
      'contents': [
        {'role': 'user', 'parts': parts},
      ],
    });

    final resp = await http.post(
      _endpoint,
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': _apiKey,
      },
      body: body,
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Gemini HTTP ${resp.statusCode}: ${resp.body}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final candidates = (data['candidates'] as List?) ?? const [];
    if (candidates.isEmpty) return '(no response)';

    final c0 = candidates.first as Map<String, dynamic>;
    final content = c0['content'] as Map<String, dynamic>?;
    final cParts = (content?['parts'] as List?) ?? const [];

    for (final p in cParts) {
      final mp = p as Map<String, dynamic>;
      final t = mp['text'];
      if (t is String && t.trim().isNotEmpty) return t.trim();
    }
    return '(no text in response)';
  }

  Future<void> _send() async {
    if (_sending) return;

    final text = _input.text.trim();
    final hasAnything = text.isNotEmpty || _pending.isNotEmpty;
    if (!hasAnything) return;

    final userMsg = _Msg.user(text, atts: List.of(_pending));
    setState(() {
      _messages.add(userMsg);
      _input.clear();
      _sending = true;
      _pending.clear();
    });
    _scrollToEndSoon();

    setState(() {
      _messages.add(_Msg.ai('__thinking__'));
    });

    try {
      final res = await _callGemini(
        prompt: text.isEmpty ? 'Describe this image.' : text,
        atts: userMsg.atts,
      );

      final idx = _messages.lastIndexWhere((m) => m.text == '__thinking__');
      if (idx != -1) _messages.removeAt(idx);

      setState(() {
        _messages.add(_Msg.ai(res));
      });
    } catch (e) {
      final idx = _messages.lastIndexWhere((m) => m.text == '__thinking__');
      if (idx != -1) _messages.removeAt(idx);
      setState(() {
        _messages.add(_Msg.ai('Sorry, I ran into an error: $e'));
      });
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToEndSoon();
    }
  }

  void _scrollToEndSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 240,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1220),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          titleTextStyle: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
          title: const Text('AI Assistant'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.maybePop(context),
          ),
          actions: [
            IconButton(
              tooltip: _showBg ? 'Hide background' : 'Show background',
              onPressed: () => setState(() => _showBg = !_showBg),
              icon: Icon(
                Icons.auto_awesome_rounded,
                color: _showBg ? const Color(0xFF27E1D7) : Colors.white70,
              ),
            ),
            IconButton(
              tooltip: 'Clear chat',
              onPressed: () {
                setState(() {
                  _messages
                    ..clear()
                    ..add(
                      _Msg.ai(
                        "Hi! I'm your AI Assistant.\n"
                        "You can chat with me freely. (This chat is NOT connected to any app data.)",
                      ),
                    );
                });
              },
              icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white),
            ),
          ],
        ),
        body: Stack(
          children: [
            if (_showBg) const Positioned.fill(child: _Starfield()),
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 6),
                  Expanded(
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      itemCount: _messages.length,
                      itemBuilder: (context, i) {
                        final m = _messages[i];
                        if (m.text == '__thinking__') {
                          return const _ThinkingBrain();
                        }
                        return _Bubble(
                          msg: m,
                          onCopy: () {
                            Clipboard.setData(ClipboardData(text: m.text));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Copied')),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  if (_pending.isNotEmpty) _pendingBar(),
                  _inputBar(cs),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pendingBar() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: SizedBox(
        height: 110,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _pending.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) {
            final a = _pending[i];
            return Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.memory(
                    a.bytes ?? Uint8List(0),
                    width: 110,
                    height: 110,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  right: 6,
                  top: 6,
                  child: InkWell(
                    onTap: () => setState(() => _pending.removeAt(i)),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _inputBar(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Row(
        children: [
          InkWell(
            onTap: _showPickSheet,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0x1A27E1D7),
                border: Border.all(color: const Color(0x3327E1D7)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.image_outlined, color: Colors.white),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: cs.surface.withOpacity(.70),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outlineVariant.withOpacity(.5)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(
                  hintText: 'Ask anything…',
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _sending ? null : _send,
            icon: const Icon(Icons.send_rounded),
            label: Text(_sending ? 'Sending' : 'Send'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5B5FEF),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

enum _Role { user, ai }

class _Msg {
  _Msg(this.role, this.text, {List<_Attachment>? atts})
      : atts = atts ?? const [];
  _Msg.user(this.text, {List<_Attachment>? atts})
      : role = _Role.user,
        atts = atts ?? const [];
  _Msg.ai(this.text, {List<_Attachment>? atts})
      : role = _Role.ai,
        atts = atts ?? const [];

  final _Role role;
  final String text;
  final List<_Attachment> atts;
}

class _Attachment {
  _Attachment({required this.name, this.bytes, this.mime});
  _Attachment.memory({required this.name, required this.bytes, this.mime});

  final String name;
  final Uint8List? bytes;
  final String? mime;
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg, required this.onCopy});
  final _Msg msg;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isUser = msg.role == _Role.user;

    final bg = isUser
        ? const Color(0xFF3C2E87)
        : cs.surfaceContainerHigh.withOpacity(.72);
    const fg = Colors.white;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        constraints: const BoxConstraints(maxWidth: 720),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x4027E1D7)),
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isUser ? Icons.person : Icons.auto_awesome_rounded,
                  size: 18,
                  color: fg,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: SelectableText(
                    msg.text,
                    style: const TextStyle(color: fg, height: 1.35),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Copy',
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_all_rounded, size: 18, color: fg),
                  splashRadius: 16,
                ),
              ],
            ),
            if (msg.atts.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: msg.atts
                    .map(
                      (a) => ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          a.bytes ?? Uint8List(0),
                          width: 120,
                          height: 120,
                          fit: BoxFit.cover,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ThinkingBrain extends StatelessWidget {
  const _ThinkingBrain();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 160,
      child: Center(
        child: SizedBox(width: 140, height: 140, child: _Brain()),
      ),
    );
  }
}

class _Brain extends StatefulWidget {
  @override
  State<_Brain> createState() => _BrainState();
}

class _BrainState extends State<_Brain> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return CustomPaint(painter: _BrainPainter(_c.value));
        },
      ),
    );
  }
}

class _BrainPainter extends CustomPainter {
  _BrainPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * .28;

    final glow = Paint()
      ..color = const Color(0xFF27E1D7).withOpacity(.10)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24);
    canvas.drawCircle(c, radius * 1.6, glow);

    for (int i = 0; i < 3; i++) {
      final sc = 1.0 + (t + i * .2) % 1 * .6;
      final alpha = (1 - (sc - 1) / .6).clamp(0.0, 1.0);
      final p = Paint()
        ..color = const Color(0xFF27E1D7).withOpacity(.55 * alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawCircle(c, radius * sc, p);
    }

    final brain = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF27E1D7);
    canvas.drawCircle(c, radius, brain);

    final sweep = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..shader = SweepGradient(
        colors: const [Color(0xFF27E1D7), Colors.transparent],
        stops: const [.0, .85],
        transform: GradientRotation(t * math.pi * 2),
      ).createShader(Rect.fromCircle(center: c, radius: radius * 1.2));

    final rect = Rect.fromCircle(center: c, radius: radius * 1.2);
    canvas.drawArc(rect, 0, math.pi * 1.6, false, sweep);
  }

  @override
  bool shouldRepaint(covariant _BrainPainter oldDelegate) => true;
}

class _Starfield extends StatefulWidget {
  const _Starfield();

  @override
  State<_Starfield> createState() => _StarfieldState();
}

class _StarfieldState extends State<_Starfield>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 20),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _StarPainter(_c));
  }
}

class _StarPainter extends CustomPainter {
  _StarPainter(this.c) : super(repaint: c);
  final Animation<double> c;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF0B1220);
    canvas.drawRect(Offset.zero & size, bg);

    final n = (size.width * size.height / 12000).clamp(80, 220).toInt();
    final t = c.value;

    for (int i = 0; i < n; i++) {
      final x = (i * 91) % size.width;
      final y = (i * 57 + t * 30) % size.height;
      final r = (1 + (i % 3)) * .65;
      final col = [
        const Color(0xFFE1E6F8),
        const Color(0xFF9ADBF2),
        const Color(0xFFCBB9F8),
      ][i % 3]
          .withOpacity(.85);

      final p = Paint()
        ..color = col
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
      canvas.drawCircle(Offset(x.toDouble(), y.toDouble()), r, p);
    }
  }

  @override
  bool shouldRepaint(covariant _StarPainter oldDelegate) => true;
}

String? _guessMime(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.webp')) return 'image/webp';
  return null;
}
