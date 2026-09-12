import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/controllers/base_list_controller.dart';
import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/documents/models/attachment_models.dart';
import 'package:enterprise_bike_showroom/features/documents/repositories/attachment_repository.dart';
import 'package:enterprise_bike_showroom/services/image_service.dart';

/// Document register.
class AttachmentController extends BaseListController<AttachmentModel> {
  AttachmentController(
    this.repository,
    this.session,
    this.imageService,
  ) : super(repository.list, pageSize: 20);

  final AttachmentRepository repository;
  final SessionController session;
  final ImageService imageService;

  @override
  Future<void> onInit() async {
    await super.onInit();
    refresh();
  }

  /// Uploads a document and records it.
  Future<bool> upload({
    required String storagePath,
    required String fileName,
    required String mimeType,
    required int fileSize,
    required String entityType,
    required String entityId,
    String notes = '',
  }) async {
    try {
      await repository.create(<String, dynamic>{
        'showroom_id':
            session.activeShowroomId.isEmpty ? null : session.activeShowroomId,
        'user_id': session.user.value?.id,
        'entity_type': entityType,
        'entity_id': entityId,
        'file_name': fileName,
        'mime_type': mimeType,
        'file_size': fileSize,
        'storage_path': storagePath,
        'notes': notes,
      });
      refresh();
      return true;
    } on AppException {
      return false;
    }
  }

  Future<bool> remove(AttachmentModel attachment) async {
    try {
      await repository.softDelete(attachment.id!);
      refresh();
      return true;
    } on AppException {
      return false;
    }
  }
}

/// Audit log register.
class AuditController extends BaseListController<AuditLogModel> {
  AuditController(AuditRepository repository)
      : super(repository.list, pageSize: 50);

  @override
  Future<void> onInit() async {
    await super.onInit();
    refresh();
  }
}
