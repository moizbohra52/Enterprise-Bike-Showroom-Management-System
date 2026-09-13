import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_dropdown.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_snackbar.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_text_field.dart';
import 'package:enterprise_bike_showroom/common/models/dropdown_option.dart';
import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/validators/validators.dart';
import 'package:enterprise_bike_showroom/features/accounting/controllers/accounting_controller.dart';
import 'package:enterprise_bike_showroom/features/accounting/repositories/accounting_repository.dart';

/// New account (chart extension).
class AccountFormView extends StatefulWidget {
  const AccountFormView({super.key});

  @override
  State<AccountFormView> createState() => _AccountFormViewState();
}

class _AccountFormViewState extends State<AccountFormView> {
  final AccountController controller = Get.find<AccountController>();

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'New Account',
      showBack: true,
      actions: <Widget>[
        Obx(
          () => AppButton(
            label: 'Create Account',
            icon: Icons.save_outlined,
            isLoading: _saving.value,
            onPressed: _saving.value ? null : _submit,
          ),
        ),
      ],
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: AppCard(
          child: Form(
            key: _formKey,
            child: Column(
              children: <Widget>[
                _field('code', 'Account Code * (e.g. 1010)',
                    validator: (String? v) =>
                        AppValidators.required(v, message: 'Code is required.')),
                _field('name', 'Account Name *',
                    validator: (String? v) =>
                        AppValidators.required(v, message: 'Name is required.')),
                AppDropdown<String>(
                  label: 'Type',
                  options: const <DropdownOption<String>>[
                    DropdownOption(value: 'asset', label: 'Asset'),
                    DropdownOption(value: 'liability', label: 'Liability'),
                    DropdownOption(value: 'equity', label: 'Equity'),
                    DropdownOption(value: 'income', label: 'Income'),
                    DropdownOption(value: 'expense', label: 'Expense'),
                  ],
                  value: _type,
                  onChanged: (String? value) =>
                      setState(() => _type = value ?? 'asset'),
                ),
                _field('subType', 'Sub-type (optional)'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  final RxBool _saving = false.obs;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _code = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _subType = TextEditingController();
  String _type = 'asset';

  Widget _field(String key, String label,
      {String? Function(String?)? validator}) {
    final TextEditingController controller = key == 'code'
        ? _code
        : key == 'name'
            ? _name
            : _subType;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppTextField(
        controller: controller,
        label: label,
        validator: validator,
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _saving.value = true;
    try {
      final AccountingRepository repository =
          Get.find<AccountingRepository>();
      await repository.createAccount(<String, dynamic>{
        'code': _code.text.trim().toUpperCase(),
        'name': _name.text.trim(),
        'type': _type,
        if (_subType.text.trim().isNotEmpty)
          'sub_type': _subType.text.trim().toLowerCase(),
      });
      AppSnackbar.success(context, 'Account created');
      Get.back();
      controller.refresh();
    } on AppException catch (e) {
      AppSnackbar.error(context, e.message);
    } catch (e) {
      AppSnackbar.error(context, ErrorMapper.friendly(e));
    } finally {
      _saving.value = false;
    }
  }
}
