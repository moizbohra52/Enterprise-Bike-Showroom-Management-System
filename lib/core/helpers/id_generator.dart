import 'dart:math';

import 'package:uuid/uuid.dart';

/// Central ID generation (client-side, offline-capable).
///
/// The database is the final authority on document numbers; client ids
/// are used for offline-created rows and for referential consistency
/// while a row is in the sync queue.
class IdGenerator {
  IdGenerator._();

  static const Uuid _uuid = Uuid();

  /// RFC 4122 version 4 UUID (the wire id type across the schema).
  static String uuid() => _uuid.v4();

  /// Short human-friendly id (8 base32 chars), e.g. for offline prefixes.
  static String shortId({int length = 8}) {
    const String alphabet = 'abcdefghjkmnpqrstuvwxyz23456789';
    final Random random = Random.secure();
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < length; i++) {
      buffer.write(alphabet[random.nextInt(alphabet.length)]);
    }
    return buffer.toString().toUpperCase();
  }

  /// Uniqueness token for idempotency keys.
  static String token(String prefix) => '${prefix}_${uuid()}';
}
