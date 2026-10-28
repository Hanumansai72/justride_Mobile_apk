/// Keep actionable service messages, but never show implementation diagnostics.
String userFacingError(String? message,
    {String fallback = 'Something went wrong. Please try again.'}) {
  final text = message?.trim() ?? '';
  if (text.isEmpty || text.length > 240 || _internalDetails.hasMatch(text)) {
    return fallback;
  }
  return text;
}

final _internalDetails = RegExp(
  r'[\r\n]|https?://|(?:\d{1,3}\.){3}\d{1,3}|[A-Z]:[\\/]|'
  r'\b(?:exception|stacktrace|traceback|socketexception|clientexception|'
  r'platformexception|formatexception|typeerror|nosuchmethoderror|'
  r'sqlstate|sql|mongoose|mongodb|postgres|econnrefused|enotfound|'
  r'localhost|esp32|gatt|rgb565|sharedpreferences)\b|'
  r'\b(?:bearer\s+|eyJ[A-Za-z0-9_-]+\.|api[_ -]?key|access[_ -]?token)|'
  r'/(?:home|usr|var|tmp|api)/',
  caseSensitive: false,
);
