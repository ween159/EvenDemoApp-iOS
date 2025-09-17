
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  static const _apiKeyKey = 'openai_api_key';
  static const _audioSourceKey = 'audio_source'; // 'auto' | 'phone' | 'glasses'
  static const _streamingModeKey = 'streaming_mode'; // reserved
  static const _autoMirrorKey = 'auto_mirror_glasses'; // bool
  static const _targetLangKey = 'target_lang'; // e.g., 'vi'

  static Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_apiKeyKey);
  }

  static Future<void> setApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyKey, key.trim());
  }

  static Future<String> getAudioSource() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_audioSourceKey) ?? 'auto';
  }

  static Future<void> setAudioSource(String v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_audioSourceKey, v);
  }

  static Future<bool> getAutoMirror() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoMirrorKey) ?? true;
  }

  static Future<void> setAutoMirror(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoMirrorKey, v);
  }

  static Future<String> getTargetLang() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_targetLangKey) ?? 'vi';
  }

  static Future<void> setTargetLang(String v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_targetLangKey, v);
  }
}
