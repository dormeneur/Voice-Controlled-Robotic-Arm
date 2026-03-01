import 'package:flutter_dotenv/flutter_dotenv.dart';

/// App-wide configuration loaded from the .env file.
/// Copy .env.example → .env and set GEMINI_API_KEY.
class AppConfig {
  AppConfig._();

  static String get geminiApiKey => dotenv.env['GEMINI_API_KEY'] ?? '';

  /// Allow runtime override from the in-app settings dialog.
  static String? _override;
  static String get effectiveApiKey => _override ?? geminiApiKey;
  static set geminiApiKey(String value) => _override = value;
}
