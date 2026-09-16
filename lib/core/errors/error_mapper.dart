import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_exception.dart';

/// Maps low-level errors (Dio, PostgREST, Supabase Auth, socket) to the
/// application's [AppException] hierarchy.
///
/// The UI never inspects raw exceptions; it always goes through
/// [ErrorMapper].
class ErrorMapper {
  ErrorMapper._();

  /// Maps any thrown object to an [AppException].
  static AppException map(Object error) {
    if (error is AppException) return error;
    if (error is DioException) return mapDio(error);
    if (error is PostgrestException) return mapPostgrest(error);
    if (error is AuthException) return mapAuth(error);
    if (error is SocketException) {
      return NetworkException();
    }
    if (error is TimeoutException) {
      return RequestTimeoutException();
    }
    if (kDebugMode) {
      // Surface unexpected errors with context in development only.
      return UnknownException('Unexpected error: $error', error);
    }
    return UnknownException.withDetails(error);
  }

  /// Friendly one-line message for any thrown object (snackbars/dialogs).
  static String friendly(Object error) {
    final AppException mapped = map(error);
    return mapped.message;
  }

  /// True when the error means the user must sign in again.
  static bool isAuthError(Object error) {
    final AppException mapped = map(error);
    return mapped is UnauthorizedException || mapped is AppAuthException;
  }

  /// True when the error means the user is offline.
  static bool isNetworkError(Object error) {
    final AppException mapped = map(error);
    return mapped is NetworkException || mapped is OfflineException;
  }

  /// Dio-specific mapping.
  static AppException mapDio(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return RequestTimeoutException();
      case DioExceptionType.connectionError:
        return NetworkException();
      case DioExceptionType.cancel:
        return UnknownException('Request cancelled.', error);
      case DioExceptionType.badCertificate:
        return UnknownException(
          'A security check failed while connecting to the server.',
          error,
        );
      case DioExceptionType.badResponse:
        return _mapBadResponse(error);
      case DioExceptionType.unknown:
        if (error.message?.contains('SocketException') == true ||
            error.message?.contains('Connection') == true) {
          return NetworkException();
        }
        return UnknownException.withDetails(error);
    }
  }

  static AppException _mapBadResponse(DioException error) {
    final int? status = error.response?.statusCode;
    final dynamic data = error.response?.data;
    final String? message = _extractMessage(data);

    switch (status) {
      case 400:
        return ValidationException(message ?? 'Invalid request.');
      case 401:
        return UnauthorizedException();
      case 403:
        return message == null
            ? ForbiddenException()
            : ForbiddenException(message);
      case 404:
        return message == null ? NotFoundException() : NotFoundException(message);
      case 409:
        return message == null ? ConflictException() : ConflictException(message);
      case 422:
        return ValidationException(message ?? 'Validation failed.');
      case 429:
        return ServerException('Too many requests. Please slow down.');
      default:
        if ((status ?? 500) >= 500) {
          return ServerException(message);
        }
        return UnknownException(message ?? 'Request failed.', error);
    }
  }

  /// PostgREST (Supabase Postgres) error mapping using Postgres error codes.
  static AppException mapPostgrest(PostgrestException error) {
    switch (error.code) {
      case '22P02': // invalid_text_representation
      case '23514': // check_constraint_violation
      case '23502': // not_null_violation
      case '22023': // invalid_parameter_value
      case '22003': // numeric_value_out_of_range
        return ValidationException(error.message, fields: _extractPgFields());
      case '23503': // foreign_key_violation
        return ValidationException(
          'This action would break related records. '
          'Choose a valid related record.',
        );
      case '23505': // unique_violation
        return ConflictException(_humanizeUnique(error));
      case '42501': // insufficient_privilege
        return ForbiddenException();
      case 'PGRST116': // row not found
        return NotFoundException();
      case 'PGRST204': // rpc not found
        return NotFoundException('The requested operation is not available.');
      case '0A000': // feature_not_supported
        return UnknownException('This operation is not supported.');
      default:
        if ((error.code?.startsWith('23') ?? false)) {
          return ConflictException(error.message);
        }
        return ServerException(error.message);
    }
  }

  /// Supabase Auth (GoTrue) error mapping.
  static AppException mapAuth(AuthException error) {
    final String message = error.message.toLowerCase();
    if (message.contains('invalid login credentials')) {
      return AppAuthException('Incorrect email or password.');
    }
    if (message.contains('email not confirmed')) {
      return AppAuthException('Please confirm your email before signing in.');
    }
    if (message.contains('already registered')) {
      return AppAuthException(
        'This email is already registered. Try signing in instead.',
      );
    }
    if (message.contains('rate limit')) {
      return AppAuthException('Too many attempts. Please try again later.');
    }
    if (message.contains('session expired') || message.contains('jwt')) {
      return UnauthorizedException();
    }
    return AppAuthException(
      error.message.isEmpty
          ? 'Sign in failed. Please try again.'
          : error.message,
      code: error.code,
    );
  }

  static String? _extractMessage(dynamic data) {
    if (data is Map) {
      for (final String key in <String>['message', 'msg', 'error', 'detail']) {
        final dynamic v = data[key];
        if (v is String && v.isNotEmpty) return v;
      }
      final dynamic errors = data['errors'];
      if (errors is List && errors.isNotEmpty) {
        return errors.first.toString();
      }
    }
    if (data is String && data.isNotEmpty) return data;
    return null;
  }

  static Map<String, String> _extractPgFields() => <String, String>{};

  static String _humanizeUnique(PostgrestException error) {
    final String msg = error.message.toLowerCase();
    if (msg.contains('chassis')) {
      return 'This chassis number is already registered in the system.';
    }
    if (msg.contains('engine')) {
      return 'This engine number is already registered in the system.';
    }
    if (msg.contains('unique')) {
      return 'A record with the same unique value already exists.';
    }
    return 'This record already exists.';
  }
}
