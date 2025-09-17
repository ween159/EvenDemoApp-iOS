// lib/services/realtime_translate_service.dart
//
// D?ch realtime: nh?n WAV bytes -> STT -> d?ch sang Ti?ng Vi?t
// - Có singleton: RealtimeTranslateService.I (h?p v?i UI dang g?i .I)
// - Có factory constructor d? t?o instance c?u hình s?n (không redirecting có body)
// - API chính: hasMicPermission(), start(), stop(), stream, processWavBytes(...)
// - Ti?n ích: transcribeOnly(), translateOnly()

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:demo_ai_even/services/openai_service.dart';
import 'package:demo_ai_even/services/settings_service.dart';
import 'package:demo_ai_even/services/evenai.dart';
import 'package:demo_ai_even/services/proto.dart';
import 'package:demo_ai_even/ble_manager.dart';
import 'package:record/record.dart';
import 'package:flutter/foundation.dart';

class RealtimeTranslateService {
  // -------- Singleton cho UI: RealtimeTranslateService.I --------
  static final RealtimeTranslateService I = RealtimeTranslateService._internal();

  // Private constructor cho singleton
  RealtimeTranslateService._internal();

  // Factory constructor (du?c phép có body) d? t?o instance dã c?u hình
  factory RealtimeTranslateService({
    required String apiKey,
    String sttModel = 'whisper-1',
    String translateModel = 'gpt-4o-mini',
    double temperature = 0.2,
  }) {
    final s = RealtimeTranslateService._internal();
    s.configure(
      apiKey: apiKey,
      sttModel: sttModel,
      translateModel: translateModel,
      temperature: temperature,
    );
    return s;
  }

  // -------- C?u hình d?ch v? --------
  String? _apiKey;
  String _sttModel = 'whisper-1';       // ho?c 'gpt-4o-mini-transcribe' n?u tài kho?n h? tr?
  String _translateModel = 'gpt-4o-mini';
  double _temperature = 0.2;

  // -------- Paragraph accumulation for glasses display --------
  String _englishParagraph = '';
  String _vietnameseParagraph = '';
  int _sentenceCount = 0;
  static const int _sentencesPerParagraph = 3; // Send to glasses every 3 sentences

  OpenAIService? _openai;

  /// G?i hàm này d? c?p nh?t API key / model khi c?n (ví d? sau khi user nh?p key).
  void configure({
    required String apiKey,
    String? sttModel,
    String? translateModel,
    double? temperature,
  }) {
    _apiKey = apiKey;
    if (sttModel != null) _sttModel = sttModel;
    if (translateModel != null) _translateModel = translateModel;
    if (temperature != null) _temperature = temperature;
    _openai = OpenAIService(apiKey: _apiKey!);
  }

  // -------- Stream s? ki?n cho UI --------
  // Map g?m: { 'orig': b?n g?c, 'vi': b?n d?ch, 'error': l?i (n?u có) }
  final StreamController<Map<String, String?>> _eventCtrl =
      StreamController<Map<String, String?>>.broadcast();

  Stream<Map<String, String?>> get stream => _eventCtrl.stream;

  // -------- Quy?n mic & vòng d?i --------

  /// Tr? v? true d? UI không b? ch?n; n?u dùng permission_handler/record, thay b?ng check th?t s?.
  Future<bool> hasMicPermission() async => true;

  bool _running = false;
  StreamSubscription<String>? _evenAiSub;

  // Phone mic recording
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _recordingTimer;

