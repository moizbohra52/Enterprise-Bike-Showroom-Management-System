import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_date_picker.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_dropdown.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_snackbar.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_text_field.dart';
import 'package:enterprise_bike_showroom/common/models/dropdown_option.dart';
import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/validators/validators.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/inventory/controllers/inventory_controller.dart';
import 'package:enterprise_bike_showroom/features/inventory/repositories/inventory_repository.dart';
import 'package:enterprise_bike_showroom/features/inventory/models/inventory_models.dart';
import 'package:enterprise_bike_showroom/features/products/controllers/product_controller.dart';

/// Stock-in: add a physical bike to inventory.
class StockInView extends StatefulWidget {
  StockInView({super.key});

  @override
  State<StockInView> createState() => _StockInViewState();
}

class _StockInViewState extends State<StockInView> {
  InventoryController get controller => Get.find<InventoryController>();

  @override
  Widget build(BuildContext context) {
    final RxBool saving = _saving;
    return AppShell(
      title: 'Stock In',
      showBack: true,
      actions: <Widget>[
        Obx(
          () => AppButton(
            label: 'Add to Stock',
            icon: Icons.check,
            isLoading: saving.value,
            onPressed: saving.value ? null : () => _submit(context),
          ),
        ),
      ],
      child: _form(),
    );
  }

  final RxBool _saving = false.obs;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _fields = <String, TextEditingController>{
    'stockCode': TextEditingController(),
    'chassis': TextEditingController(),
    'engine': TextEditingController(),
    'purchasePrice': TextEditingController(),
    'location': TextEditingController(),
  };

  String? _productId;
  String? _colorId;
  DateTime? _manufacturingDate;
  DateTime? _purchaseDate;
  int? _modelYear;

  List<DropdownOption<String?>> get _productOptions {
    final ProductController products = Get.find<ProductController>();
    return <DropdownOption<String?>>[
      const DropdownOption<String?>(value: null, label: 'Select product'),
      for (final dynamic p in products.items.value)
        if (p.id != null)
          DropdownOption<String?>(value: p.id, label: p.fullName),
    ];
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
                    AppDropdown<String?>(
                      label: 'Product *',
                      options: _productOptions,
                      value: _productId,
                      onChanged: (String? value) {
                        setState(() {
                          _productId = value;
                          _colorId = null;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Obx(
                      () => AppDropdown<String?>(
                        label: 'Color',
                        options: _colorOptions,
                        value: _colorId,
                        onChanged: (String? value) =>
                            setState(() => _colorId = value),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AppTextField(
                        label: 'Stock Code',
                        controller: _fields['stockCode'],
                        hint: 'Auto-generated if blank',
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AppTextField(
                        label: 'Chassis Number *',
                        controller: _fields['chassis'],
                        validator: (String? v) => AppValidators.chassisNumber(v),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AppTextField(
                        label: 'Engine Number *',
                        controller: _fields['engine'],
                        validator: (String? v) => AppValidators.engineNumber(v),
                      ),
                    ),
                    AppDatePicker(
                      label: 'Manufacturing Date',
                      value: _manufacturingDate,
                      onChanged: (DateTime? d) =>
                          setState(() => _manufacturingDate = d),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AppTextField(
                        label: 'Model Year',
                        keyboardType: TextInputType.number,
                        onChanged: (String v) =>
                            setState(() => _modelYear = int.tryParse(v)),
                      ),
                    ),
                    AppDatePicker(
                      label: 'Purchase Date',
                      value: _purchaseDate,
                      onChanged: (DateTime? d) =>
                          setState(() => _purchaseDate = d),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AppTextField(
                        label: 'Purchase Price *',
                        prefixText: '\u20B9',
                        keyboardType: TextInputType.number,
                        controller: _fields['purchasePrice'],
                        validator: (String? v) =>
                            AppValidators.required(v, message: 'Required.'),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AppTextField(
                        label: 'Location (floor / bay)',
                        controller: _fields['location'],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<DropdownOption<String?>> get _colorOptions {
    final ProductController products = Get.find<ProductController>();
    for (final dynamic p in products.items.value) {
      if (p.id == _productId) {
        return <DropdownOption<String?>>[
          const DropdownOption<String?>(value: null, label: 'Select color'),
          for (final dynamic c in p.colors)
            if (c.id != null)
              DropdownOption<String?>(value: c.id, label: c.colorName),
        ];
      }
    }
    return <DropdownOption<String?>>[
      const DropdownOption<String?>(value: null, label: 'Select product first'),
    ];
  }

  Future<void> _submit(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;
    if (_productId == null) {
      AppSnackbar.error(context, 'Please select a product.');
      return;
    }
    _saving.value = true;
    try {
      final SessionController session = Get.find<SessionController>();
      final InventoryRepository repository = Get.find<InventoryRepository>();
      final dynamic product = Get.find<ProductController>()
          .items
          .value
          .firstWhere((dynamic p) => p.id == _productId);
      final String stockCode = _fields['stockCode']!.text.trim().isNotEmpty
          ? _fields['stockCode']!.text.trim().toUpperCase()
          : 'STK-${DateTime.now().year}'
              '${DateTime.now().month.toString().padLeft(2, '0')}'
              '${DateTime.now().day.toString().padLeft(2, '0')}-'
              '${DateTime.now().millisecondsSinceEpoch % 10000}';
      final InventoryModel created = await repository.stockIn(<String, dynamic>{
        'showroom_id': session.activeShowroomId,
        'product_id': _productId,
        'color_id': _colorId,
        'stock_code': stockCode,
        'chassis_number': _fields['chassis']!.text.trim().toUpperCase(),
        'engine_number': _fields['engine']!.text.trim().toUpperCase(),
        'manufacturing_date':
            _manufacturingDate?.toIso8601String(),
        'model_year': _modelYear,
        'purchase_date': _purchaseDate?.toIso8601String(),
        'purchase_price':
            double.tryParse(_fields['purchasePrice']!.text) ?? 0,
        'location': _fields['location']!.text.trim(),
        'status': 'available',
      });
      // ignore: unused_local_variable
      final _ = product;
      AppSnackbar.success(context, 'Bike added to stock: ${created.stockCode}');
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
