import 'package:flutter/material.dart';

/// A [FutureBuilder] that evaluates the future exactly once per mount, so
/// widget rebuilds do not restart the fetch (important inside forms).
class FutureCache<T> extends StatefulWidget {
  const FutureCache({
    super.key,
    required this.future,
    required this.builder,
    this.initial,
  });

  /// The factory is invoked once in initState.
  final Future<T> Function() future;
  final Widget Function(BuildContext context, AsyncSnapshot<T> snapshot) builder;
  final T? initial;

  @override
  State<FutureCache<T>> createState() => _FutureCacheState<T>();
}

class _FutureCacheState<T> extends State<FutureCache<T>> {
  late final Future<T> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.future();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: widget.builder,
    );
  }
}
