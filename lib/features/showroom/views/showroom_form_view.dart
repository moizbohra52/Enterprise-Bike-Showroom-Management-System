import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_snackbar.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_text_field.dart';
import 'package:enterprise_bike_showroom/common/widgets/future_cache.dart';
import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/validators/validators.dart';
import 'package:enterprise_bike_showroom/common/models/showroom_model.dart';
import 'package:enterprise_bike_showroom/features/showroom/controllers/showroom_controller.dart';

/// Add / edit showroom form.
class ShowroomFormView extends GetView<ShowroomController> {
  // Not const: this widget owns mutable state (Rx / TextEditingController),
  // and a const constructor cannot have initialized instance fields.
  ShowroomFormView({super.key});

  @override
  Widget build(BuildContext context) {
    final String? id = Get.parameters['id'];
    final bool isEdit = id != null;

    return AppShell(
      title: isEdit ? 'Edit Showroom' : 'Add Showroom',
      showBack: true,
      actions: <Widget>[
        Obx(
          () => AppButton(
            label: isEdit ? 'Save Changes' : 'Create Showroom',
            icon: Icons.save_outlined,
            isLoading: _saving.value,
            onPressed: _saving.value ? null : () => _submit(context, isEdit, id),
          ),
        ),
      ],
      child: _form(isEdit),
    );
  }

  final RxBool _saving = false.obs;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _fields = <String, TextEditingController>{
    'name': TextEditingController(),
    'code': TextEditingController(),
    'address': TextEditingController(),
    'city': TextEditingController(),
    'state': TextEditingController(),
    'pincode': TextEditingController(),
    'phone': TextEditingController(),
    'email': TextEditingController(),
    'gstNumber': TextEditingController(),
    'panNumber': TextEditingController(),
    'invoicePrefix': TextEditingController(text: 'INV'),
  };
  String _status = 'active';

  Future<void> _load(ShowroomRepository repository, String id) async {
    final ShowroomModel? showroom = await repository.getById(id);
    if (showroom == null) return;
    _fields['name']?.text = showroom.name;
    _fields['code']?.text = showroom.code;
    _fields['address']?.text = showroom.address;
    _fields['city']?.text = showroom.city;
    _fields['state']?.text = showroom.state;
    _fields['pincode']?.text = showroom.pincode;
    _fields['phone']?.text = showroom.phone;
    _fields['email']?.text = showroom.email;
    _fields['gstNumber']?.text = showroom.gstNumber;
    _fields['panNumber']?.text = showroom.panNumber;
    _fields['invoicePrefix']?.text = showroom.invoicePrefix;
    _status = showroom.status;
  }

  Widget _form(bool isEdit) {
    return FutureCache<void>(
      future: () =>
          isEdit ? _load(controller.repository, Get.parameters['id']!) : Future.value(),
      builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
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
                        _field('name', 'Name *',
                            validator: (String? v) =>
                                AppValidators.required(v, message: 'Name is required.')),
                        _field('code', 'Code * (e.g. HSR-001)',
                            validator: (String? v) =>
                                AppValidators.required(v, message: 'Code is required.')),
                        _field('address', 'Address'),
                        _field('city', 'City'),
                        _field('state', 'State'),
                        _field('pincode', 'Pincode',
                            keyboardType: TextInputType.number,
                            validator: (String? v) => AppValidators.pincode(v)),
                        _field('phone', 'Phone',
                            keyboardType: TextInputType.phone),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        _field('email', 'Email',
                            keyboardType: TextInputType.emailAddress,
                            validator: (String? v) => AppValidators.email(v)),
                        _field('gstNumber', 'GST Number',
                            validator: (String? v) => AppValidators.gst(v)),
                        _field('panNumber', 'PAN Number',
                            validator: (String? v) => AppValidators.pan(v)),
                        _field('invoicePrefix', 'Invoice Prefix'),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: _status,
              decoration: const InputDecoration(labelText: 'Status'),
                          items: const <DropdownMenuItem<String>>[
                            DropdownMenuItem(value: 'active', child: Text('Active')),
                            DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                          ],
                          onChanged: (String? value) =>
                              setState(() => _status = value ?? 'active'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _field(String key, String label,
      {String? Function(String?)? validator,
      TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppTextField(
        controller: _fields[key],
        label: label,
        validator: validator,
        keyboardType: keyboardType,
      ),
    );
  }

  Future<void> _submit(BuildContext context, bool isEdit, String? id) async {
    if (!_formKey.currentState!.validate()) return;
    _saving.value = true;
    final Map<String, dynamic> payload = <String, dynamic>{
      'name': _fields['name']!.text.trim(),
      'code': _fields['code']!.text.trim().toUpperCase(),
      'address': _fields['address']!.text.trim(),
      'city': _fields['city']!.text.trim(),
      'state': _fields['state']!.text.trim(),
      'pincode': _fields['pincode']!.text.trim(),
      'phone': _fields['phone']!.text.trim(),
      'email': _fields['email']!.text.trim(),
      'gst_number': _fields['gstNumber']!.text.trim().toUpperCase(),
      'pan_number': _fields['panNumber']!.text.trim().toUpperCase(),
      'invoice_prefix': _fields['invoicePrefix']!.text.trim().toUpperCase(),
      'status': _status,
    };
    try {
      if (isEdit && id != null) {
        await controller.repository.update(id, payload);
        AppSnackbar.success(context, 'Showroom updated');
      } else {
        await controller.repository.create(payload);
        AppSnackbar.success(context, 'Showroom created');
      }
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
