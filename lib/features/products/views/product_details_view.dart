import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_dialog.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_image.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_loader.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_snackbar.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_status_chip.dart';
import 'package:enterprise_bike_showroom/core/helpers/formatters.dart';
import 'package:enterprise_bike_showroom/features/products/controllers/product_controller.dart';
import 'package:enterprise_bike_showroom/features/products/models/product_models.dart';

/// Product details: specs, colors, images, pricing.
class ProductDetailsView extends GetView<ProductDetailsController> {
  const ProductDetailsView({super.key});

  @override
  Widget build(BuildContext context) {
    final String? id = Get.parameters['id'];
    if (id == null) {
      return AppShell(
          title: 'Product', showBack: true, child: const AppLoader());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.load(id));

    return AppShell(
      title: 'Product Details',
      showBack: true,
      actions: <Widget>[
        AppButton(
          label: 'Edit',
          icon: Icons.edit_outlined,
          variant: AppButtonVariant.outlined,
          onPressed: () async {
            final ProductController list = Get.find<ProductController>();
            await list.openForm(id: id);
            controller.load(id);
          },
        ),
      ],
      child: Obx(() {
        if (controller.isLoading.value || controller.product.value == null) {
          return const AppLoader();
        }
        final ProductModel product = controller.product.value!;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _gallery(product),
              const SizedBox(height: 12),
              AppCard(
                title: product.fullName,
                subtitle: product.brand?.name,
                actions: <Widget>[AppStatusChip(status: product.status)],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _specRow('Model', product.model),
                    _specRow('Variant', product.variant),
                    _specRow('Category', product.category),
                    _specRow('Engine', product.engineCc == null ? '-' : '${product.engineCc} cc'),
                    _specRow('Fuel Type', product.fuelType),
                    _specRow('Transmission', product.transmission),
                    _specRow('Mileage', product.mileage == null ? '-' : '${product.mileage} km/l'),
                    const Divider(height: 20),
                    _specRow('Base Price', product.basePrice.currency),
                    _specRow('Selling Price', product.sellingPrice.currency, bold: true),
                    _specRow('Tax Rate', '${product.taxRate} %'),
                    _specRow('Warranty', '${product.warrantyMonths} months'),
                    _specRow('Created', AppFormatters.date(product.createdAt)),
                    _specRow('Updated', AppFormatters.date(product.updatedAt)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              AppCard(
                title: 'Description',
                child: Text(
                  product.description.isEmpty
                      ? 'No description.'
                      : product.description,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 12),
              AppCard(
                title: 'Actions',
                child: Row(
                  children: <Widget>[
                    AppButton(
                      label: 'Deactivate',
                      icon: Icons.block,
                      variant: AppButtonVariant.outlined,
                      onPressed: () => _confirmDeactivate(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _gallery(ProductModel product) {
    final images = product.images;
    if (images.isEmpty) {
      return AppCard(
        title: 'Images',
        child: const SizedBox(
          height: 120,
          child: Center(
            child: Icon(Icons.image_outlined, size: 40, color: Colors.grey),
          ),
        ),
      );
    }
    return AppCard(
      title: 'Images (${images.length})',
      child: SizedBox(
        height: 180,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: images.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (BuildContext context, int index) {
            final ProductImageModel image = images[index];
            return Stack(
              children: <Widget>[
                AppImage(
                  url: image.thumbnailUrl ?? image.imageUrl,
                  width: 160,
                  height: 120,
                ),
                if (image.isPrimary)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Chip(
                      label: const Text('Primary', style: TextStyle(fontSize: 10)),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _specRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 140,
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: bold ? FontWeight.w600 : FontWeight.w400),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeactivate(BuildContext context) async {
    final bool confirmed = await AppDialog.confirm(
      context,
      title: 'Deactivate product?',
      message: 'The product will be hidden from new sales but kept for history.',
      confirmLabel: 'Deactivate',
      destructive: true,
    );
    if (!confirmed) return;
    final bool ok = await controller.delete();
    if (ok) {
      AppSnackbar.success(context, 'Product deactivated');
      Get.back();
    } else {
      AppSnackbar.error(context, 'Could not deactivate the product.');
    }
  }
}
