import 'package:flutter/material.dart';

import 'avatar_image.dart';

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
    super.key,
    required this.color,
    required this.category,
    required this.title,
    required this.timeRange,
    required this.participants,
    this.subtitle,
    this.trailingIcon,
    this.onTap,
  });

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
            color: Colors.black.withValues(alpha: 0.05),
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
              ?trailingIcon,
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (participants.isNotEmpty) ..._buildParticipantAvatars(),
              if (participants.isNotEmpty && subtitle != null)
                const SizedBox(width: 8),
              if (subtitle != null)
                Flexible(
                  child: Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
    const double overlap = 10;

    final visibleParticipants = participants.take(2).toList();
    final remainingCount = participants.length - visibleParticipants.length;

    final List<Widget> widgets = [];

    for (int i = 0; i < visibleParticipants.length; i++) {
      final imageUrl = visibleParticipants[i];

      widgets.add(
        Transform.translate(
          offset: Offset(i == 0 ? 0 : -overlap, 0),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipOval(child: AvatarImage(imageUrl: imageUrl)),
          ),
        ),
      );
    }

    if (remainingCount > 0) {
      widgets.add(
        Transform.translate(
          offset: const Offset(-6, 0),
          child: Text(
            '+$remainingCount',
            style: TextStyle(
              color: _fadedColorFor(color),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return widgets;
  }

  Color _fadedColorFor(Color c) {
    return c.computeLuminance() > 0.5 ? Colors.black54 : Colors.white70;
  }

  Color _primaryTextColorFor(Color c) {
    return c.computeLuminance() > 0.5 ? Colors.black : Colors.white;
  }
}
