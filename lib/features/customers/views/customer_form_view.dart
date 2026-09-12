import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_dropdown.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_snackbar.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_text_field.dart';
import 'package:enterprise_bike_showroom/common/widgets/future_cache.dart';
import 'package:enterprise_bike_showroom/common/models/dropdown_option.dart';
import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/validators/validators.dart';
import 'package:enterprise_bike_showroom/features/customers/controllers/customer_controller.dart';
import 'package:enterprise_bike_showroom/features/customers/models/customer_models.dart';

/// Add / edit customer.
class CustomerFormView extends GetView<CustomerController> {
  const CustomerFormView({super.key});

  @override
  Widget build(BuildContext context) {
    final String? id = Get.parameters['id'];
    final bool isEdit = id != null;
    final RxBool saving = _saving;

    return AppShell(
      title: isEdit ? 'Edit Customer' : 'Add Customer',
      showBack: true,
      actions: <Widget>[
        Obx(
          child: AppButton(
            label: isEdit ? 'Save Changes' : 'Create Customer',
            icon: Icons.save_outlined,
            isLoading: saving,
            onPressed: saving ? null : () => _submit(isEdit, id),
          ),
        ),
      ],
      child: FutureCache<CustomerModel?>(
        future: () =>
            isEdit ? controller.repository.getById(id!) : Future.value(null),
        builder: (BuildContext context, AsyncSnapshot<CustomerModel?> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          _apply(snapshot.data);
          return _form();
        },
      ),
    );
  }

  final RxBool _saving = false.obs;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _fields = <String, TextEditingController>{
    'name': TextEditingController(),
    'phone': TextEditingController(),
    'alternatePhone': TextEditingController(),
    'email': TextEditingController(),
    'address': TextEditingController(),
    'city': TextEditingController(),
    'state': TextEditingController(),
    'pincode': TextEditingController(),
    'notes': TextEditingController(),
  };

  String _type = 'retail';
  String _status = 'active';

  void _apply(CustomerModel? c) {
    if (c == null) return;
    _fields['name']?.text = c.name;
    _fields['phone']?.text = c.phone;
    _fields['alternatePhone']?.text = c.alternatePhone;
    _fields['email']?.text = c.email;
    _fields['address']?.text = c.address;
    _fields['city']?.text = c.city;
    _fields['state']?.text = c.state;
    _fields['pincode']?.text = c.pincode;
    _fields['notes']?.text = c.notes;
    _type = c.customerType;
    _status = c.status;
  }

  Widget _form() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: AppCard(
        child: Form(
          key: _formKey,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  children: <Widget>[
                    _field('name', 'Full Name *',
                        validator: (String? v) =>
                            AppValidators.required(v, message: 'Name is required.')),
                    _field('phone', 'Phone *',
                        keyboardType: TextInputType.phone,
                        validator: (String? v) => AppValidators.phone(v)),
                    _field('alternatePhone', 'Alternate Phone',
                        keyboardType: TextInputType.phone,
                        validator: (String? v) => AppValidators.optionalPhone(v)),
                    _field('email', 'Email',
                        keyboardType: TextInputType.emailAddress,
                        validator: (String? v) => AppValidators.email(v)),
                    _field('address', 'Address', maxLines: 3),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: <Widget>[
                    _field('city', 'City'),
                    _field('state', 'State'),
                    _field('pincode', 'Pincode',
                        keyboardType: TextInputType.number,
                        validator: (String? v) => AppValidators.pincode(v)),
                    AppDropdown<String>(
                      label: 'Customer Type',
                      options: const <DropdownOption<String>>[
                        DropdownOption(value: 'retail', label: 'Retail'),
                        DropdownOption(value: 'dealer', label: 'Dealer'),
                        DropdownOption(value: 'corporate', label: 'Corporate'),
                        DropdownOption(value: 'financier', label: 'Financier'),
                      ],
                      value: _type,
                      onChanged: (String? value) =>
                          setState(() => _type = value ?? 'retail'),
                    ),
                    const SizedBox(height: 12),
                    AppDropdown<String>(
                      label: 'Status',
                      options: const <DropdownOption<String>>[
                        DropdownOption(value: 'active', label: 'Active'),
                        DropdownOption(value: 'inactive', label: 'Inactive'),
                        DropdownOption(value: 'blocked', label: 'Blocked'),
                      ],
                      value: _status,
                      onChanged: (String? value) =>
                          setState(() => _status = value ?? 'active'),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: <Widget>[
                    _field('notes', 'Notes', maxLines: 9),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(String key, String label,
      {String? Function(String?)? validator,
      TextInputType? keyboardType,
      int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppTextField(
        controller: _fields[key],
        label: label,
        validator: validator,
        keyboardType: keyboardType,
        maxLines: maxLines,
      ),
    );
  }

  Future<void> _submit(bool isEdit, String? id) async {
    if (!_formKey.currentState!.validate()) return;
    _saving.value = true;
    final Map<String, dynamic> payload = <String, dynamic>{
      'name': _fields['name']!.text.trim(),
      'phone': _fields['phone']!.text.trim(),
      'alternate_phone': _fields['alternatePhone']!.text.trim(),
      'email': _fields['email']!.text.trim(),
      'address': _fields['address']!.text.trim(),
      'city': _fields['city']!.text.trim(),
      'state': _fields['state']!.text.trim(),
      'pincode': _fields['pincode']!.text.trim(),
      'customer_type': _type,
      'notes': _fields['notes']!.text.trim(),
      'status': _status,
    };
    try {
      final bool ok = await controller.saveCustomer(payload, id: id);
      if (ok) {
        AppSnackbar.success(context,
            '${controller.connectivity.isOnline ? 'Saved' : 'Saved offline — will sync'}');
        Get.back();
        controller.refresh();
      }
    } on AppException catch (e) {
      AppSnackbar.error(context, e.message);
    } catch (e) {
      AppSnackbar.error(context, ErrorMapper.friendly(e));
    } finally {
      _saving.value = false;
    }
  }
}
