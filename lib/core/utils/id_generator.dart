import 'dart:math';

import 'package:uuid/uuid.dart';

/// Centralized id generation (client-side, offline capable).
///
/// The database is the final authority on document numbers; client ids are
/// used for offline-created rows and for referential consistency while a row
/// sits in the sync queue.
class IdGenerator {
  IdGenerator._();

  static const Uuid _uuid = Uuid();

  /// New random UUID (v4) — the wire id type across the schema.
  static String uuid() => _uuid.v4();

  /// New UUID wrapped for offline drafts (still a valid UUID).
  static String localUuid() => _uuid.v4();

  /// Short human-friendly id (base32, default 8 chars), e.g. offline prefixes.
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
