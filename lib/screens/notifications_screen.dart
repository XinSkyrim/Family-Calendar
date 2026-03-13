import 'package:flutter/material.dart';
import 'dart:ui';

import '../assets/figma_assets.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(context),
      body: _buildBody(context),
      backgroundColor: const Color(0xFFFDFBF7),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(80),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFDFBF7).withOpacity(0.8),
              border: Border(
                bottom: BorderSide(color: Colors.black.withOpacity(0.04)),
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: const Icon(
                        Icons.arrow_back,
                        size: 24,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Text(
                      'Notifications',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {},
                      child: const Icon(
                        Icons.settings,
                        size: 24,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        _buildSectionTitle('Today'),
        _buildJoinRequestCard(context),
        _buildNewEventCard(context),
        _buildSectionTitle('Sep 2nd'),
        _buildModifiedEventCard(context),
        _buildTaskCompletedCard(context),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildJoinRequestCard(BuildContext context) {
    return _notificationCard(
      context,
      icon: Icons.person_add,
      iconBackground: Colors.yellow.shade700,
      title: 'New member request',
      subtitle: 'John Doe wants to join the family calendar',
      action: TextButton(
        onPressed: () {},
        child: const Text('Accept'),
      ),
    );
  }

  Widget _buildNewEventCard(BuildContext context) {
    return _notificationCard(
      context,
      icon: Icons.event,
      iconBackground: Colors.orange.shade600,
      title: 'Scheduled: Sunday Roast',
      subtitle: 'Your family event is set for tomorrow at 6:00 PM',
      action: TextButton(
        onPressed: () {},
        child: const Text('View'),
      ),
    );
  }

  Widget _buildModifiedEventCard(BuildContext context) {
    return _notificationCard(
      context,
      icon: Icons.edit,
      iconBackground: Colors.blue.shade400,
      title: 'Event changed',
      subtitle: 'Sunday Roast moved to 7:00 PM',
      action: TextButton(
        onPressed: () {},
        child: const Text('View'),
      ),
    );
  }

  Widget _buildTaskCompletedCard(BuildContext context) {
    return _notificationCard(
      context,
      icon: Icons.check_circle,
      iconBackground: Colors.grey.shade400,
      title: 'Task completed',
      subtitle: 'Dad finished grocery shopping',
      action: TextButton(
        onPressed: () {},
        child: const Text('Got it'),
      ),
    );
  }

  Widget _notificationCard(
    BuildContext context, {
    required IconData icon,
    required Color iconBackground,
    required String title,
    required String subtitle,
    required Widget action,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8),
          ],
        ),
        child: ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconBackground,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 24, color: Colors.white),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(subtitle),
          trailing: action,
        ),
      ),
    );
  }

}
