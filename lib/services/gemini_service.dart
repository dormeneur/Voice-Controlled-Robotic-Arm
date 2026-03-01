import 'package:google_generative_ai/google_generative_ai.dart';

import '../config/app_config.dart';

/// Sends natural-language voice commands to Gemini and gets back a compact
/// command sequence string such as "LUPROD".
///
/// Valid characters in the sequence:
///   L = move left
///   R = move right
///   U = move up
///   D = move down
///   P = pick / grab / close gripper
///   O = release / open gripper / drop
///   X = reset to home position
class GeminiService {
  GenerativeModel? _model;

  static const _systemPrompt = '''
You are a strict command parser for a robotic arm controller.

The robotic arm understands exactly these 7 commands:
  L = move left
  R = move right
  U = move up
  D = move down
  P = pick / grab / grasp / close gripper
  O = open / release / drop (open gripper)
  X = reset / go home / restart

Your job: read the user's natural language instruction and return a command sequence string.

RULES — follow these exactly:
1. Output ONLY the sequence string. No spaces, no punctuation, no explanation, no quotes.
2. Use ONLY the characters L, R, U, D, P, O, X (uppercase).
3. Map ALL movement/action words to the correct letter. Synonyms to consider:
   - left, turn left, go left → L
   - right, turn right, go right → R
   - up, raise, lift → U
   - down, lower, descend → D
   - pick, grab, grasp, take, hold, close, clamp → P
   - release, open, drop, let go, place, put down → O
   - reset, home, restart, return → X
4. Preserve the ORDER in which the user states the actions.
5. If a word appears multiple times, repeat the letter multiple times.
6. If the sentence contains NO recognisable commands, output only: NONE

Examples:
  "move left, go up, pick it, move right, go down, release" → LUPROD
  "can you move the arm left up pick then move right then down and finally release it" → LUPROD
  "go right twice then pick and drop" → RRPO
  "lift the arm, grab the part, lower it, release" → UPDО
  "reset" → X
  "hello how are you" → NONE
''';

  /// Initialises (or re-initialises) the model with the current API key.
  void _ensureModel() {
    _model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: AppConfig.effectiveApiKey,
      systemInstruction: Content.system(_systemPrompt),
      generationConfig: GenerationConfig(
        temperature: 0, // zero temperature → deterministic
        maxOutputTokens: 64,
      ),
    );
  }

  /// Returns a command sequence string or throws on error.
  Future<String> parseSequence(String userSpeech) async {
    if (AppConfig.effectiveApiKey.isEmpty) {
      throw Exception('Gemini API key is not set.');
    }

    _ensureModel();

    final response = await _model!.generateContent([Content.text(userSpeech)]);

    final raw = response.text?.trim().toUpperCase() ?? '';

    // Strip any non-command chars the model might have sneaked in
    final cleaned = raw.replaceAll(RegExp(r'[^LRUDPOX]'), '');

    if (cleaned.isEmpty || cleaned == 'NONE') {
      throw Exception('Could not identify any commands in the speech.');
    }

    return cleaned;
  }
}
