import 'environment_config.dart';

/// Supabase connection + storage layout configuration.
///
/// Only the public anon key is ever compiled into the client. Row Level
/// Security and storage policies on the Supabase project enforce all
/// authorization; this configuration merely points the client at the
/// project.
class SupabaseConfig {
  SupabaseConfig._();

  /// Supabase project URL.
  static String get url => EnvironmentConfig.supabaseUrl;

  /// Supabase public (anon) key.
  static String get anonKey => EnvironmentConfig.supabaseAnonKey;

  /// Realtime realtime channel (single public channel in this project).
  static const String realtimeChannel = 'public';

  /// Storage buckets. Sensitive document buckets are PRIVATE; only
  /// product-images is public (display only, download still restricted
  /// client-side per showroom policy).
  class StorageBuckets {
    StorageBuckets._();

    static const String productImages = 'product-images';
    static const String customerDocuments = 'customer-documents';
    static const String vehicleDocuments = 'vehicle-documents';
    static const String invoiceDocuments = 'invoice-documents';
    static const String serviceDocuments = 'service-documents';
    static const String insuranceDocuments = 'insurance-documents';
    static const String warrantyDocuments = 'warranty-documents';
    static const String expenseAttachments = 'expense-attachments';

    /// All buckets, used by storage policy verification and admin tooling.
    static const List<String> all = <String>[
      productImages,
      customerDocuments,
      vehicleDocuments,
      invoiceDocuments,
      serviceDocuments,
      insuranceDocuments,
      warrantyDocuments,
      expenseAttachments,
    ];

    /// Buckets that may expose public read URLs.
    static const List<String> publicRead = <String>[productImages];
  }

  /// Whether a bucket is publicly readable.
  static bool isPublicBucket(String bucket) =>
      StorageBuckets.publicRead.contains(bucket);

  /// Builds a canonical storage path: `entities/{entityId}/{filename}`.
  static String storagePath({
    required String collection,
    required String entityId,
    required String fileName,
  }) {
    return '$collection/$entityId/$fileName';
  }
}
