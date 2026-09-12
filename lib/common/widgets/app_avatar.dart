import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:enterprise_bike_showroom/core/extensions/string_extensions.dart';

/// Circular avatar with initials fallback.
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    this.name,
    this.imageUrl,
    this.size = 40,
  });

  final String? name;
  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final String? url =
        (imageUrl == null || imageUrl!.isEmpty) ? null : imageUrl;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: url != null
            ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                errorWidget: (BuildContext context, String _, dynamic __) =>
                    _initials(),
              )
            : _initials(),
      ),
    );
  }

  Widget _initials() {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      color: colors.primary.withAlpha(60),
      alignment: Alignment.center,
      child: Text(
        (name ?? '?').initials,
        style: TextStyle(
          fontSize: size * 0.38,
          fontWeight: FontWeight.w600,
          color: colors.primary,
        ),
      ),
    );
  }
}
