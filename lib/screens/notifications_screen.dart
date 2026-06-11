import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/task_invitation_service.dart';
import '../services/family_invitation_service.dart';
import '../themes/app_theme.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  static const _primaryColor = Color(0xFF0F172A);
  static const _mutedColor = Color(0xFF64748B);
  static const _accentColor = Color(0xFFE2B736);

  @override
  Widget build(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppTheme.pageBackground,
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: statusBarHeight,
            child: const ColoredBox(color: AppTheme.headerBackground),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildAppBar(context),
                Expanded(child: _buildBody(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      decoration: const BoxDecoration(
        color: Color(0xFFF8F7F6),
      ),
      child: Row(
        children: [
          Material(
            color: const Color(0xFFF3EEE0),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(context).pop(),
              child: const SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: Icon(
                    Icons.arrow_back_ios_new,
                    size: 18,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Notifications',
              textAlign: TextAlign.center,
              style: AppTheme.headlineStyle,
            ),
          ),
          Material(
            color: const Color(0xFFF1F5F9),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () {},
              child: const SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: Icon(
                    Icons.settings,
                    size: 20,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Center(child: Text('Please sign in first.'));
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('recipientId', isEqualTo: user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Failed to load notifications.'));
        }

        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = [
          ...(snapshot.data?.docs ??
              const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
        ]..sort((a, b) {
          final aTime = a.data()['createdAt'];
          final bTime = b.data()['createdAt'];
          final aDate = aTime is Timestamp
              ? aTime.toDate()
              : DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = bTime is Timestamp
              ? bTime.toDate()
              : DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        });

        if (docs.isEmpty) {
          return const Center(child: Text('No notifications yet.'));
        }

        final sections = _groupNotificationsByDate(docs);

        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          children: [
            for (final section in sections) ...[
              _buildSectionHeader(section.label),
              const SizedBox(height: 16),
              ...section.docs.map((doc) => _buildNotificationCard(context, doc)),
              const SizedBox(height: 24),
            ],
          ],
        );
      },
    );
  }

  Widget _buildNotificationCard(
      BuildContext context,
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data();

    final type = (data['type'] ?? '').toString();
    final title = (data['title'] ?? 'Notification').toString();
    final message = (data['message'] ?? '').toString();
    final eventTitle = (data['eventTitle'] ?? '').toString();
    final senderName = (data['senderName'] ?? '').toString();
    final familyName = (data['familyName'] ?? '').toString();
    final eventId = (data['eventId'] ?? '').toString();
    final status = (data['status'] ?? '').toString();
    final isRead = data['isRead'] == true;

    final createdAt =
    data['createdAt'] is Timestamp ? (data['createdAt'] as Timestamp).toDate() : null;

    final isTaskInvitation = type == 'task_invitation' && status == 'pending';
    final isFamilyInvitation = type == 'family_invitation' && status == 'pending';
    final isInvitation = isTaskInvitation || isFamilyInvitation;

    final displayText = message.isNotEmpty
        ? message
        : isTaskInvitation
            ? '${senderName.isEmpty ? 'Someone' : senderName} wants to join the ${familyName.isEmpty ? 'family' : familyName} family group.'
            : isFamilyInvitation
                ? '${senderName.isEmpty ? 'Someone' : senderName} wants to join the ${familyName.isEmpty ? 'family' : familyName} family group.'
                : '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () async {
          if (!isRead) {
            await TaskInvitationService.markAsRead(doc.id);
          }
        },
        child: Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFF1F5F9)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D000000),
                blurRadius: 20,
                spreadRadius: -2,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (isInvitation)
                    _buildInvitationAvatar(type)
                  else
                    _buildNotificationIcon(type),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: _primaryColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          displayText,
                          style: const TextStyle(
                            color: _mutedColor,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (createdAt != null) ...[
                const SizedBox(height: 12),
                Text(
                  DateFormat('MMM d, HH:mm').format(createdAt),
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                  ),
                ),
              ],
              if (isInvitation) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    SizedBox(
                      width: 91,
                      height: 40,
                      child: Material(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(24),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: () => isTaskInvitation
                              ? _respondTask(
                                  context,
                                  notificationId: doc.id,
                                  eventId: eventId,
                                  accepted: false,
                                )
                              : _respondFamily(
                                  context,
                                  notificationId: doc.id,
                                  accepted: false,
                                ),
                          child: const Center(
                            child: Text(
                              'Refuse',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 91,
                      height: 40,
                      child: Material(
                        color: _accentColor,
                        borderRadius: BorderRadius.circular(24),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: () => isTaskInvitation
                              ? _respondTask(
                                  context,
                                  notificationId: doc.id,
                                  eventId: eventId,
                                  accepted: true,
                                )
                              : _respondFamily(
                                  context,
                                  notificationId: doc.id,
                                  accepted: true,
                                ),
                          child: const Center(
                            child: Text(
                              'Accept',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationIcon(String type) {
    IconData icon;
    Color background;

    switch (type) {
      case 'task_invitation':
      case 'task_invitation_sent':
        icon = Icons.assignment;
        background = const Color(0xFFDBA21F);
        break;
      case 'task_invitation_accepted':
        icon = Icons.check_circle;
        background = const Color(0xFF16A34A);
        break;
      case 'task_invitation_declined':
        icon = Icons.cancel;
        background = const Color(0xFFDC2626);
        break;
      case 'family_invitation':
      case 'family_invitation_accepted':
        icon = Icons.group_add;
        background = const Color(0xFF6366F1);
        break;
      default:
        icon = Icons.notifications;
        background = const Color(0xFF64748B);
    }

    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Center(
        child: Icon(
          icon,
          size: 24,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildInvitationAvatar(String type) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFFE2B736),
            borderRadius: BorderRadius.circular(28),
          ),
          child: const Center(
            child: Icon(
              Icons.person,
              size: 28,
              color: Colors.white,
            ),
          ),
        ),
        Positioned(
          right: -4,
          bottom: -4,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: const Color(0xFFE2B736),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Center(
              child: Icon(
                Icons.person_add,
                size: 10,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF94A3B8),
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
        ),
      ),
    );
  }

  List<_NotificationSection> _groupNotificationsByDate(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sections = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};

    for (final doc in docs) {
      final data = doc.data();
      final createdAt = data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : null;
      final label = createdAt == null ? 'Unknown' : _sectionLabelForDate(createdAt);
      sections.putIfAbsent(label, () => []).add(doc);
    }

    return sections.entries
        .map((entry) => _NotificationSection(label: entry.key, docs: entry.value))
        .toList();
  }

  String _sectionLabelForDate(DateTime date) {
    final now = DateTime.now();
    final localDate = DateTime(date.year, date.month, date.day);
    final today = DateTime(now.year, now.month, now.day);
    if (localDate == today) {
      return 'Today';
    }
    final yesterday = today.subtract(const Duration(days: 1));
    if (localDate == yesterday) {
      return 'Yesterday';
    }
    final suffix = _daySuffix(localDate.day);
    return '${DateFormat('MMM').format(localDate)} ${localDate.day}$suffix';
  }

  String _daySuffix(int day) {
    if (day >= 11 && day <= 13) {
      return 'th';
    }
    switch (day % 10) {
      case 1:
        return 'st';
      case 2:
        return 'nd';
      case 3:
        return 'rd';
      default:
        return 'th';
    }
  }

  Future<void> _respondTask(
      BuildContext context, {
        required String notificationId,
        required String eventId,
        required bool accepted,
      }) async {
    try {
      await TaskInvitationService.respondToInvitation(
        notificationId: notificationId,
        eventId: eventId,
        accepted: accepted,
      );

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(accepted ? 'Invitation accepted' : 'Invitation refused')),
      );
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Operation failed：$e')),
      );
    }
  }


  Future<void> _respondFamily(
      BuildContext context, {
        required String notificationId,
        required bool accepted,
      }) async {
    try {
      await FamilyInvitationService.respondToFamilyInvitation(
        notificationId: notificationId,
        accepted: accepted,
      );

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(accepted ? 'Invitation accepted' : 'Invitation refused')),
      );
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Operation failed：$e')),
      );
    }
  }

  Widget _iconForType(String type) {
    IconData icon;
    Color background;

    switch (type) {
      case 'task_invitation':
        icon = Icons.assignment;
        background = Colors.orange.shade600;
        break;
      case 'task_invitation_sent':
        icon = Icons.schedule_send;
        background = Colors.blue.shade500;
        break;
      case 'task_invitation_accepted':
        icon = Icons.check_circle;
        background = Colors.green.shade600;
        break;
      case 'task_invitation_declined':
        icon = Icons.cancel;
        background = Colors.red.shade500;
        break;
      case 'family_invitation':
        icon = Icons.group_add;
        background = Colors.deepPurple.shade400;
        break;
      case 'family_invitation_accepted':
        icon = Icons.how_to_reg;
        background = Colors.green.shade700;
        break;
      case 'family_invitation_declined':
        icon = Icons.person_off;
        background = Colors.red.shade700;
        break;
      default:
        icon = Icons.notifications;
        background = Colors.grey.shade500;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 22, color: Colors.white),
    );
  }
}

class _NotificationSection {
  _NotificationSection({required this.label, required this.docs});

  final String label;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
}