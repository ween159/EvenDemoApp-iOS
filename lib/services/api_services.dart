﻿import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

class ApiService {
  late Dio _dio;

  ApiService() {
    _dio = Dio(
      BaseOptions(
        baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
        headers: {
          'Authorization': 'Bearer ${const String.fromEnvironment("DASHSCOPE_API_KEY", defaultValue: "sk-3d0c51c9e1ac4502b7406abc37940c78")}', // replace with your apikey
          'Content-Type': 'application/json',
        },
      ),
    );
  }

  Future<String> sendChatRequest(String question) async {
    final data = {
      "model": "qwen-plus",
      "messages": [
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": question}
      ],
    };
debugPrint("sendChatRequest------data----------$data--------");

    try {
      final response = await _dio.post('/chat/completions', data: data);

      if (response.statusCode == 200) {
debugPrint("Response: ${response.data}");

          final data = response.data;
          final content = data['choices']?[0]?['message']?['content'] ?? "Unable to answer the question";
          return content;
      } else {
debugPrint("Request failed with status: ${response.statusCode}");
        return "Request failed with status: ${response.statusCode}";
      }
    } on DioException catch (e) {
      if (e.response != null) {
debugPrint("Error: ${e.response?.statusCode}, ${e.response?.data}");
        return "AI request error: ${e.response?.statusCode}, ${e.response?.data}";
      } else {
debugPrint("Error: ${e.message}");
        return "AI request error: ${e.message}";
      }
    }
  }
}



