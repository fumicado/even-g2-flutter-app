import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

/// Speech Recognition Service using phone microphone
class SpeechService {
  final SpeechToText _speechToText = SpeechToText();
  bool _isInitialized = false;
  bool _isListening = false;

  Function(String)? onResult;
  Function(String)? onPartialResult;
  Function()? onListeningStarted;
  Function()? onListeningStopped;
  Function(String)? onError;

  bool get isListening => _isListening;
  bool get isAvailable => _isInitialized;

  /// Initialize speech recognition
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      _isInitialized = await _speechToText.initialize(
        onError: (error) {
          _isListening = false;
          onError?.call(error.errorMsg);
          onListeningStopped?.call();
        },
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            _isListening = false;
            onListeningStopped?.call();
          }
        },
      );
      return _isInitialized;
    } catch (e) {
      onError?.call('Speech recognition initialization failed: $e');
      return false;
    }
  }

  /// Start listening for speech
  Future<void> startListening({String localeId = 'ja-JP'}) async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) {
        onError?.call('Speech recognition not available');
        return;
      }
    }

    if (_isListening) return;

    _isListening = true;
    onListeningStarted?.call();

    await _speechToText.listen(
      onResult: _handleResult,
      localeId: localeId,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      listenMode: ListenMode.dictation,
    );
  }

  /// Stop listening
  Future<void> stopListening() async {
    if (!_isListening) return;

    await _speechToText.stop();
    _isListening = false;
    onListeningStopped?.call();
  }

  /// Cancel listening
  Future<void> cancel() async {
    await _speechToText.cancel();
    _isListening = false;
    onListeningStopped?.call();
  }

  void _handleResult(SpeechRecognitionResult result) {
    if (result.finalResult) {
      onResult?.call(result.recognizedWords);
    } else {
      onPartialResult?.call(result.recognizedWords);
    }
  }

  /// Get available locales
  Future<List<LocaleName>> getLocales() async {
    if (!_isInitialized) await initialize();
    return await _speechToText.locales();
  }

  /// Dispose resources
  void dispose() {
    _speechToText.cancel();
    _isListening = false;
    _isInitialized = false;
  }
}
