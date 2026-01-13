import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// LLM Service for AI chat functionality
class LlmService {
  static const String _apiKeyStorageKey = 'openai_api_key';
  static const String _modelStorageKey = 'llm_model';

  String? _apiKey;
  String _model = 'gpt-5-nano';
  String _baseUrl = 'https://api.openai.com/v1';

  final List<Map<String, String>> _conversationHistory = [];

  /// Load saved API key from storage
  Future<void> loadSavedApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString(_apiKeyStorageKey);
    _model = prefs.getString(_modelStorageKey) ?? 'gpt-5-nano';
  }

  /// Configure the LLM service and save to storage
  Future<void> configure({
    required String apiKey,
    String? model,
    String? baseUrl,
  }) async {
    _apiKey = apiKey;
    if (model != null) _model = model;
    if (baseUrl != null) _baseUrl = baseUrl;

    // Save to persistent storage
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyStorageKey, apiKey);
    if (model != null) {
      await prefs.setString(_modelStorageKey, model);
    }
  }

  /// Clear saved API key
  Future<void> clearApiKey() async {
    _apiKey = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_apiKeyStorageKey);
  }

  /// Check if service is configured
  bool get isConfigured => _apiKey != null && _apiKey!.isNotEmpty;

  /// Get current model
  String get model => _model;

  /// Clear conversation history
  void clearHistory() {
    _conversationHistory.clear();
  }

  /// Send a message to the LLM and get a response
  Future<String> chat(String message, {bool useHistory = true}) async {
    if (!isConfigured) {
      throw Exception('LLM service not configured. Please set API key.');
    }

    // Add user message to history
    if (useHistory) {
      _conversationHistory.add({'role': 'user', 'content': message});
    }

    try {
      final response = await _sendRequest(message, useHistory: useHistory);

      // Add assistant response to history
      if (useHistory) {
        _conversationHistory.add({'role': 'assistant', 'content': response});
      }

      return response;
    } catch (e) {
      // Remove the user message if request failed
      if (useHistory && _conversationHistory.isNotEmpty) {
        _conversationHistory.removeLast();
      }
      rethrow;
    }
  }

  /// Send request to OpenAI-compatible API
  Future<String> _sendRequest(String message, {bool useHistory = true}) async {
    final messages = <Map<String, String>>[
      {
        'role': 'system',
        'content': 'あなたはEven G2スマートグラスのAIアシスタントです。'
            '短く簡潔に、日本語で回答してください。'
            'ユーザーは音声で質問しているので、自然な会話形式で応答してください。'
            '回答は2-3文以内に収めてください。',
      },
    ];

    if (useHistory) {
      messages.addAll(_conversationHistory);
    } else {
      messages.add({'role': 'user', 'content': message});
    }

    final url = '$_baseUrl/chat/completions';

    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      },
      body: jsonEncode({
        'model': _model,
        'messages': messages,
        'max_completion_tokens': 150,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('LLM API error: ${response.statusCode} - ${response.body}');
    }

    final data = jsonDecode(response.body);

    // Debug: print the full response structure
    print('LLM Response: ${response.body}');

    // Try GPT-5 Responses API format first (output_text or output)
    if (data['output_text'] != null) {
      return data['output_text'] as String;
    }
    if (data['output'] != null) {
      // output might be a list of content items
      final output = data['output'];
      if (output is List && output.isNotEmpty) {
        final firstOutput = output[0];
        if (firstOutput['content'] != null) {
          final content = firstOutput['content'];
          if (content is List && content.isNotEmpty) {
            return content[0]['text'] as String;
          }
        }
      }
      if (output is String) {
        return output;
      }
    }

    // Fallback to Chat Completions format
    if (data['choices'] != null && (data['choices'] as List).isNotEmpty) {
      return data['choices'][0]['message']['content'] as String;
    }

    throw Exception('Unknown response format: ${response.body}');
  }

  /// Stream chat response (for real-time display)
  Stream<String> chatStream(String message) async* {
    if (!isConfigured) {
      throw Exception('LLM service not configured. Please set API key.');
    }

    _conversationHistory.add({'role': 'user', 'content': message});

    final messages = <Map<String, String>>[
      {
        'role': 'system',
        'content': 'あなたはEven G2スマートグラスのAIアシスタントです。'
            '短く簡潔に、日本語で回答してください。'
            'ユーザーは音声で質問しているので、自然な会話形式で応答してください。'
            '回答は2-3文以内に収めてください。',
      },
      ..._conversationHistory,
    ];

    final url = '$_baseUrl/chat/completions';

    final request = http.Request('POST', Uri.parse(url));
    request.headers.addAll({
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $_apiKey',
    });
    request.body = jsonEncode({
      'model': _model,
      'messages': messages,
      'max_completion_tokens': 150,
      'stream': true,
    });

    final client = http.Client();
    try {
      final streamedResponse = await client.send(request);

      if (streamedResponse.statusCode != 200) {
        throw Exception('LLM API error: ${streamedResponse.statusCode}');
      }

      final fullResponse = StringBuffer();

      await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
        final lines = chunk.split('\n');
        for (final line in lines) {
          if (line.startsWith('data: ') && line != 'data: [DONE]') {
            try {
              final data = jsonDecode(line.substring(6));
              final content = data['choices']?[0]?['delta']?['content'];
              if (content != null) {
                fullResponse.write(content);
                yield content;
              }
            } catch (_) {
              // Skip invalid JSON
            }
          }
        }
      }

      _conversationHistory.add({'role': 'assistant', 'content': fullResponse.toString()});
    } finally {
      client.close();
    }
  }
}

enum LlmProvider {
  openai,
  anthropic,
  custom,
}
