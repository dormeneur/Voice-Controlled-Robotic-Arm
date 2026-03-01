class CommandMapper {
  static const Map<String, String> _commands = {
    'left': 'L',
    'right': 'R',
    'up': 'U',
    'down': 'D',
    'pick': 'P',
    'release': 'O',
    'open': 'O',
    'reset': 'X',
  };

  /// Maps recognized speech text to a single-character command.
  /// Returns null if no valid keyword is found.
  static String? mapCommand(String text) {
    final lower = text.toLowerCase();
    for (final entry in _commands.entries) {
      if (lower.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }
}
