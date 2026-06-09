import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../constants/default_avatar.dart';

ImageProvider avatarImageProvider(String imageUrl) {
  final source = imageUrl.trim().isEmpty ? DefaultAvatar.path : imageUrl.trim();
  if (source.startsWith('assets/')) {
    return AssetImage(source);
  }
  return CachedNetworkImageProvider(source);
}

class AvatarImage extends StatelessWidget {
  const AvatarImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.placeholderColor = const Color(0xFFF1F5F9),
  });

  final String imageUrl;
  final BoxFit fit;
  final Color placeholderColor;

  @override
  Widget build(BuildContext context) {
    final source = imageUrl.trim().isEmpty
        ? DefaultAvatar.path
        : imageUrl.trim();
    if (source.startsWith('assets/')) {
      return Image.asset(source, fit: fit);
    }

    return CachedNetworkImage(
      imageUrl: source,
      fit: fit,
      placeholder: (context, url) => ColoredBox(color: placeholderColor),
      errorWidget: (context, url, error) {
        return Image.asset(DefaultAvatar.path, fit: fit);
      },
    );
  }
}
