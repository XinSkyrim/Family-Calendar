import 'package:flutter/material.dart';

import '../assets/figma_assets.dart';
import '../models/task.dart';
import '../widgets/event_card.dart';
import 'add_task_screen.dart';
import 'edit_task_screen.dart';
import 'notifications_screen.dart';
import 'family_screen.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

class CalendarScreen extends StatelessWidget {
  const CalendarScreen({Key? key}) : super(key: key);

  static const bgColor = Color(0xFFFDFBF7);
  static const primaryColor = Color(0xFF0F172A);
  static const accentColor = Color(0xFFE2B736);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Container(
                width: 430,
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(
                  children: [
                    _buildHeader(context),
                    const SizedBox(height: 16),
                    _buildDateSelector(),
                    const SizedBox(height: 16),
                    Expanded(child: _buildTimeline(context)),
                    const SizedBox(height: 90),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 16,
              bottom: 72,
              child: FloatingActionButton(
                shape: const CircleBorder(),
                backgroundColor: accentColor,
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AddTaskScreen()),
                  );
                },
                child: const Icon(Icons.add),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildBottomNav(context),
            ),
          ],
        ),
      ),
    );
  }

  // -----------------------------
  // Header
  // -----------------------------
  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 20,
                backgroundColor: Colors.white,
                child: Icon(Icons.person, size: 24, color: Colors.grey),
              ),
              const SizedBox(width: 8),
              const CircleAvatar(
                radius: 20,
                backgroundColor: Colors.white,
                child: Icon(Icons.person, size: 24, color: Colors.grey),
              ),
            ],
          ),
          const Text(
            'December',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: primaryColor,
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.white.withOpacity(0.6),
                  child: Icon(Icons.notifications, size: 18, color: primaryColor),
                ),
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: const BoxDecoration(
                      color: Color(0xFFEF4444),
                      borderRadius: BorderRadius.all(Radius.circular(999)),
                    ),
                    child: const Text(
                      '99+',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -----------------------------
  // Date selector
  // -----------------------------
  Widget _buildDateSelector() {
    // Keep it simple: List<Map<String, dynamic>> avoids Object -> String issues.
    final List<Map<String, dynamic>> days = [
      {'label': 'Mon', 'day': '11'},
      {'label': 'Tue', 'day': '12'},
      {'label': 'Wed', 'day': '13', 'selected': true},
      {'label': 'Thu', 'day': '14'},
      {'label': 'Fri', 'day': '15'},
      {'label': 'Sat', 'day': '16'},
    ];

    return SizedBox(
      height: 104,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final d = days[index];
          final bool selected = d['selected'] == true;

          return Container(
            width: 80,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            decoration: BoxDecoration(
              color: selected ? const Color(0x22E2B736) : Colors.white.withOpacity(0.5),
              border: Border.all(
                color: selected ? accentColor : const Color(0xFFF1F5F9),
                width: selected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  d['label'].toString(), // ✅ always String
                  style: TextStyle(
                    color: selected ? accentColor : const Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  d['day'].toString(), // ✅ always String
                  style: TextStyle(
                    color: selected ? accentColor : primaryColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // -----------------------------
  // Timeline
  // -----------------------------
  Widget _buildTimeline(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            _timeRow('08:00', _blueEvent(context)),
            const SizedBox(height: 24),
            _timeDivider('09:00'),
            const SizedBox(height: 24),
            _timeRow('10:00', _purpleEvent(context)),
            const SizedBox(height: 24),
            _timeDivider('11:00'),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _timeRow(String time, Widget right) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 60,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              time,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(child: right),
      ],
    );
  }

  Widget _timeDivider(String time) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              time,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Container(height: 2, width: 282, color: const Color(0xFFF1F5F9)),
      ],
    );
  }

  // -----------------------------
  // Event cards
  // -----------------------------
  Widget _blueEvent(BuildContext context) {
    final task = Task(
      title: 'English Class',
      category: 'Education',
      date: DateTime.now(),
      startTime: DateTime.now(),
      endTime: DateTime.now().add(const Duration(hours: 1, minutes: 30)),
      notes: '',
      participants: ['Mom', 'Dad', 'Sister'],
      reminderEnabled: true,
    );

    return EventCard(
      color: const Color(0xFFE0F2FE),
      category: task.category,
      title: task.title,
      timeRange: '8:00 AM - 9:30 AM',
      participants: task.participants,
      trailingIcon: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.6),
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: Icon(Icons.event, size: 18, color: primaryColor),
        ),
      ),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EditTaskScreen(
              initialTask: task,
              onUpdate: (updated) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Task updated')),
                );
              },
              onDelete: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Task deleted')),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _purpleEvent(BuildContext context) {
    final task = Task(
      title: 'Grocery Run',
      category: 'Family',
      date: DateTime.now(),
      startTime: DateTime.now().add(const Duration(hours: 1)),
      endTime: DateTime.now().add(const Duration(hours: 1, minutes: 45)),
      notes: "Dad's turn today",
      participants: ['Brother'],
      reminderEnabled: true,
    );

    return EventCard(
      color: const Color(0xFFF3E8FF),
      category: task.category,
      title: task.title,
      timeRange: '10:15 AM - 11:00 AM',
      participants: task.participants,
      subtitle: task.notes,
      trailingIcon: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.6),
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: Icon(Icons.shopping_cart, size: 18, color: primaryColor),
        ),
      ),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EditTaskScreen(
              initialTask: task,
              onUpdate: (updated) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Task updated')),
                );
              },
              onDelete: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Task deleted')),
                );
              },
            ),
          ),
        );
      },
    );
  }

  // -----------------------------
  // Bottom navigation
  // -----------------------------
  Widget _buildBottomNav(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        border: const Border(
          top: BorderSide(color: Color(0xFFF1F5F9)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _navItem(Icons.calendar_today, 'Today', selected: true),
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FamilyScreen()),
            ),
            child: _navItem(Icons.people, 'Family'),
          ),
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ChatScreen()),
            ),
            child: _navItem(Icons.chat_bubble_outline, 'Chat'),
          ),
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            child: _navItem(Icons.settings, 'Settings'),
          ),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, {bool selected = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 20,
          color: selected ? accentColor : const Color(0xFF94A3B8),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? accentColor : const Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }
}