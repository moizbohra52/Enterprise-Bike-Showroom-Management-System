import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/models/dropdown_option.dart';
import 'package:enterprise_bike_showroom/common/models/role_model.dart';
import 'package:enterprise_bike_showroom/common/models/showroom_model.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_dropdown.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_loader.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_snackbar.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_text_field.dart';
import 'package:enterprise_bike_showroom/config/theme_config.dart';
import 'package:enterprise_bike_showroom/features/users/controllers/user_form_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Create / edit an application user (profile + auth account + roles).
class UserFormView extends GetView<UserFormController> {
  const UserFormView({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return AppShell(
      title: 'User',
      showBack: true,
      actions: <Widget>[
        Obx(
          () => AppButton(
            label: controller.isEdit ? 'Save changes' : 'Create user',
            icon: Icons.save_outlined,
            isLoading: controller.isSaving.value,
            onPressed:
                controller.isSaving.value ? null : () => _submit(context),
          ),
        ),
      ],
      child: Obx(
        () {
          if (controller.isLoading.value) {
            return const AppLoader(message: 'Loading user…');
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              AppCard(
                title: 'Profile',
                subtitle: controller.isEdit
                    ? 'Updating an existing user.'
                    : 'Creating the Supabase auth account and the application '
                        'profile in one step.',
                child: Form(
                  key: controller.formKey,
                  child: Column(
                    children: <Widget>[
                      AppTextField(
                        controller: controller.nameController,
                        label: 'Full name *',
                        prefixIcon: Icons.badge_outlined,
                        validator: controller.validateName,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppTextField(
                        controller: controller.emailController,
                        label: 'Work email *',
                        prefixIcon: Icons.mail_outline,
                        keyboardType: TextInputType.emailAddress,
                        readOnly: controller.isEdit,
                        validator: controller.validateEmail,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppTextField(
                        controller: controller.phoneController,
                        label: 'Phone',
                        prefixIcon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                        validator: controller.validatePhone,
                      ),
                      if (!controller.isEdit) ...<Widget>[
                        const SizedBox(height: AppSpacing.md),
                        AppTextField(
                          controller: controller.passwordController,
                          label: 'Temporary password *',
                          helper: 'Minimum 8 characters. The user can reset it '
                              'from the login screen.',
                          prefixIcon: Icons.lock_outline,
                          obscureText: true,
                          validator: controller.validatePassword,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      AppDropdown<String>(
                        label: 'Home showroom',
                        hint: 'Select showroom',
                        options: <DropdownOption<String>>[
                          for (final ShowroomModel showroom
                              in controller.session.accessibleShowrooms)
                            DropdownOption<String>(
                              value: showroom.id ?? '',
                              label: '${showroom.code} · ${showroom.name}',
                            ),
                        ],
                        value: controller.selectedShowroomId.value.isEmpty
                            ? null
                            : controller.selectedShowroomId.value,
                        onChanged: (String? value) => controller
                            .selectedShowroomId
                            .value = value ?? '',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppCard(
                title: 'Roles',
                subtitle: 'Permissions are inherited from the selected roles. '
                    'SUPER ADMIN implicitly holds every permission.',
                child: Obx(
                  () => controller.availableRoles.isEmpty
                      ? Text(
                          'No roles found. Seed roles with migration '
                          '008_roles_permissions.sql.',
                          style: theme.textTheme.bodySmall,
                        )
                      : Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            for (final RoleModel role
                                in controller.availableRoles)
                              FilterChip(
                                label: Text(role.label),
                                selected: controller.selectedRoleIds
                                    .contains(role.id),
                                onSelected: role.id == null
                                    ? null
                                    : (_) => controller.toggleRole(role.id!),
                              ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Obx(
                () => controller.errorMessage.value.isEmpty
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: Text(
                          controller.errorMessage.value,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _submit(BuildContext context) async {
    final bool saved = await controller.save();
    if (!saved) return;
    AppSnackbar.success(context, 'User saved');
    Get.back<void>();
  }
}
