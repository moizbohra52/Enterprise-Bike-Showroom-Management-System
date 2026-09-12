/// List conveniences.
extension ListX<T> on List<T> {
  /// Splits the list into chunks of at most [size] items.
  List<List<T>> chunked(int size) {
    if (size <= 0) return <List<T>>[List<T>.of(this)];
    final List<List<T>> chunks = <List<T>>[];
    for (int i = 0; i < length; i += size) {
      chunks.add(sublist(i, i + size > length ? length : i + size));
    }
    return chunks;
  }

  /// Removes duplicates by the provided key.
  List<T> uniqueBy(dynamic Function(T) key) {
    final Set<dynamic> seen = <dynamic>{};
    final List<T> result = <T>[];
    for (final T item in this) {
      if (seen.add(key(item))) result.add(item);
    }
    return result;
  }

  /// First non-null result of [transform] or null.
  R? firstValue<R>(R? Function(T) transform) {
    for (final T item in this) {
      final R? value = transform(item);
      if (value != null) return value;
    }
    return null;
  }

  /// Sums a numeric projection (zero for empty).
  num sumBy(num Function(T) value) {
    num total = 0;
    for (final T item in this) {
      total += value(item);
    }
    return total;
  }
}