  /// Kh?i d?ng phiên d?ch (không t? ghi âm; b?n d?y audio vào b?ng processWavBytes)
  Future<void> start({String? sourceLang}) async {
    debugPrint('DEBUG: RealtimeTranslateService.start() called');
    debugPrint('DEBUG: API key check: ${_apiKey != null ? "present" : "null"}, isEmpty: ${_apiKey?.isEmpty ?? true}');
    if (_apiKey == null || _apiKey!.isEmpty) {
      debugPrint('DEBUG: Missing API key, adding error event');
      _eventCtrl.add({'error': 'Thi?u OpenAI API Key trong Cài d?t.'});
      return;
    }
    _running = true;
    debugPrint('DEBUG: Set _running = true');
    
    // Reset paragraph accumulation when starting new session
    _englishParagraph = '';
    _vietnameseParagraph = '';
    _sentenceCount = 0;
    // Determine audio source from settings (auto/phone/glasses)
    debugPrint('DEBUG: Getting audio source from settings...');
    final audioSource = await AppSettings.getAudioSource();
    debugPrint('DEBUG: Audio source: $audioSource');

    if (audioSource == 'glasses') {
      // Ensure glasses are connected before subscribing to their speech stream
      if (!BleManager.instance.isBothConnected()) {
        _eventCtrl.add({'error': 'Kính chua k?t n?i. Vui lòng k?t n?i kính tru?c khi b?t Realtime Translate.'});
        return;
      }
      // subscribe to EvenAI text stream and translate incoming texts
      await _evenAiSub?.cancel();
      _evenAiSub = EvenAI.textStream.listen((txt) async {
        if (!_running) return;
        final t = txt.trim();
        if (t.isEmpty) return;
        try {
          final vi = await _openai!.translateToVietnamese(t, model: _translateModel, temperature: _temperature);
          _eventCtrl.add({'orig': t, 'vi': vi});
          final autoMirror = await AppSettings.getAutoMirror();
          if (autoMirror && BleManager.instance.isBothConnected()) {
            await Proto.sendEvenAIData(vi, newScreen: (0x01 | 0x30), pos: 0, current_page_num: 1, max_page_num: 1);
          }
        } catch (e) {
          _eventCtrl.add({'error': e.toString()});
        }
      });
      return;
    }

    // For phone or auto sources: enable phone mic recording
    if (audioSource == 'phone' || audioSource == 'auto') {
      debugPrint('DEBUG: Starting phone mic recording for source: $audioSource');
      await _startPhoneMicRecording();
      return;
    }
  }

  Future<void> stop() async {
    _running = false;
    try {
      await _recorder.stop();
      _recordingTimer?.cancel();
      _recordingTimer = null;
    } catch (_) {}
    await _evenAiSub?.cancel();
    _evenAiSub = null;
    
    // Reset paragraph accumulation when stopping
    _englishParagraph = '';
    _vietnameseParagraph = '';
    _sentenceCount = 0;
  }

  // -------- Tác v? chính: nh?n WAV bytes -> STT -> d?ch -> phát s? ki?n --------

  /// Nh?n m?t khúc WAV bytes, STT -> d?ch -> phát ra stream {orig, vi}
  Future<void> processWavBytes(
    List<int> wavBytes, {
    String? languageCode,
  }) async {
    print('DEBUG: processWavBytes called with ${wavBytes.length} bytes');
    if (!_running) {
      print('DEBUG: processWavBytes skipped, not running');
      return;
    }
    if (_openai == null) {
      debugPrint('DEBUG: processWavBytes failed, no OpenAI service');
      _eventCtrl.add({'error': 'D?ch v? chua du?c c?u hình API key.'});
      return;
    }

    // Check if audio contains actual speech before transcribing
    if (!_hasAudibleContent(wavBytes)) {
      debugPrint('DEBUG: Audio chunk contains only silence, skipping transcription');
      return;
    }

    try {
      debugPrint('DEBUG: Calling OpenAI transcribe...');
      // 1) STT
      final textOriginal = await _openai!.transcribeWavBytes(
        wavBytes,
        sttModel: _sttModel,
        languageCode: languageCode,
      );
      debugPrint('DEBUG: Transcription result: $textOriginal');
      if (textOriginal.isEmpty) return;

      debugPrint('DEBUG: Calling OpenAI translate...');
      // 2) D?ch -> Ti?ng Vi?t
      final vi = await _openai!.translateToVietnamese(
        textOriginal,
        model: _translateModel,
        temperature: _temperature,
      );
      debugPrint('DEBUG: Translation result: $vi');

      // 3) Phát s? ki?n cho UI
      _eventCtrl.add({'orig': textOriginal, 'vi': vi});
      debugPrint('DEBUG: Event sent to UI');
      
      // 4) T? d?ng g?i b?n d?ch lên kính n?u du?c b?t
      final autoMirror = await AppSettings.getAutoMirror();
      if (autoMirror && BleManager.instance.isBothConnected()) {
        await _updateGlassesDisplay(textOriginal, vi);
      }
    } catch (e) {
      debugPrint('DEBUG: processWavBytes error: $e');
      _eventCtrl.add({'error': e.toString()});
    }
  }

