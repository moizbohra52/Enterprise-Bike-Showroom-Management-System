import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Network image with caching, lazy placeholder and error fallback.
///
/// For private Supabase storage, pass a signed URL (see
/// `StorageService.displayUrl`).
class AppImage extends StatelessWidget {
  const AppImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.radius = 10,
    this.errorIcon = Icons.broken_image_outlined,
    this.showWatermark = false,
  });

  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double radius;
  final IconData errorIcon;

  /// Overlays a "watermark" badge (display restriction hint).
  final bool showWatermark;

  @override
  Widget build(BuildContext context) {
    final Color placeholder = Theme.of(context).colorScheme.primary.withAlpha(40);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: (url == null || url!.isEmpty)
            ? _placeholder(placeholder)
            : Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  CachedNetworkImage(
                    imageUrl: url!,
                    fit: fit,
                    placeholder: (BuildContext context, String _) =>
                        _placeholder(placeholder),
                    errorWidget: (BuildContext context, String _, dynamic __) =>
                        _placeholder(placeholder, icon: errorIcon),
                  ),
                  if (showWatermark)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'WATERMARKED',
                          style: TextStyle(
                              fontSize: 8, color: Colors.white, letterSpacing: 0.6),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _placeholder(Color color, {IconData? icon}) {
    return Container(
      color: color,
      alignment: Alignment.center,
      child: Icon(icon ?? Icons.image_outlined,
          size: 28, color: Colors.grey.shade500),
    );
  }
}
