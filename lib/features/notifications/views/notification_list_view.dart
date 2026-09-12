import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_empty_state.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_loader.dart';
import 'package:enterprise_bike_showroom/core/enums/common_enums.dart';
import 'package:enterprise_bike_showroom/core/helpers/formatters.dart';
import 'package:enterprise_bike_showroom/features/notifications/controllers/notification_controller.dart';
import 'package:enterprise_bike_showroom/features/notifications/models/notification_model.dart';

/// In-app notification center.
class NotificationListView extends GetView<NotificationController> {
  const NotificationListView({super.key});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (controller.notifications.value.isEmpty) controller.load();
    });

    return AppShell(
      title: 'Notifications',
      actions: <Widget>[
        Obx(
          child: AppButton(
            label: 'Mark all read',
            icon: Icons.done_all_outlined,
            variant: AppButtonVariant.outlined,
            onPressed:
                controller.unreadCount.value == 0 ? null : controller.markAllRead,
          ),
        ),
      ],
      child: Obx(() {
        final List<NotificationModel> items = controller.notifications.value;
        if (controller.isLoading.value && items.isEmpty) {
          return const AppLoader();
        }
        if (items.isEmpty) {
          return const AppEmptyState(
            icon: Icons.notifications_none,
            title: 'No notifications',
            message: 'Alerts about sales, EMIs, services and renewals '
                'appear here.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(8),
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (BuildContext context, int index) {
            final NotificationModel n = items[index];
            return ListTile(
              onTap: () => controller.open(n),
              leading: Icon(
                _iconFor(n.type),
                color: n.isRead
                    ? Theme.of(context).disabledColor
                    : Theme.of(context).colorScheme.primary,
              ),
              title: Text(
                n.title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: n.isRead
                      ? FontWeight.w400
                      : FontWeight.w700,
                ),
              ),
              subtitle: Text(
                '${n.message}\n${AppFormatters.dateTime(n.sentAt)}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              isThreeLine: true,
              trailing: n.isRead
                  ? null
                  : Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Color(0xFF2563EB),
                        shape: BoxShape.circle,
                      ),
                    ),
            );
          },
        );
      }),
    );
  }

  IconData _iconFor(NotificationType type) {
    switch (type) {
      case NotificationType.payment:
        return Icons.payments;
      case NotificationType.emi:
        return Icons.request_quote;
      case NotificationType.service:
        return Icons.engineering;
      case NotificationType.insurance:
        return Icons.policy;
      case NotificationType.warranty:
        return Icons.verified_user;
      case NotificationType.approval:
        return Icons.approval_outlined;
      case NotificationType.stock:
        return Icons.inventory_2_outlined;
      case NotificationType.system:
      default:
        return Icons.campaign_outlined;
    }
  }
}