  // ---- Phone recorder loop ----
  // Phone recording intentionally not implemented in this iteration.

  /// Ch? STT (n?u c?n hi?n th? b?n g?c song song)
  Future<String> transcribeOnly(
    List<int> wavBytes, {
    String? languageCode,
  }) async {
    if (_openai == null) {
      throw StateError('OpenAIService chua du?c c?u hình. Hãy g?i configure(apiKey: ...) tru?c.');
    }
    return _openai!.transcribeWavBytes(
      wavBytes,
      sttModel: _sttModel,
      languageCode: languageCode,
    );
  }

  /// Ch? d?ch do?n text sang Ti?ng Vi?t
  Future<String> translateOnly(String text) async {
    if (_openai == null) {
      throw StateError('OpenAIService chua du?c c?u hình. Hãy g?i configure(apiKey: ...) tru?c.');
    }
    return _openai!.translateToVietnamese(
      text,
      model: _translateModel,
      temperature: _temperature,
    );
  }

  // ---- Phone mic recording implementation ----
  Future<void> _startPhoneMicRecording() async {
    print('DEBUG: _startPhoneMicRecording called');
    
    // Request mic permission
    final hasPermission = await _recorder.hasPermission();
    debugPrint('DEBUG: Mic permission: $hasPermission');
    
    if (!hasPermission) {
      _eventCtrl.add({'error': 'Không có quy?n truy c?p micro.'});
      return;
    }
    
    // Start continuous recording in chunks
    debugPrint('DEBUG: Starting record chunks...');
    await _recordChunks();
  }
  
  Future<void> _recordChunks() async {
    int chunkIndex = 0;
    debugPrint('DEBUG: _recordChunks started');
    
    _recordingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!_running) {
        debugPrint('DEBUG: Recording stopped, _running = false');
        timer.cancel();
        return;
      }
      
      final currentChunk = chunkIndex++;
      debugPrint('DEBUG: Recording chunk $currentChunk');
      
