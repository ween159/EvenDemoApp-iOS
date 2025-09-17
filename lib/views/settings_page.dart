
import 'package:demo_ai_even/services/settings_service.dart';
import 'package:demo_ai_even/services/realtime_translate_service.dart';
import 'package:flutter/material.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _apiCtl = TextEditingController();
  String _audio = 'auto';
  bool _autoMirror = true;
  String _lang = 'vi';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _apiCtl.text = (await AppSettings.getApiKey()) ?? '';
    _audio = await AppSettings.getAudioSource();
    _autoMirror = await AppSettings.getAutoMirror();
    _lang = await AppSettings.getTargetLang();
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    await AppSettings.setApiKey(_apiCtl.text);
    await AppSettings.setAudioSource(_audio);
    await AppSettings.setAutoMirror(_autoMirror);
    await AppSettings.setTargetLang(_lang);
    // Configure realtime service with new API key
    try {
      RealtimeTranslateService.I.configure(apiKey: _apiCtl.text);
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã lưu cài đặt')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('OpenAI API Secret Key'),
          const SizedBox(height: 8),
          TextField(
            controller: _apiCtl,
            obscureText: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'sk-...',
            ),
          ),
          const SizedBox(height: 16),
          const Text('Nguồn micro'),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'auto', label: Text('Tự động')),
              ButtonSegment(value: 'phone', label: Text('Điện thoại')),
              ButtonSegment(value: 'glasses', label: Text('Kính')),
            ],
            selected: <String>{_audio},
            onSelectionChanged: (s) => setState(() => _audio = s.first),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Tự đồng bộ lên kính (beta)'),
            value: _autoMirror,
            onChanged: (v) => setState(() => _autoMirror = v),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _lang,
            items: const [
              DropdownMenuItem(value: 'vi', child: Text('Tiếng Việt')),
              DropdownMenuItem(value: 'en', child: Text('English (for test)')),
            ],
            onChanged: (v) => setState(() => _lang = v ?? 'vi'),
            decoration: const InputDecoration(labelText: 'Ngôn ngữ đích', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('Lưu'),
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
