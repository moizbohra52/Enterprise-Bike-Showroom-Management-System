import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:enterprise_bike_showroom/core/helpers/logger.dart';

/// Tracks online/offline state and notifies listeners.
///
/// On platforms where connectivity monitoring is unsupported (e.g. web) the
/// service stays optimistic (online) and the app relies on network-error
/// handling instead.
class ConnectivityService {
  ConnectivityService();

  StreamSubscription<List<ConnectivityResult>>? _subscription;

  /// Reactive online flag (optimistic `true` initially).
  bool isOnline = true;

  /// Listeners for online/offline transitions (sync service, UI banners).
  final List<void Function(bool online)> onlineListeners =
      <void Function(bool online)>[];

  /// Starts monitoring connectivity.
  void init() {
    if (_subscription != null) return;
    try {
      _subscription = Connectivity().onConnectivityChanged.listen(
        (List<ConnectivityResult> results) {
          final bool online =
              results.any((ConnectivityResult r) => r != ConnectivityResult.none);
          setOnline(online);
        },
      );
      unawaited(_initialCheck());
    } catch (e) {
      // Web / unsupported platform: assume online.
      AppLogger.debug('CONNECTIVITY', 'monitoring unsupported, assuming online',
          error: e);
    }
  }

  Future<void> _initialCheck() async {
    try {
      final List<ConnectivityResult> results =
          await Connectivity().checkConnectivity();
      final bool online = results.isNotEmpty &&
          results.any((ConnectivityResult r) => r != ConnectivityResult.none);
      setOnline(online, quiet: true);
    } catch (e) {
      AppLogger.debug('CONNECTIVITY',
          'initial check failed, keeping optimistic state', error: e);
    }
  }

  /// Updates the online flag and notifies listeners.
  void setOnline(bool online, {bool quiet = false}) {
    if (online == isOnline) return;
    isOnline = online;
    if (!quiet) {
      AppLogger.info('CONNECTIVITY', online ? 'back online' : 'went offline');
    }
    for (final void Function(bool) listener
        in List<void Function(bool)>.of(onlineListeners)) {
      try {
        listener(online);
      } catch (e) {
        AppLogger.error('CONNECTIVITY', 'listener error', error: e);
      }
    }
  }

  /// Registers an online/offline listener; returns a cancel function.
  CancelableListener addListener(void Function(bool online) listener) {
    onlineListeners.add(listener);
    return () => onlineListeners.remove(listener);
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    onlineListeners.clear();
  }
}

/// A listener that can be removed.
typedef CancelableListener = void Function();
