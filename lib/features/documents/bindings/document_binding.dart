import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/documents/controllers/attachment_controller.dart';
import 'package:enterprise_bike_showroom/features/documents/repositories/attachment_repository.dart';
import 'package:enterprise_bike_showroom/services/image_service.dart';
import 'package:enterprise_bike_showroom/services/supabase_service.dart';

/// Registers documents + audit module dependencies.
class DocumentBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<AttachmentRepository>(
      () => AttachmentRepository(Get.find<SupabaseService>()),
      fenix: true,
    );
    Get.lazyPut<AuditRepository>(
      () => AuditRepository(Get.find<SupabaseService>()),
      fenix: true,
    );
    Get.lazyPut<AttachmentController>(
      () => AttachmentController(
        Get.find<AttachmentRepository>(),
        Get.find<SessionController>(),
        Get.find<ImageService>(),
      ),
      fenix: true,
    );
    Get.lazyPut<AuditController>(
      () => AuditController(Get.find<AuditRepository>()),
      fenix: true,
    );
  }
}
