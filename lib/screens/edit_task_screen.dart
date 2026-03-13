import 'package:flutter/material.dart';

import '../assets/figma_assets.dart';
import '../models/task.dart';
import 'select_members_screen.dart';

class EditTaskScreen extends StatefulWidget {
  const EditTaskScreen({
    Key? key,
    required this.initialTask,
    required this.onUpdate,
    required this.onDelete,
  }) : super(key: key);

  final Task initialTask;
  final ValueChanged<Task> onUpdate;
  final VoidCallback onDelete;

  @override
  State<EditTaskScreen> createState() => _EditTaskScreenState();
}

class _EditTaskScreenState extends State<EditTaskScreen> {
  static const _background = Color(0xFFFDFBF7);
  static const _card = Color(0xFFFAF6EB);
  static const _labelColor = Color(0xFFB08F4C);
  static const _primaryColor = Color(0xFF0F172A);
  static const _accentColor = Color(0xFFE2B736);

  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  late Task _task;

  @override
  void initState() {
    super.initState();
    _task = widget.initialTask;
    _titleController = TextEditingController(text: _task.title);
    _notesController = TextEditingController(text: _task.notes);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _applyUpdate() {
    final updated = _task.copyWith(
      title: _titleController.text.trim().isEmpty
          ? _task.title
          : _titleController.text.trim(),
      notes: _notesController.text.trim(),
    );
    widget.onUpdate(updated);
    Navigator.of(context).pop();
  }

  void _deleteTask() {
    widget.onDelete();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFDFBF7), Color(0xFFFFF7E1)],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: Container(
                  width: 430,
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Column(
                    children: [
                      _buildHeader(context),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 18),
                              _buildTitleSection(),
                              const SizedBox(height: 20),
                              _buildCategoryChips(),
                              const SizedBox(height: 22),
                              _buildDateTimeCard(),
                              const SizedBox(height: 20),
                              _buildNotesSection(),
                              const SizedBox(height: 20),
                              _buildParticipantsSection(),
                              const SizedBox(height: 20),
                              _buildReminderCard(),
                              const SizedBox(height: 20),
                              _buildActionButtons(context),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  Icons.arrow_back_ios_new,
                  size: 18,
                  color: _primaryColor,
                ),
              ),
            ),
          ),
          const Text(
            'Edit Task',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _primaryColor,
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _buildTitleSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Task Title',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _labelColor,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 56,
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.centerLeft,
          child: TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              hintText: 'Add task title',
              hintStyle: TextStyle(
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.w500,
              ),
              border: InputBorder.none,
              isDense: true,
            ),
            style: const TextStyle(
              color: _primaryColor,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryChips() {
    const categories = [
      {'label': 'Education', 'color': Color(0xFF3B82F6)},
      {'label': 'Family', 'color': Color(0xFF8B5CF6)},
      {'label': 'Leisure', 'color': Color(0xFFF97316)},
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(categories.length, (index) {
        final category = categories[index];
        final bool selected = category['label'] == _task.category;
        final color = category['color'] as Color;

        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() {
              _task = _task.copyWith(category: category['label'] as String);
            }),
            child: Container(
              height: 40,
              margin: EdgeInsets.only(left: index == 0 ? 0 : 8),
              decoration: BoxDecoration(
                color: selected ? color.withOpacity(0.15) : _card,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected ? color.withOpacity(0.25) : const Color(0xFFE5E7EB),
                  width: 1.2,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: selected ? color : color.withOpacity(0.4),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    category['label'] as String,
                    style: TextStyle(
                      color: selected ? color : const Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildDateTimeCard() {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      child: Column(
        children: [
          _buildDateTimeRow(
            icon: Icons.calendar_month,
            label: 'Date',
            value: _formatDate(_task.date),
            onTap: () {},
          ),
          const Divider(height: 24, thickness: 1, color: Color(0xFFEDE6D3)),
          _buildDateTimeRow(
            icon: Icons.access_time,
            label: 'Time',
            value: _formatTimeRange(_task.startTime, _task.endTime),
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildDateTimeRow({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(icon, color: _accentColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: _primaryColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    // Example: Monday, Oct 24, 2023
    return '${_weekdayName(date.weekday)}, ${_monthName(date.month)} ${date.day}, ${date.year}';
  }

  String _formatTime(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  String _formatTimeRange(DateTime start, DateTime end) {
    return '${_formatTime(start)} – ${_formatTime(end)}';
  }

  String _weekdayName(int weekday) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[weekday - 1];
  }

  String _monthName(int month) {
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return names[month - 1];
  }

  Widget _buildNotesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.notes, size: 18, color: _labelColor),
            SizedBox(width: 8),
            Text(
              'NOTES',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _labelColor,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(minHeight: 120),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: TextField(
            controller: _notesController,
            maxLines: null,
            minLines: 4,
            decoration: const InputDecoration(
              hintText: 'Add some extra details here...',
              hintStyle: TextStyle(
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.w500,
              ),
              border: InputBorder.none,
            ),
            style: const TextStyle(
              color: Color(0xFF334155),
              fontSize: 15,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildParticipantsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Participants',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: _primaryColor,
              ),
            ),
            TextButton(
              onPressed: () async {
                final updated = await Navigator.of(context).push<List<String>>(
                  MaterialPageRoute(
                    builder: (_) => SelectMembersScreen(
                      initialSelectedNames: _task.participants,
                    ),
                  ),
                );
                if (updated != null) {
                  setState(() {
                    _task = _task.copyWith(participants: updated);
                  });
                }
              },
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(50, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                '+ Edit Member',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _accentColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: _task.participants
              .map((name) => Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: _buildMemberAvatar(name),
                  ))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildMemberAvatar(String name) {
    final url = _memberAvatarUrl(name);
    return CircleAvatar(
      radius: 22,
      backgroundColor: const Color(0xFFDCE1E8),
      backgroundImage: NetworkImage(url),
    );
  }

  String _memberAvatarUrl(String name) {
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

  Widget _buildReminderCard() {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.notifications,
              color: _accentColor,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Reminders',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _primaryColor,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '15 minutes before',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _task.reminderEnabled,
            activeColor: _accentColor,
            onChanged: (value) {
              setState(() {
                _task = _task.copyWith(reminderEnabled: value);
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          height: 56,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFDBA3C), Color(0xFFFFA800)],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFEA9E22).withOpacity(0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: _applyUpdate,
                child: const Center(
                  child: Text(
                    'Update Task',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _deleteTask,
          child: const Text(
            'Delete Task',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFFEF4444),
            ),
          ),
        ),
      ],
    );
  }
}
