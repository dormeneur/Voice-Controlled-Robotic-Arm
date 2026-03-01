import 'package:speech_to_text/speech_to_text.dart';

class SpeechService {
  final SpeechToText _speech = SpeechToText();
  bool _isInitialized = false;

  bool get isListening => _speech.isListening;

  /// Initializes the speech recognition engine. Call once per app session.
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    _isInitialized = await _speech.initialize(
      options: [SpeechToText.androidNoBluetooth],
    );
    return _isInitialized;
  }

  /// Starts listening for speech input.
  /// [onResult] is called with the recognized text and whether it is
  /// the final result.
  Future<void> startListening(
    void Function(String text, bool isFinal) onResult,
  ) async {
    await _speech.listen(
      onResult: (result) {
        onResult(result.recognizedWords, result.finalResult);
      },
    );
  }

  /// Stops listening for speech input.
  Future<void> stopListening() async {
    await _speech.stop();
  }
}
