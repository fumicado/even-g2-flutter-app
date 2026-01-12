import 'package:flutter/material.dart';
import '../services/speech_service.dart';
import '../services/llm_service.dart';
import '../services/ble_service.dart';

class AiChatWidget extends StatefulWidget {
  final BleService bleService;

  const AiChatWidget({super.key, required this.bleService});

  @override
  State<AiChatWidget> createState() => _AiChatWidgetState();
}

class _AiChatWidgetState extends State<AiChatWidget> {
  final SpeechService _speechService = SpeechService();
  final LlmService _llmService = LlmService();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _textController = TextEditingController();

  bool _isListening = false;
  bool _isProcessing = false;
  String _partialText = '';
  String _lastResponse = '';
  final List<ChatMessage> _messages = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Load saved API key
    await _llmService.loadSavedApiKey();
    setState(() {}); // Update UI to reflect API key status

    // Initialize speech service
    await _speechService.initialize();

    _speechService.onPartialResult = (text) {
      setState(() => _partialText = text);
    };

    _speechService.onResult = (text) {
      setState(() {
        _partialText = '';
        if (text.isNotEmpty) {
          _addMessage(text, isUser: true);
          _processWithLLM(text);
        }
      });
    };

    _speechService.onListeningStarted = () {
      setState(() => _isListening = true);
    };

    _speechService.onListeningStopped = () {
      setState(() => _isListening = false);
    };

    _speechService.onError = (error) {
      _showError('Speech error: $error');
      setState(() => _isListening = false);
    };
  }

  void _addMessage(String text, {required bool isUser}) {
    setState(() {
      _messages.add(ChatMessage(text: text, isUser: isUser));
    });
  }

  Future<void> _processWithLLM(String text) async {
    if (!_llmService.isConfigured) {
      _showError('APIキーを設定してください');
      return;
    }

    setState(() => _isProcessing = true);

    try {
      // Get LLM response
      final response = await _llmService.chat(text);

      setState(() {
        _lastResponse = response;
        _isProcessing = false;
      });

      _addMessage(response, isUser: false);

      // Show response on glasses using official 0x4E AI command
      await widget.bleService.sendAIResponse(response);
    } catch (e) {
      setState(() => _isProcessing = false);
      _showError('LLM error: $e');
    }
  }

  void _toggleListening() async {
    if (_isListening) {
      await _speechService.stopListening();
    } else {
      await _speechService.startListening();
    }
  }

  void _sendTextMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    _textController.clear();
    _addMessage(text, isUser: true);
    await _processWithLLM(text);
  }

  void _showApiKeyDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('OpenAI API Key'),
        content: TextField(
          controller: _apiKeyController,
          decoration: const InputDecoration(
            hintText: 'sk-...',
            labelText: 'API Key',
          ),
          obscureText: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () async {
              final apiKey = _apiKeyController.text.trim();
              if (apiKey.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('APIキーを入力してください'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }
              await _llmService.configure(apiKey: apiKey);
              if (mounted) {
                Navigator.pop(context);
                setState(() {}); // Update UI to reflect new API key status
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('APIキーを保存しました')),
                );
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  void dispose() {
    _speechService.dispose();
    _apiKeyController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // API Key button
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _llmService.isConfigured
                      ? '✓ APIキー設定済み'
                      : 'APIキー未設定',
                  style: TextStyle(
                    color: _llmService.isConfigured ? Colors.green : Colors.orange,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: _showApiKeyDialog,
                tooltip: 'APIキー設定',
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  _llmService.clearHistory();
                  setState(() => _messages.clear());
                },
                tooltip: '履歴クリア',
              ),
            ],
          ),
        ),

        // Chat messages
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final message = _messages[index];
              return Align(
                alignment: message.isUser
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.all(12),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                  ),
                  decoration: BoxDecoration(
                    color: message.isUser
                        ? Colors.blue[100]
                        : Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.isUser ? '🎤 You' : '🤖 AI',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(message.text),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        // Partial recognition text
        if (_partialText.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.yellow[100],
            child: Row(
              children: [
                const Icon(Icons.mic, color: Colors.red, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _partialText,
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ),
          ),

        // Processing indicator
        if (_isProcessing)
          Container(
            padding: const EdgeInsets.all(8),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('AI考え中...'),
              ],
            ),
          ),

        // Input area
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            border: Border(top: BorderSide(color: Colors.grey[300]!)),
          ),
          child: Row(
            children: [
              // Text input
              Expanded(
                child: TextField(
                  controller: _textController,
                  decoration: const InputDecoration(
                    hintText: 'メッセージを入力...',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  onSubmitted: (_) => _sendTextMessage(),
                ),
              ),
              const SizedBox(width: 8),

              // Send button
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: _sendTextMessage,
                color: Colors.blue,
              ),

              // Mic button
              GestureDetector(
                onTapDown: (_) => _speechService.startListening(),
                onTapUp: (_) => _speechService.stopListening(),
                onTapCancel: () => _speechService.stopListening(),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _isListening ? Colors.red : Colors.blue,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isListening ? Icons.mic : Icons.mic_none,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}
