/// Base class for all application-level errors.
///
/// Repositories and services throw [AppException] subtypes; the UI maps
/// them to friendly messages through [ErrorMapper] and [AppSnackbar].
class AppException implements Exception {
  AppException(this.message, {this.code, this.details});

  /// Human-readable message (already safe to display).
  final String message;

  /// Machine-readable error code (e.g. `42501`, `PGRST116`, `offline`).
  final String? code;

  /// Original underlying error (kept for logging, never displayed).
  final dynamic details;

  @override
  String toString() =>
      'AppException(${code ?? 'unknown'}): $message';
}

/// Network unreachable / connection failure.
class NetworkException extends AppException {
  NetworkException([
    String message = 'Unable to reach the server. Please check your '
        'internet connection.',
  ]) : super(message, code: 'network_error');
}

/// Operation attempted while offline (and offline mode does not support it).
class OfflineException extends AppException {
  OfflineException([
    String message = 'You are offline. This action requires a connection.',
  ]) : super(message, code: 'offline');
}

/// Session invalid or missing (401).
class UnauthorizedException extends AppException {
  UnauthorizedException([
    String message = 'Your session has expired. Please sign in again.',
  ]) : super(message, code: 'unauthorized');
}

/// Authenticated but not allowed (403 / RLS violation).
class ForbiddenException extends AppException {
  ForbiddenException([
    String message = 'You do not have permission to perform this action.',
  ]) : super(message, code: 'forbidden');
}

/// Input validation failure, with per-field messages.
class ValidationException extends AppException {
  ValidationException(String message, {Map<String, String>? fields})
      : fields = fields ?? <String, String>{},
        super(message, code: 'validation');

  /// Field name -> error message.
  final Map<String, String> fields;
}

/// Record does not exist (404 / PGRST116).
class NotFoundException extends AppException {
  NotFoundException([
    String message = 'The requested record was not found.',
  ]) : super(message, code: 'not_found');
}

/// Unique-constraint or business-state conflict (409 / 23505).
class ConflictException extends AppException {
  ConflictException([
    String message = 'This record already exists or is in an invalid state.',
  ]) : super(message, code: 'conflict');
}

/// Unexpected server-side failure (5xx).
class ServerException extends AppException {
  ServerException([String? message])
      : super(
          message ?? 'The server encountered an error. Please try again.',
          code: 'server_error',
        );
}

/// Request took too long.
class RequestTimeoutException extends AppException {
  RequestTimeoutException([
    String message = 'The request timed out. Please try again.',
  ]) : super(message, code: 'timeout');
}

/// Supabase authentication failure.
class AppAuthException extends AppException {
  AppAuthException(String message, {String? code, dynamic details})
      : super(message, code: code, details: details);
}

/// Unknown / unmapped error.
class UnknownException extends AppException {
  UnknownException([
    String message = 'Something went wrong. Please try again.',
    dynamic details,
  ]) : super(message, code: 'unknown', details: details);
}
