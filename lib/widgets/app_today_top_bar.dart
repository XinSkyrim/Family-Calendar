import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../screens/notifications_screen.dart';
import '../themes/app_theme.dart';
import '../services/user_profile_service.dart';

class AppTodayTopBar extends StatelessWidget {
  final String title;
  final bool showNotifications;

  const AppTodayTopBar({
    Key? key,
    required this.title,
    this.showNotifications = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 16),
      decoration: const BoxDecoration(
        color: AppTheme.headerBackground,
        boxShadow: [AppTheme.headerShadow],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const _HeaderAvatar(),
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppTheme.headline,
              letterSpacing: -0.5,
            ),
          ),
          showNotifications
              ? const _NotificationsButton()
              : const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _HeaderAvatar extends StatelessWidget {
  const _HeaderAvatar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UserProfile>(
      valueListenable: UserProfileService.profile,
      builder: (context, profile, child) {
        return Row(children: [_buildAvatar(profile.photoUrl)]);
      },
    );
  }

  Widget _buildAvatar(String imageUrl) {
    final hasImage = imageUrl.isNotEmpty;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: hasImage
            ? CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: const Color(0xFFF1F5F9),
                ),
                errorWidget: (context, url, error) => Container(
                  color: const Color(0xFFF1F5F9),
                  child: const Icon(
                    Icons.person,
                    size: 18,
                    color: Colors.grey,
                  ),
                ),
              )
            : Container(
                color: const Color(0xFFF1F5F9),
                child: const Icon(Icons.person, size: 18, color: Colors.grey),
              ),
      ),
    );
  }
}

class _NotificationsButton extends StatelessWidget {
  const _NotificationsButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.5),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: const Center(
              child: Icon(Icons.notifications, size: 18, color: AppTheme.headline),
            ),
          ),
          if (user != null)
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('notifications')
                  .where('recipientId', isEqualTo: user.uid)
                  .where('isRead', isEqualTo: false)
                  .snapshots(),
              builder: (context, snapshot) {
                final count = snapshot.data?.docs.length ?? 0;
                if (count == 0) return const SizedBox.shrink();

                return Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: const BoxDecoration(
                      color: Color(0xFFEF4444),
                      borderRadius: BorderRadius.all(Radius.circular(999)),
                    ),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
