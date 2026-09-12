import 'package:uuid/uuid.dart';

/// Centralized id generation.
class IdGenerator {
  IdGenerator._();

  static const Uuid _uuid = Uuid();

  /// New random UUID (v4) for local records / sync queue entries.
  static String uuid() => _uuid.v4();

  /// New UUID wrapped for offline drafts (still a valid UUID).
  static String localUuid() => _uuid.v4();
}