      try {
        // Stop any previous recording
        await _recorder.stop();
        
        // Create temp file path for this chunk
        final tempDir = Directory.systemTemp;
        final tempFile = File('${tempDir.path}/audio_chunk_$currentChunk.wav');
        debugPrint('DEBUG: Recording to file: ${tempFile.path}');
        
        // Start recording to file
        await _recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            numChannels: 1,
          ),
          path: tempFile.path,
        );
        debugPrint('DEBUG: Recording started, waiting 2.5s...');
        
        // Record for 2.5 seconds to ensure minimum duration
        await Future.delayed(const Duration(milliseconds: 2500));
        
        final recordedPath = await _recorder.stop();
        debugPrint('DEBUG: Recording stopped, path: $recordedPath');
        
        if (recordedPath != null && _running) {
          final file = File(recordedPath);
          if (await file.exists()) {
            final wavBytes = await file.readAsBytes();
            debugPrint('DEBUG: Read WAV file, size: ${wavBytes.length} bytes');
            // Feed WAV bytes to STT
            await processWavBytes(wavBytes);
            debugPrint('DEBUG: processWavBytes called');
            // Clean up temp file
            await file.delete();
          } else {
            debugPrint('DEBUG: WAV file does not exist: $recordedPath');
          }
        }
        
      } catch (e) {
        debugPrint('DEBUG: Recording error: $e');
        _eventCtrl.add({'error': 'L?i recording: $e'});
        timer.cancel();
      }
    });
  }

  // -------- Vietnamese text conversion for glasses display --------
  
  /// Convert Vietnamese diacritics to no-diacritics Vietnamese for better font compatibility
  /// Uses proper Vietnamese characters without tone marks instead of ASCII conversion
  String _convertVietnameseNoDiacritics(String text) {
    // Map Vietnamese characters with diacritics to Vietnamese without diacritics
    final Map<String, String> vietnameseMap = {
      // A family - keep Vietnamese but remove diacritics
      'à': 'a', 'á': 'a', '?': 'a', 'ã': 'a', '?': 'a',
      'a': 'a', '?': 'a', '?': 'a', '?': 'a', '?': 'a', '?': 'a',
      'â': 'a', '?': 'a', '?': 'a', '?': 'a', '?': 'a', '?': 'a',
      'À': 'A', 'Á': 'A', '?': 'A', 'Ã': 'A', '?': 'A',
      'A': 'A', '?': 'A', '?': 'A', '?': 'A', '?': 'A', '?': 'A',
      'Â': 'A', '?': 'A', '?': 'A', '?': 'A', '?': 'A', '?': 'A',
      
      // E family
      'è': 'e', 'é': 'e', '?': 'e', '?': 'e', '?': 'e',
      'ê': 'e', '?': 'e', '?': 'e', '?': 'e', '?': 'e', '?': 'e',
      'È': 'E', 'É': 'E', '?': 'E', '?': 'E', '?': 'E',
      'Ê': 'E', '?': 'E', '?': 'E', '?': 'E', '?': 'E', '?': 'E',
      
      // I family
      'ì': 'i', 'í': 'i', '?': 'i', 'i': 'i', '?': 'i',
      'Ì': 'I', 'Í': 'I', '?': 'I', 'I': 'I', '?': 'I',
      
      // O family
      'ò': 'o', 'ó': 'o', '?': 'o', 'õ': 'o', '?': 'o',
      'ô': 'o', '?': 'o', '?': 'o', '?': 'o', '?': 'o', '?': 'o',
      'o': 'o', '?': 'o', '?': 'o', '?': 'o', '?': 'o', '?': 'o',
      'Ò': 'O', 'Ó': 'O', '?': 'O', 'Õ': 'O', '?': 'O',
      'Ô': 'O', '?': 'O', '?': 'O', '?': 'O', '?': 'O', '?': 'O',
      'O': 'O', '?': 'O', '?': 'O', '?': 'O', '?': 'O', '?': 'O',
      
      // U family  
      'ù': 'u', 'ú': 'u', '?': 'u', 'u': 'u', '?': 'u',
      'u': 'u', '?': 'u', '?': 'u', '?': 'u', '?': 'u', '?': 'u',
      'Ù': 'U', 'Ú': 'U', '?': 'U', 'U': 'U', '?': 'U',
      'U': 'U', '?': 'U', '?': 'U', '?': 'U', '?': 'U', '?': 'U',
      
      // Y family
      '?': 'y', 'ý': 'y', '?': 'y', '?': 'y', '?': 'y',
      '?': 'Y', 'Ý': 'Y', '?': 'Y', '?': 'Y', '?': 'Y',
      
      // D family - keep d as special case, critical for Vietnamese
      'd': 'd', 'Ð': 'D',
    };
    
    String result = text;
    vietnameseMap.forEach((vietnamese, noDiacritic) {
      result = result.replaceAll(vietnamese, noDiacritic);
    });
    
    return result;
  }


  /// Send bilingual text to glasses using TextService approach for scrollable display
  /// Uses Vietnamese without diacritics to avoid font issues
  Future<void> _sendDualSideText(String englishText, String vietnameseText) async {
    try {
      // Convert Vietnamese to no-diacritics version for better font compatibility
      final vietnameseNoDiacritics = _convertVietnameseNoDiacritics(vietnameseText);
      
      debugPrint('DEBUG: Sending bilingual text to glasses using TextService approach');
      debugPrint('DEBUG: English: $englishText');
      debugPrint('DEBUG: Vietnamese (original): $vietnameseText');
      debugPrint('DEBUG: Vietnamese (no diacritics): $vietnameseNoDiacritics');

      // Create bilingual display with proper formatting for TextService
      // Format similar to TextService: clear separation and good readability
      final bilinguaText = "???? $englishText\n\n???? $vietnameseNoDiacritics";
      
      // Use TextService approach: send directly with 0x70 mode for scrollable display
      await Proto.sendEvenAIData(
        bilinguaText,
        newScreen: (0x01 | 0x70), // TextService mode for scrollable display
        pos: 0,
        current_page_num: 1, 
        max_page_num: 1,
      );
      
      debugPrint('DEBUG: Bilingual text sent using TextService mode (scrollable)');
      
    } catch (e) {
      debugPrint('DEBUG: Error sending bilingual text, trying fallback: $e');
      
      // Fallback to Vietnamese-only without diacritics
      try {
        final vietnameseOnly = _convertVietnameseNoDiacritics(vietnameseText);
        
        await Proto.sendEvenAIData(
          vietnameseOnly,
          newScreen: (0x01 | 0x70), // TextService mode
          pos: 0,
          current_page_num: 1,
          max_page_num: 1,
        );
        
        debugPrint('DEBUG: Fallback Vietnamese-only display completed');
      } catch (e2) {
        debugPrint('DEBUG: All approaches failed: $e2');
        rethrow;
      }
    }
  }

  /// Update glasses display with paragraph accumulation and bilingual display
  /// Shows both English and Vietnamese together since G1 doesn't support true split-screen
  Future<void> _updateGlassesDisplay(String english, String vietnamese) async {
    // Accumulate sentences
    _englishParagraph += (_englishParagraph.isEmpty ? '' : ' ') + english;
    _vietnameseParagraph += (_vietnameseParagraph.isEmpty ? '' : ' ') + vietnamese;
    _sentenceCount++;

    // Check if we should send to glasses (every N sentences or if paragraph is getting long)
    bool shouldSend = _sentenceCount >= _sentencesPerParagraph || 
                     _englishParagraph.length > 200 || 
                     vietnamese.contains('.') || vietnamese.contains('!') || vietnamese.contains('?');

    if (shouldSend) {
      debugPrint('DEBUG: Sending paragraph to glasses ($_sentenceCount sentences)');
      debugPrint('DEBUG: English: $_englishParagraph');
      debugPrint('DEBUG: Vietnamese: $_vietnameseParagraph');

      try {
        // Send bilingual text to glasses (English + Vietnamese together)
        await _sendDualSideText(_englishParagraph, _vietnameseParagraph);
        
        // Reset paragraph accumulation
        _englishParagraph = '';
        _vietnameseParagraph = '';
        _sentenceCount = 0;
      } catch (e) {
        debugPrint('DEBUG: Error sending bilingual text to glasses: $e');
        // Fallback to Vietnamese-only display using TextService mode for scrollability
        final glassesText = _convertVietnameseNoDiacritics(vietnamese);
        await Proto.sendEvenAIData(glassesText, newScreen: (0x01 | 0x70), pos: 0, current_page_num: 1, max_page_num: 1);
      }
    } else {
      debugPrint('DEBUG: Accumulating sentence $_sentenceCount/$_sentencesPerParagraph');
    }
  }

  /// Check if audio data contains audible content (not just silence)
  /// to prevent AI hallucination when transcribing empty audio
  bool _hasAudibleContent(List<int> wavBytes) {
    if (wavBytes.length < 44) return false; // Invalid WAV
    
    // Skip WAV header (44 bytes) and analyze audio samples
    const int headerSize = 44;
    if (wavBytes.length <= headerSize) return false;
    
    // Calculate RMS (Root Mean Square) to detect audio energy
    double sum = 0.0;
    int sampleCount = 0;
    
    // Read 16-bit samples from WAV data
    for (int i = headerSize; i < wavBytes.length - 1; i += 2) {
      if (i + 1 >= wavBytes.length) break;
      
      // Convert bytes to 16-bit signed integer (little-endian)
      int sample = wavBytes[i] | (wavBytes[i + 1] << 8);
      if (sample > 32767) sample -= 65536; // Convert to signed
      
      sum += sample * sample;
      sampleCount++;
    }
    
    if (sampleCount == 0) return false;
    
    // Calculate RMS and check if it exceeds silence threshold
    double rms = sqrt(sum / sampleCount);
    const double silenceThreshold = 500.0; // Adjust as needed
    
    bool hasAudio = rms > silenceThreshold;
    debugPrint('DEBUG: Audio RMS: ${rms.toStringAsFixed(2)}, HasAudio: $hasAudio');
    
    return hasAudio;
  }

  // -------- D?n d?p --------
  void dispose() {
    _eventCtrl.close();
  }
}
