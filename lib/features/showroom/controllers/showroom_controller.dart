import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/models/showroom_model.dart';
import 'package:enterprise_bike_showroom/common/controllers/base_list_controller.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/showroom/repositories/showroom_repository.dart';
import 'package:enterprise_bike_showroom/core/constants/permission_constants.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';

/// Showroom list controller (SUPER ADMIN only module).
class ShowroomController extends BaseListController<ShowroomModel> {
  ShowroomController(
    ShowroomRepository repository,
    SessionController session,
  ) : super(repository.list, pageSize: 20) {
    this.repository = repository;
    this.session = session;
  }

  late final ShowroomRepository repository;
  late final SessionController session;

  /// Only SUPER ADMIN (or users granted showroom.view) reach this screen.
  bool get canCreate => session.can(Permissions.showroomCreate);
  bool get canEdit => session.can(Permissions.showroomEdit);

  @override
  Future<void> onInit() async {
    await super.onInit();
    refresh();
  }

  Future<void> openForm({String? id}) async {
    await Get.toNamed(
      AppRoutes.showroomForm,
      parameters: <String, String?>{
        if (id != null) 'id': id,
      },
    );
    refresh();
  }

  Future<void> openDetails(ShowroomModel showroom) async {
    await Get.toNamed(AppRoutes.showroomDetails,
        parameters: <String, String?>{'id': showroom.id});
  }
}
