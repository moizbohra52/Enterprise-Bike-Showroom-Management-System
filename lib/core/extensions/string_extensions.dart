/// String conveniences.
extension StringX on String {
  /// `true` when the string is null, empty or only whitespace.
  bool get isBlank => trim().isEmpty;

  /// Uppercase first character, rest untouched.
  String get capitalized {
    if (isEmpty) return this;
    return this[0].toUpperCase() + substring(1);
  }

  /// Uppercase first letter of each word.
  String get titleCased {
    if (isEmpty) return this;
    return split(RegExp(r'[\s_-]+'))
        .map((String w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  /// Initials for avatars: `Rahul Sharma` -> `RS`.
  String get initials {
    final List<String> parts = trim().split(RegExp(r'\s+')).where((String p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  /// Masks the middle of a value: `ra***@e.com`.
  String maskMiddle({int keepStart = 2, int keepEnd = 2}) {
    if (length <= keepStart + keepEnd + 3) return '*'.padLeft(length, '*');
    return '$keepStart chars hidden';
  }

  String maskMiddleSmart() {
    if (isBlank) return '';
    if (contains('@')) {
      final List<String> parts = split('@');
      final String local = parts.first;
      final String visible = local.length > 2
          ? '${local.substring(0, 1)}${'*' * (local.length - 2)}${local.substring(local.length - 1)}'
          : '***';
      return '$visible@${parts.last}';
    }
    if (length >= 8) {
      return '${substring(0, 4)}••••${substring(length - 4)}';
    }
    return '••••';
  }
}
