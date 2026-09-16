import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_dropdown.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_image.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_loader.dart';
import 'package:enterprise_bike_showroom/common/widgets/future_cache.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_snackbar.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_text_field.dart';
import 'package:enterprise_bike_showroom/common/models/dropdown_option.dart';
import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/helpers/logger.dart';
import 'package:enterprise_bike_showroom/core/validators/validators.dart';
import 'package:enterprise_bike_showroom/features/products/controllers/product_controller.dart';
import 'package:enterprise_bike_showroom/features/products/models/product_models.dart';
import 'package:enterprise_bike_showroom/services/image_service.dart';

/// Add / edit product with colors + images.
class ProductFormView extends GetView<ProductController> {
  // Not const: this widget owns mutable state (Rx / TextEditingController),
  // and a const constructor cannot have initialized instance fields.
  ProductFormView({super.key});

  @override
  Widget build(BuildContext context) {
    final String? id = Get.parameters['id'];
    final bool isEdit = id != null;

    return AppShell(
      title: isEdit ? 'Edit Product' : 'Add Product',
      showBack: true,
      actions: <Widget>[
        Obx(
          () => AppButton(
            label: isEdit ? 'Save Changes' : 'Create Product',
            icon: Icons.save_outlined,
            isLoading: _saving.value,
            onPressed: _saving.value ? null : () => _submit(context, isEdit, id),
          ),
        ),
      ],
      child: FutureCache<void>(
        future: () => isEdit ? _load(id!) : Future.value(),
        builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoader();
          }
          return _form(context);
        },
      ),
    );
  }

  final RxBool _saving = false.obs;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final Map<String, TextEditingController> _fields = <String, TextEditingController>{
    'name': TextEditingController(),
    'model': TextEditingController(),
    'variant': TextEditingController(),
    'category': TextEditingController(),
    'engineCc': TextEditingController(),
    'fuelType': TextEditingController(),
    'transmission': TextEditingController(),
    'mileage': TextEditingController(),
    'basePrice': TextEditingController(),
    'sellingPrice': TextEditingController(),
    'taxRate': TextEditingController(text: '18'),
    'warrantyMonths': TextEditingController(text: '12'),
    'description': TextEditingController(),
  };

  String? _brandId;
  String _status = 'active';
  final List<_ColorRow> _colors = <_ColorRow>[
    _ColorRow('Red', '#C62828'),
    _ColorRow('Black', '#212121'),
  ];
  final List<_ProductImageRef> _pickedImages = <_ProductImageRef>[];
  final ImagePicker _picker = ImagePicker();

  Future<void> _load(String id) async {
    final ProductModel? product = await controller.repository.getById(id);
    if (product == null) return;
    _fields['name']?.text = product.name;
    _fields['model']?.text = product.model;
    _fields['variant']?.text = product.variant;
    _fields['category']?.text = product.category;
    _fields['engineCc']?.text = product.engineCc?.toString() ?? '';
    _fields['fuelType']?.text = product.fuelType;
    _fields['transmission']?.text = product.transmission;
    _fields['mileage']?.text = product.mileage?.toString() ?? '';
    _fields['basePrice']?.text = product.basePrice.toString();
    _fields['sellingPrice']?.text = product.sellingPrice.toString();
    _fields['taxRate']?.text = product.taxRate.toString();
    _fields['warrantyMonths']?.text = product.warrantyMonths.toString();
    _fields['description']?.text = product.description;
    _brandId = product.brandId;
    _status = product.status;
    if (product.colors.isNotEmpty) {
      _colors
        ..clear()
        ..addAll(product.colors.map((ProductColorModel c) => _ColorRow(c.colorName, c.hexCode)));
    }
  }

  Widget _form(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AppCard(
              title: 'Basic Details',
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        _field('name', 'Product Name *',
                            validator: (String? v) =>
                                AppValidators.required(v, message: 'Name is required.')),
                        _field('model', 'Model'),
                        _field('variant', 'Variant'),
                        _field('category', 'Category'),
                        _dropdown(
                          label: 'Brand *',
                          value: _brandId,
                          options: <DropdownOption<String?>>[
                            const DropdownOption<String?>(
                                value: null, label: 'Select brand'),
                            for (final BrandModel b in controller.brands.value)
                              DropdownOption<String?>(value: b.id, label: b.name),
                          ],
                          onChanged: (String? value) => setState(() => _brandId = value),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        _field('engineCc', 'Engine (cc)',
                            keyboardType: TextInputType.number),
                        _field('fuelType', 'Fuel Type'),
                        _field('transmission', 'Transmission'),
                        _field('mileage', 'Mileage (km/l)',
                            keyboardType: TextInputType.number),
                        _dropdown(
                          label: 'Status',
                          value: _status,
                          options: const <DropdownOption<String>>[
                            DropdownOption(value: 'active', label: 'Active'),
                            DropdownOption(value: 'inactive', label: 'Inactive'),
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
            const SizedBox(height: 12),
            AppCard(
              title: 'Pricing & Warranty',
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        _field('basePrice', 'Base Price *',
                            keyboardType: TextInputType.number,
                            validator: (String? v) =>
                                AppValidators.required(v, message: 'Required.')),
                        _field('sellingPrice', 'Selling Price *',
                            keyboardType: TextInputType.number,
                            validator: (String? v) =>
                                AppValidators.required(v, message: 'Required.')),
                        _field('taxRate', 'Tax Rate (%)',
                            keyboardType: TextInputType.number),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        _field('warrantyMonths', 'Warranty (months)',
                            keyboardType: TextInputType.number),
                        _field('description', 'Description', maxLines: 4),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AppCard(
              title: 'Colors',
              actions: <Widget>[
                AppButton(
                  label: 'Add',
                  icon: Icons.add,
                  variant: AppButtonVariant.text,
                  size: AppButtonSize.small,
                  onPressed: () => setState(
                      () => _colors.add(_ColorRow('', '#000000'))),
                ),
              ],
              child: Column(
                children: <Widget>[
                  for (int i = 0; i < _colors.length; i++)
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: AppTextField(
                              label: 'Color ${i + 1} name',
                              controller: _colors[i].name,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: AppTextField(
                              label: 'Hex code',
                              controller: _colors[i].hex,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: _colors.length > 1
                              ? () => setState(() => _colors.removeAt(i))
                              : null,
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AppCard(
              title: 'Images',
              actions: <Widget>[
                AppButton(
                  label: 'Pick',
                  icon: Icons.add_photo_alternate_outlined,
                  variant: AppButtonVariant.outlined,
                  size: AppButtonSize.small,
                  onPressed: () => _pickImages(context),
                ),
              ],
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  for (final _ProductImageRef ref in _pickedImages)
                    Stack(
                      children: <Widget>[
                        ref.path.startsWith('http')
                            ? AppImage(url: ref.path, width: 110, height: 80)
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.file(
                                  File(ref.path),
                                  width: 110,
                                  height: 80,
                                  fit: BoxFit.cover,
                                ),
                              ),
                        if (ref.isPrimary)
                          Positioned(
                            top: 4,
                            left: 4,
                            child: Chip(
                              label: const Text('Primary',
                                  style: TextStyle(fontSize: 10)),
                              padding: EdgeInsets.zero,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        Positioned(
                          top: -6,
                          right: -6,
                          child: IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () => setState(
                                () => _pickedImages.remove(ref)),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
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

  Widget _dropdown({
    required String label,
    required String? value,
    required List<DropdownOption<String?>> options,
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppDropdown<String?>(
        label: label,
        options: options,
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Future<void> _pickImages(BuildContext context) async {
    try {
      final List<XFile>? images =
          await _picker.pickMultiImage(imageQuality: 85);
      if (images == null || images.isEmpty) return;
      setState(() {
        for (final XFile file in images) {
          _pickedImages.add(_ProductImageRef(file.path, _pickedImages.isEmpty));
        }
      });
    } catch (e) {
      AppSnackbar.error(context, 'Could not pick images');
    }
  }

  Future<void> _submit(BuildContext context, bool isEdit, String? id) async {
    if (!_formKey.currentState!.validate()) return;
    if (_brandId == null) {
      AppSnackbar.error(context, 'Please select a brand.');
      return;
    }
    _saving.value = true;
    try {
      final num? engineCc = _fields['engineCc']!.text.isEmpty
          ? null
          : double.tryParse(_fields['engineCc']!.text);
      final num? mileage = _fields['mileage']!.text.isEmpty
          ? null
          : double.tryParse(_fields['mileage']!.text);

      final Map<String, dynamic> payload = <String, dynamic>{
        'brand_id': _brandId,
        'name': _fields['name']!.text.trim(),
        'model': _fields['model']!.text.trim(),
        'variant': _fields['variant']!.text.trim(),
        'category': _fields['category']!.text.trim(),
        'engine_cc': engineCc,
        'fuel_type': _fields['fuelType']!.text.trim(),
        'transmission': _fields['transmission']!.text.trim(),
        'mileage': mileage,
        'description': _fields['description']!.text.trim(),
        'base_price': double.tryParse(_fields['basePrice']!.text) ?? 0,
        'selling_price': double.tryParse(_fields['sellingPrice']!.text) ?? 0,
        'tax_rate': double.tryParse(_fields['taxRate']!.text) ?? 18,
        'warranty_months': int.tryParse(_fields['warrantyMonths']!.text) ?? 12,
        'status': _status,
      };

      ProductModel product;
      if (isEdit && id != null) {
        product = await controller.repository.update(id, payload);
        AppSnackbar.success(context, 'Product updated');
      } else {
        product = await controller.repository.create(payload);
        AppSnackbar.success(context, 'Product created');
      }

      // Colors
      await controller.repository.replaceColors(
        product.id ?? id!,
        <ProductColorModel>[
          for (final _ColorRow row in _colors)
            if (row.name.text.trim().isNotEmpty)
              ProductColorModel(
                productId: product.id ?? id!,
                colorName: row.name.text.trim(),
                hexCode: row.hex.text.trim(),
              ),
        ],
      );

      // Images (compress + upload to Supabase Storage)
      final ImageService imageService = Get.find<ImageService>();
      for (int i = 0; i < _pickedImages.length; i++) {
        final _ProductImageRef ref = _pickedImages[i];
        if (ref.path.startsWith('http')) {
          await controller.repository.upsertImage(ProductImageModel(
            productId: product.id ?? id!,
            imageUrl: ref.path,
            isPrimary: ref.isPrimary,
            sortOrder: i,
          ));
          continue;
        }
        try {
          final String path = await imageService.uploadProductImage(
            productId: product.id ?? id!,
            file: File(ref.path),
            index: i,
          );
          await controller.repository.upsertImage(ProductImageModel(
            productId: product.id ?? id!,
            imageUrl: path,
            isPrimary: ref.isPrimary,
            sortOrder: i,
          ));
        } catch (e) {
          AppLogger.warning('PRODUCTS', 'image upload failed', error: e);
        }
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

class _ColorRow {
  _ColorRow(String name, String hex)
      : name = TextEditingController(text: name),
        hex = TextEditingController(text: hex);

  final TextEditingController name;
  final TextEditingController hex;
}

/// A locally picked image (path + whether it is the primary photo).
class _ProductImageRef {
  _ProductImageRef(this.path, this.isPrimary);

  final String path;
  final bool isPrimary;
}
