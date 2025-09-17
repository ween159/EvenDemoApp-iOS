// lib/services/openai_service.dart
//
// Dịch vụ OpenAI cho STT (transcription) và dịch sang tiếng Việt.
// - /v1/audio/transcriptions để chuyển WAV -> text
// - /v1/chat/completions để dịch sang tiếng Việt
//
// Cách dùng:
// final openai = OpenAIService(apiKey: 'sk-...');
// final enText = await openai.transcribeWavBytes(wavBytes);
// final viText = await openai.translateToVietnamese(enText);

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart' show MediaType;

class OpenAIService {
  OpenAIService({
    required this.apiKey,
    Dio? dio,
    String baseUrl = 'https://api.openai.com/v1',
  }) : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl,
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 60),
              ),
            ) {
    // Thiết lập header Authorization ở đây (không dùng biến lạ).
    _dio.options.headers['Authorization'] = 'Bearer $apiKey';
  }

  /// API key truyền vào khi khởi tạo service
  final String apiKey;

  /// Dio dùng chung
  final Dio _dio;

  /// STT: WAV bytes -> văn bản
  /// [sttModel] mặc định 'whisper-1'.
  Future<String> transcribeWavBytes(
    List<int> wavBytes, {
    String sttModel = 'whisper-1',
    String? languageCode,
  }) async {
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          wavBytes,
          filename: 'audio.wav',
          // contentType cần MediaType
          contentType: MediaType('audio', 'wav'),
        ),
        'model': sttModel,
        if (languageCode != null) 'language': languageCode,
      });

      final Response resp = await _dio.post(
        '/audio/transcriptions',
        data: formData,
      );

      final data = resp.data;
      if (data is Map && data['text'] is String) {
        return (data['text'] as String).trim();
      }
      throw OpenAIServiceException(
        'Unexpected transcription response shape',
        details: data,
      );
    } on DioException catch (e) {
      throw OpenAIServiceException.fromDio('Transcription failed', e);
    } catch (e) {
      throw OpenAIServiceException('Transcription failed', details: e);
    }
  }

  /// Dịch một đoạn văn bản sang tiếng Việt
  Future<String> translateToVietnamese(
    String text, {
    String model = 'gpt-4o-mini',
    double temperature = 0.2,
  }) async {
    try {
      final body = <String, dynamic>{
        'model': model,
        'temperature': temperature,
        'messages': [
          {
            'role': 'system',
            'content':
                "You are a translation engine. Translate the user's text to Vietnamese. Return ONLY the translation with natural Vietnamese punctuation."
          },
          {
            'role': 'user',
            'content': text,
          },
        ],
      };

      final Response resp = await _dio.post(
        '/chat/completions',
        data: body,
        options: Options(contentType: 'application/json'),
      );

      final data = resp.data;
      if (data is Map &&
          data['choices'] is List &&
          (data['choices'] as List).isNotEmpty) {
        final choice0 = (data['choices'] as List).first;
        final message = choice0 is Map ? choice0['message'] : null;
        final content = message is Map ? message['content'] : null;
        if (content is String) return content.trim();
      }
      throw OpenAIServiceException(
        'Unexpected translation response shape',
        details: data,
      );
    } on DioException catch (e) {
      throw OpenAIServiceException.fromDio('Translation failed', e);
    } catch (e) {
      throw OpenAIServiceException('Translation failed', details: e);
    }
  }

  /// Tiện ích: STT rồi dịch sang tiếng Việt
  Future<String> transcribeAndTranslate(
    List<int> wavBytes, {
    String sttModel = 'whisper-1',
    String translateModel = 'gpt-4o-mini',
    String? languageCode,
    double temperature = 0.2,
  }) async {
    final original = await transcribeWavBytes(
      wavBytes,
      sttModel: sttModel,
      languageCode: languageCode,
    );
    return translateToVietnamese(
      original,
      model: translateModel,
      temperature: temperature,
    );
  }
}

class OpenAIServiceException implements Exception {
  OpenAIServiceException(this.message, {this.details});

  final String message;
  final Object? details;

  factory OpenAIServiceException.fromDio(String label, DioException e) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    final msg =
        status == null ? '$label: network/client error' : '$label: HTTP $status';
    return OpenAIServiceException(msg, details: data ?? e.message);
  }

  @override
  String toString() {
    final d = details == null ? '' : ' | details: $details';
    return 'OpenAIServiceException: $message$d';
    }
}
