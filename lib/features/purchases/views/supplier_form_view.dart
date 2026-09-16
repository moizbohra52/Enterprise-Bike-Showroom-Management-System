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
import 'package:enterprise_bike_showroom/features/purchases/controllers/purchase_controller.dart';
import 'package:enterprise_bike_showroom/features/purchases/models/purchase_models.dart';
import 'package:enterprise_bike_showroom/features/purchases/repositories/purchase_repository.dart';

/// Add / edit supplier.
class SupplierFormView extends GetView<SupplierController> {
  // Not const: this widget owns mutable state (Rx / TextEditingController),
  // and a const constructor cannot have initialized instance fields.
  SupplierFormView({super.key});

  @override
  Widget build(BuildContext context) {
    final String? id = Get.parameters['id'] ?? _pathId();
    final bool isEdit = id != null;
    final RxBool saving = _saving;
    final PurchaseRepository repository = Get.find<PurchaseRepository>();

    return AppShell(
      title: isEdit ? 'Edit Supplier' : 'Add Supplier',
      showBack: true,
      actions: <Widget>[
        Obx(
          () => AppButton(
            label: isEdit ? 'Save Changes' : 'Create Supplier',
            icon: Icons.save_outlined,
            isLoading: saving.value,
            onPressed: saving.value ? null : () => _submit(context, isEdit, id),
          ),
        ),
      ],
      child: FutureCache<SupplierModel?>(
        future: () => isEdit ? repository.supplierById(id!) : Future.value(null),
        builder: (BuildContext context, AsyncSnapshot<SupplierModel?> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          _apply(snapshot.data);
          return _form();
        },
      ),
    );
  }

  String? _pathId() {
    final String? name = Get.currentRoute;
    if (name != null) {
      final List<String> parts = name.split('/');
      if (parts.isNotEmpty) return parts.last;
    }
    return null;
  }

  final RxBool _saving = false.obs;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _fields = <String, TextEditingController>{
    'name': TextEditingController(),
    'contact': TextEditingController(),
    'phone': TextEditingController(),
    'altPhone': TextEditingController(),
    'email': TextEditingController(),
    'address': TextEditingController(),
    'city': TextEditingController(),
    'state': TextEditingController(),
    'pincode': TextEditingController(),
    'gstin': TextEditingController(),
    'terms': TextEditingController(text: '30'),
    'notes': TextEditingController(),
  };

  String _status = 'active';

  void _apply(SupplierModel? s) {
    if (s == null) return;
    _fields['name']?.text = s.name;
    _fields['contact']?.text = s.contactPerson;
    _fields['phone']?.text = s.phone;
    _fields['altPhone']?.text = s.alternatePhone;
    _fields['email']?.text = s.email;
    _fields['address']?.text = s.address;
    _fields['city']?.text = s.city;
    _fields['state']?.text = s.state;
    _fields['pincode']?.text = s.pincode;
    _fields['gstin']?.text = s.gstin;
    _fields['terms']?.text = '${s.paymentTermsDays}';
    _fields['notes']?.text = s.notes;
    _status = s.status;
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
                    _field('name', 'Supplier Name *',
                        validator: (String? v) =>
                            AppValidators.required(v, message: 'Name is required.')),
                    _field('contact', 'Contact Person'),
                    _field('phone', 'Phone *',
                        keyboardType: TextInputType.phone,
                        validator: (String? v) => AppValidators.phone(v)),
                    _field('altPhone', 'Alternate Phone',
                        keyboardType: TextInputType.phone),
                    _field('email', 'Email',
                        keyboardType: TextInputType.emailAddress,
                        validator: (String? v) => AppValidators.email(v)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: <Widget>[
                    _field('address', 'Address', maxLines: 2),
                    _field('city', 'City'),
                    _field('state', 'State'),
                    _field('pincode', 'Pincode',
                        keyboardType: TextInputType.number,
                        validator: (String? v) => AppValidators.pincode(v)),
                    _field('gstin', 'GSTIN',
                        validator: (String? v) => AppValidators.gst(v)),
                    _field('terms', 'Payment terms (days)',
                        keyboardType: TextInputType.number),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: <Widget>[
                    AppDropdown<String>(
                      label: 'Status',
                      options: const <DropdownOption<String>>[
                        DropdownOption(value: 'active', label: 'Active'),
                        DropdownOption(value: 'inactive', label: 'Inactive'),
                      ],
                      value: _status,
                      onChanged: (String? value) =>
                          setState(() => _status = value ?? 'active'),
                    ),
                    const SizedBox(height: 12),
                    _field('notes', 'Notes', maxLines: 8),
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

  Future<void> _submit(BuildContext context, bool isEdit, String? id) async {
    if (!_formKey.currentState!.validate()) return;
    _saving.value = true;
    final Map<String, dynamic> payload = <String, dynamic>{
      'name': _fields['name']!.text.trim(),
      'contact_person': _fields['contact']!.text.trim(),
      'phone': _fields['phone']!.text.trim(),
      'alternate_phone': _fields['altPhone']!.text.trim(),
      'email': _fields['email']!.text.trim(),
      'address': _fields['address']!.text.trim(),
      'city': _fields['city']!.text.trim(),
      'state': _fields['state']!.text.trim(),
      'pincode': _fields['pincode']!.text.trim(),
      'gstin': _fields['gstin']!.text.trim().toUpperCase(),
      'payment_terms_days': int.tryParse(_fields['terms']!.text) ?? 30,
      'notes': _fields['notes']!.text.trim(),
      'status': _status,
    };
    final PurchaseRepository repository = Get.find<PurchaseRepository>();
    try {
      if (id != null) {
        await repository.updateSupplier(id, payload);
      } else {
        await repository.createSupplier(payload);
      }
      AppSnackbar.success(context, 'Saved');
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
