import 'package:flutter/material.dart';

import '../assets/figma_assets.dart';

class EventCard extends StatelessWidget {
  final Color color;
  final String category;
  final String title;
  final String timeRange;
  final List<String> participants;
  final String? subtitle;
  final Widget? trailingIcon;
  final VoidCallback? onTap;

  const EventCard({
    Key? key,
    required this.color,
    required this.category,
    required this.title,
    required this.timeRange,
    required this.participants,
    this.subtitle,
    this.trailingIcon,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final card = Container(
      constraints: const BoxConstraints(maxWidth: 282),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.toUpperCase(),
                      style: TextStyle(
                        color: _fadedColorFor(color),
                        fontSize: 12,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      style: TextStyle(
                        color: _primaryTextColorFor(color),
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      timeRange,
                      style: TextStyle(
                        color: _fadedColorFor(color),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailingIcon != null) trailingIcon!,
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ..._buildParticipantAvatars(),
              if (subtitle != null) const SizedBox(width: 8),
              if (subtitle != null)
                Flexible(
                  child: Text(
                    subtitle!,
                    style: TextStyle(
                      color: _fadedColorFor(color),
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );

    if (onTap == null) return card;

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: card,
    );
  }

  List<Widget> _buildParticipantAvatars() {
    const double size = 32;
    List<Widget> widgets = [];
    for (var i = 0; i < participants.length; i++) {
      // if a URL was provided, skip it since we no longer load network images
      widgets.add(
        Container(
          width: size,
          height: size,
          margin: EdgeInsets.only(left: i == 0 ? 0 : 0),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Icon(Icons.person, size: 18, color: Colors.grey),
          ),
        ),
      );
    }
    return widgets;
  }

  ImageProvider? _tryNetworkImage(String url) {
    try {
      return NetworkImage(url);
    } catch (_) {
      return null;
    }
  }

  String _participantAvatarUrl(String name) {
    switch (name) {
      case 'Mom':
        return FigmaAssets.familyImgMom;
      case 'Dad':
        return FigmaAssets.familyImgDad;
      case 'Sister':
        return FigmaAssets.familyImgUncleArthur;
      case 'Brother':
        return FigmaAssets.familyImgCousinSarah;
      default:
        return FigmaAssets.familyImgMom;
    }
  }

  Color _fadedColorFor(Color c) {
    return c.computeLuminance() > 0.5 ? Colors.black54 : Colors.white70;
  }

  Color _primaryTextColorFor(Color c) {
    return c.computeLuminance() > 0.5 ? Colors.black : Colors.white;
  }
}
