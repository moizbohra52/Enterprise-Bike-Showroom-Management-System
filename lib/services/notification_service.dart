import 'dart:async';

import 'package:firebase_core/firebase_core.dart' show Firebase;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/helpers/logger.dart';
import 'package:enterprise_bike_showroom/services/supabase_service.dart';

/// Firebase Cloud Messaging integration.
///
/// - Requests permission, obtains the device token on login.
/// - Upserts the token into the `device_tokens` table (multiple devices per
///   user are supported).
/// - Deactivates the token on logout.
/// - Delivers foreground messages to [onForegroundMessage] (wired to the
///   notification controller for in-app display + realtime DB rows).
class NotificationService {
  NotificationService({required SupabaseService supabase})
      : supabase = supabase;

  /// Supabase backend (device_tokens table).
  final SupabaseService supabase;

  /// Foreground message sink (wired by the app to show in-app notifications).
  void Function(RemoteMessage message)? onForegroundMessage;

  /// Tap-to-open sink (wired by the app to navigate).
  void Function(RemoteMessage message)? onMessageOpened;

  String? _currentToken;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;

  /// The last fetched FCM token (null on web / when unavailable).
  String? get currentToken => _currentToken;

  /// Push is only available on builds that have a Firebase configuration.
  bool get supported => !kIsWeb;

  /// Platform name stored with the token.
  String get platformName {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return 'linux';
    }
  }

  /// Initializes messaging listeners (safe no-op where FCM is unavailable).
  Future<void> init() async {
    if (!supported || Firebase.apps.isEmpty) {
      AppLogger.warning('FCM', 'Firebase not initialized; push disabled');
      return;
    }
    try {
      final FirebaseMessaging messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final RemoteMessage? launch = await messaging.getInitialMessage();
      if (launch != null) _onOpened(launch);
      _foregroundSub = messaging.onMessage.listen(_onForeground);
      _openedSub = messaging.onMessageOpenedApp.listen(_onOpened);
      AppLogger.info('FCM', 'initialized');
    } catch (e) {
      AppLogger.warning('FCM', 'init failed (push unavailable)', error: e);
    }
  }

  void _onForeground(RemoteMessage message) {
    onForegroundMessage?.call(message);
  }

  void _onOpened(RemoteMessage message) {
    onMessageOpened?.call(message);
  }

  /// Requests notification permission (Android/iOS).
  Future<bool> requestPermission() async {
    try {
      final PermissionStatus status = await Permission.notification.request();
      return status.isGranted || status.isLimited;
    } catch (e) {
      AppLogger.warning('FCM', 'permission request failed', error: e);
      return false;
    }
  }

  /// Fetches the FCM token (null when unsupported).
  Future<String?> getToken() async {
    try {
      final String? token = await FirebaseMessaging.instance.getToken();
      _currentToken = token;
      return token;
    } catch (e) {
      AppLogger.debug('FCM', 'token unavailable', error: e);
      return null;
    }
  }

  /// Registers the current token for [userId] and updates `last_seen_at`.
  Future<void> registerToken({
    required String userId,
    String? token,
  }) async {
    final String? t = token ?? _currentToken ?? await getToken();
    if (t == null || t.isEmpty) return;
    _currentToken = t;
    try {
      final String deviceName = await _deviceName();
      await supabase.client.from('device_tokens').upsert(
            <String, dynamic>{
              'user_id': userId,
              'device_token': t,
              'platform': platformName,
              'device_name': deviceName,
              'is_active': true,
              'last_seen_at': DateTime.now().toIso8601String(),
            },
            onConflict: 'user_id,device_token',
          );
      AppLogger.info('FCM', 'token registered for $userId');
    } catch (e) {
      AppLogger.warning('FCM', 'token registration failed', error: e);
      throw ErrorMapper.map(e);
    }
  }

  /// Deactivates the current token (called on logout).
  Future<void> deactivateToken({
    required String userId,
    String? token,
  }) async {
    final String? t = token ?? _currentToken;
    if (t == null || t.isEmpty) return;
    try {
      await supabase.client
          .from('device_tokens')
          .update(<String, dynamic>{
            'is_active': false,
          })
          .eq('user_id', userId)
          .eq('device_token', t);
      AppLogger.info('FCM', 'token deactivated for $userId');
    } catch (e) {
      AppLogger.warning('FCM', 'token deactivation failed', error: e);
    }
  }

  /// Touches `last_seen_at` for the current device (session keepalive).
  Future<void> touchToken({required String userId, String? token}) async {
    final String? t = token ?? _currentToken;
    if (t == null) return;
    try {
      await supabase.client
          .from('device_tokens')
          .update(<String, dynamic>{
            'last_seen_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', userId)
          .eq('device_token', t);
    } catch (e) {
      AppLogger.debug('FCM', 'touch failed', error: e);
    }
  }

  Future<String> _deviceName() async {
    try {
      final DeviceInfoPlugin info = DeviceInfoPlugin();
      if (kIsWeb) return 'Web browser';
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final AndroidDeviceInfo d = await info.androidInfo;
          return '${d.brand} ${d.model}';
        case TargetPlatform.iOS:
          final IosDeviceInfo d = await info.iosInfo;
          return '${d.name} ${d.model}';
        case TargetPlatform.windows:
          final WindowsDeviceInfo d = await info.windowsInfo;
          return 'Windows ${d.releaseId}';
        default:
          return 'Web browser';
      }
    } catch (e) {
      return 'Unknown device';
    }
  }

  /// Sends a local (in-app) notification via the database so it appears in
  /// the notifications list on every device of the user.
  Future<void> pushToUser({
    required String userId,
    required String title,
    required String message,
    required String type,
    String? showroomId,
    String? referenceId,
    String? referenceType,
  }) async {
    try {
      await supabase.client.from('notifications').insert(<String, dynamic>{
        'user_id': userId,
        'showroom_id': showroomId,
        'title': title,
        'message': message,
        'notification_type': type,
        'reference_id': referenceId,
        'reference_type': referenceType,
        'is_read': false,
        'sent_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      AppLogger.warning('FCM', 'local push failed', error: e);
      throw ErrorMapper.map(e);
    }
  }

  void dispose() {
    _foregroundSub?.cancel();
    _openedSub?.cancel();
  }
}

/// Re-exports so callers can catch FCM issues with the app error type.
typedef FcmException = AppException;
