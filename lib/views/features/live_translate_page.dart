
import 'dart:async';

import 'package:demo_ai_even/services/realtime_translate_service.dart';
import 'package:demo_ai_even/services/settings_service.dart';
import 'package:flutter/material.dart';

class LiveTranslatePage extends StatefulWidget {
  const LiveTranslatePage({super.key});

  @override
  State<LiveTranslatePage> createState() => _LiveTranslatePageState();
}

class _LiveTranslatePageState extends State<LiveTranslatePage> {
  StreamSubscription? _sub;
  String _orig = '';
  String _vi = '';
  bool _running = false;

  Future<void> _start() async {
    final ok = await RealtimeTranslateService.I.hasMicPermission();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cần quyền micro')));
      return;
    }
    // Clear previous text when starting new session
    _orig = '';
    _vi = '';
    _sub?.cancel();
    _sub = RealtimeTranslateService.I.stream.listen((e) {
      if (e['error'] != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e['error']!)));
        }
        return;
      }
      if (e['orig'] != null) {
        if (_orig.isNotEmpty) _orig += '\n';
        _orig += e['orig']!;
      }
      if (e['vi'] != null) {
        if (_vi.isNotEmpty) _vi += '\n';
        _vi += e['vi']!;
      }
      setState(() {});
    });
    final target = await AppSettings.getTargetLang();
    final srcLang = target == 'vi' ? null : 'en';
    await RealtimeTranslateService.I.start(sourceLang: srcLang);
    setState(() => _running = true);
  }

  Future<void> _stop() async {
    await RealtimeTranslateService.I.stop();
    _sub?.cancel();
    _sub = null;
    setState(() => _running = false);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dịch realtime (OpenAI)')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: Icon(_running ? Icons.stop : Icons.mic),
                    style: ElevatedButton.styleFrom(backgroundColor: _running ? Colors.red : null),
                    label: Text(_running ? 'Dừng' : 'Bắt đầu'),
                    onPressed: _running ? _stop : _start,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: _Pane(title: 'Gốc', text: _orig),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Pane(title: 'Tiếng Việt', text: _vi),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('* Bản dịch sẽ được đồng bộ lên kính nếu bạn bật trong Cài đặt.', style: Theme.of(context).textTheme.bodySmall),
            )
          ],
        ),
      ),
    );
  }
}

class _Pane extends StatelessWidget {
  final String title;
  final String text;
  const _Pane({required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
        boxShadow: const [BoxShadow(blurRadius: 8, spreadRadius: 1, offset: Offset(0,1), color: Color(0x11000000))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const Divider(),
          Expanded(child: SingleChildScrollView(child: Text(text))),
        ],
      ),
    );
  }
}
