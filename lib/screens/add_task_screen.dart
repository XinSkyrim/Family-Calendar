import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/task_invitation_service.dart';
import '../assets/figma_assets.dart';
import '../themes/app_theme.dart';
import '../widgets/avatar_image.dart';
import 'family_selection_screen.dart';
import 'select_members_screen.dart';

class AddTaskScreen extends StatefulWidget {
  const AddTaskScreen({
    Key? key,
    this.initialTitle,
    this.initialNotes,
    this.initialDate,
    this.initialTime,
    this.initialCategory,
  }) : super(key: key);

  final String? initialTitle;
  final String? initialNotes;
  final DateTime? initialDate;
  final TimeOfDay? initialTime;
  final String? initialCategory;

  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  static const _background = AppTheme.pageBackground;
  static const _card = Color(0xFFFAF6EB);
  static const _labelColor = Color(0xFFB08F4C);
  static const _primaryColor = Color(0xFF0F172A);
  static const _accentColor = Color(0xFFE2B736);

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  bool _isSaving = false;
  bool _isLoadingDefaultParticipants = true;
  int _selectedCategoryIndex = 0;

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  String? _selectedFamilyId;
  String? _selectedFamilyName;
  List<SelectedTaskMember> _selectedParticipants = [];

  static const _categories = [
    {'label': 'Education', 'color': Color(0xFF3B82F6)},
    {'label': 'Family', 'color': Color(0xFF8B5CF6)},
    {'label': 'Leisure', 'color': Color(0xFFF97316)},
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _titleController.text = widget.initialTitle?.trim() ?? '';
    _notesController.text = widget.initialNotes?.trim() ?? '';
    _selectedDate =
        widget.initialDate ?? DateTime(now.year, now.month, now.day);
    _selectedTime =
        widget.initialTime ?? TimeOfDay(hour: now.hour, minute: now.minute);

    final initialCategory = widget.initialCategory?.trim().toLowerCase();
    final matchedIndex = _categories.indexWhere(
      (category) =>
          (category['label'] as String).toLowerCase() == initialCategory,
    );
    if (matchedIndex >= 0) {
      _selectedCategoryIndex = matchedIndex;
    }

    _loadDefaultParticipant();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _findUserByUid(String uid) async {
    final firestore = FirebaseFirestore.instance;

    final directDoc = await firestore.collection('users').doc(uid).get();
    if (directDoc.exists) {
      return directDoc.data();
    }

    final query = await firestore
        .collection('users')
        .where('uid', isEqualTo: uid)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      return query.docs.first.data();
    }

    return null;
  }

  Future<void> _loadDefaultParticipant() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _isLoadingDefaultParticipants = false;
      });
      return;
    }

    final userData = await _findUserByUid(user.uid);
    final name =
        (userData?['fullName'] ??
                userData?['name'] ??
                userData?['displayName'] ??
                user.email ??
                'Me')
            .toString()
            .trim();
    final avatarUrl =
        (userData?['photoURL'] ??
                userData?['photoUrl'] ??
                userData?['avatar'] ??
                '')
            .toString()
            .trim();

    final familyId = await _loadCurrentFamilyId(user.uid);

    if (!mounted) return;
    setState(() {
      _selectedFamilyId = familyId;
      _selectedParticipants = [];
      _isLoadingDefaultParticipants = false;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initialDate = _selectedDate ?? now;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _accentColor,
              onPrimary: Colors.white,
              onSurface: _primaryColor,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _pickTime() async {
    final initialTime = _selectedTime ?? const TimeOfDay(hour: 9, minute: 0);

    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(
                primary: _accentColor,
                onPrimary: Colors.white,
                onSurface: _primaryColor,
              ),
            ),
            child: child!,
          ),
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  String _dateText() {
    if (_selectedDate == null) return 'Select date';
    return DateFormat('MM/dd/yyyy').format(_selectedDate!);
  }

  String _timeText() {
    if (_selectedTime == null) return 'Select time';
    final hour = _selectedTime!.hour.toString().padLeft(2, '0');
    final minute = _selectedTime!.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  DateTime _buildStartDateTime() {
    final date = _selectedDate!;
    final time = _selectedTime!;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  String _selectedEventType() {
    return (_categories[_selectedCategoryIndex]['label'] as String)
        .toLowerCase();
  }

  Future<String?> _loadCurrentFamilyId(String uid) async {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final userData = userDoc.data();

    if (userData != null) {
      final directKeys = ['familyId', 'currentFamilyId', 'selectedFamilyId'];

      for (final key in directKeys) {
        final value = userData[key];
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
      }

      final listKeys = ['familyIds', 'families'];
      for (final key in listKeys) {
        final value = userData[key];
        if (value is List && value.isNotEmpty) {
          final first = value.first;
          if (first is String && first.trim().isNotEmpty) {
            return first.trim();
          }
        }
      }
    }

    final familyQuery = await FirebaseFirestore.instance
        .collection('families')
        .where('memberIds', arrayContains: uid)
        .limit(1)
        .get();

    if (familyQuery.docs.isNotEmpty) {
      return familyQuery.docs.first.id;
    }

    return null;
  }

  Future<void> _openFamilySelection() async {
    final result = await Navigator.of(context).push<FamilySelectionResult>(
      MaterialPageRoute(
        builder: (_) => FamilySelectionScreen(
          initialSelectedIds: _selectedParticipants.map((e) => e.id).toList(),
        ),
      ),
    );

    if (result == null) return;

    setState(() {
      _selectedFamilyId = result.familyId;
      _selectedFamilyName = result.familyName;
      _selectedParticipants = result.members;
    });
  }

  List<String> _buildParticipantIds(String _) {
    final ids = <String>{};

    for (final member in _selectedParticipants) {
      if (member.id.trim().isNotEmpty) {
        ids.add(member.id.trim());
      }
    }

    return ids.toList();
  }

  Future<void> _saveTask() async {
    final user = FirebaseAuth.instance.currentUser;
    final title = _titleController.text.trim();

    if (user == null) {
      _showMessage('Please sign in first.');
      return;
    }

    if (title.isEmpty) {
      _showMessage('Please enter task title.');
      return;
    }

    if (_selectedDate == null) {
      _showMessage('Please select date.');
      return;
    }

    if (_selectedTime == null) {
      _showMessage('Please select time.');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final familyId =
          _selectedFamilyId ?? await _loadCurrentFamilyId(user.uid) ?? user.uid;
      final selectedMemberIds = _buildParticipantIds(user.uid);
      final participantIds = selectedMemberIds;
      final containsSelf = selectedMemberIds.contains(user.uid);
      final invitedUserIds = selectedMemberIds
          .where((id) => id != user.uid)
          .toList();
      final startTime = _buildStartDateTime();
      final endTime = startTime.add(const Duration(hours: 1));
      final now = Timestamp.now();

      List<String> finalParticipantIds = [];
      List<String> pendingIds = [];
      List<String> acceptedIds = [];

      /// ✅ Case 1：只有自己
      if (participantIds.length == 1 && containsSelf) {
        finalParticipantIds = [user.uid];
        acceptedIds = [user.uid];
        pendingIds = [];

        /// ✅ Case 2：包含自己 + 其他人
      } else if (containsSelf) {
        finalParticipantIds = [user.uid]; // 自己直接可见
        acceptedIds = [user.uid];
        pendingIds = invitedUserIds;

        /// ✅ Case 3：不包含自己
      } else {
        finalParticipantIds = [];
        acceptedIds = [];
        pendingIds = participantIds;
      }

      finalParticipantIds = [user.uid];
      acceptedIds = [];
      pendingIds = invitedUserIds;

      final eventRef = await FirebaseFirestore.instance
          .collection('events')
          .add({
            'title': title,
            'description': _notesController.text.trim(),
            'eventType': _selectedEventType(),
            'familyId': familyId,
            'isAllDay': false,
            'location': '',

            'participantIds': finalParticipantIds,
            'pendingParticipantIds': pendingIds,
            'acceptedParticipantIds': acceptedIds,
            'declinedParticipantIds': <String>[],

            'reminderMinutes': 0,
            'repeatType': 'none',
            'startTime': Timestamp.fromDate(startTime),
            'endTime': Timestamp.fromDate(endTime),
            'status': 'active',
            'createdBy': user.uid,
            'createdAt': now,
            'updatedAt': now,
          });

      /// 只有存在“邀请别人”的情况才发送通知
      if (invitedUserIds.isNotEmpty) {
        await TaskInvitationService.createTaskInvitationNotifications(
          eventId: eventRef.id,
          eventTitle: title,
          creatorId: user.uid,
          invitedUserIds: containsSelf
              ? invitedUserIds
              : participantIds, // Case3：全员邀请
        );
      }

      if (!mounted) return;

      Navigator.of(context).pop(true);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            invitedUserIds.isEmpty
                ? 'Task saved!'
                : 'Task saved and invitation sent!',
          ),
        ),
      );
    } catch (e) {
      _showMessage('Failed to save task: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildParticipantAvatar(SelectedTaskMember member) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: CircleAvatar(
        radius: 22,
        backgroundColor: const Color(0xFFDCE1E8),
        backgroundImage: avatarImageProvider(member.avatarUrl),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: _background,
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
            child: Stack(
              children: [
                Center(
                  child: Container(
                    width: 430,
                    constraints: const BoxConstraints(maxWidth: 430),
                    color: _background,
                    child: Column(
                      children: [
                        _buildHeader(context),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 18),
                                _buildTitleInput(),
                                const SizedBox(height: 20),
                                _buildDateTimeCard(),
                                const SizedBox(height: 20),
                                _buildNotesSection(),
                                const SizedBox(height: 20),
                                _buildParticipantsSection(),
                                const SizedBox(height: 20),
                                _buildSaveButton(context),
                                const SizedBox(height: 36),
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
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      decoration: const BoxDecoration(
        color: AppTheme.headerBackground,
        boxShadow: [AppTheme.headerShadow],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          AppTheme.backButton(context),
          const Text(
            'Add Task',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.headline,
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildTitleInput() {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextField(
        controller: _titleController,
        decoration: const InputDecoration(
          counterText: '',
          hintText: 'Task title',
          hintStyle: TextStyle(
            color: Color(0xFF94A3B8),
            fontWeight: FontWeight.w500,
          ),
          border: InputBorder.none,
        ),
        style: const TextStyle(
          color: Color(0xFF334155),
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
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
            value: _dateText(),
            onTap: _pickDate,
          ),
          const Divider(height: 24, thickness: 1, color: Color(0xFFEDE6D3)),
          _buildDateTimeRow(
            icon: Icons.access_time,
            label: 'Time',
            value: _timeText(),
            onTap: _pickTime,
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
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
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
            minLines: 4,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Add some extra details here...',
              hintStyle: TextStyle(
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.w500,
              ),
              border: InputBorder.none,
              counterText: '',
            ),
            style: const TextStyle(color: Color(0xFF334155), fontSize: 15),
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
              onPressed: _openFamilySelection,
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
        if (_isLoadingDefaultParticipants)
          const SizedBox(
            height: 44,
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _accentColor,
              ),
            ),
          )
        else
          SizedBox(
            height: 44,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                children: _selectedParticipants
                    .map(_buildParticipantAvatar)
                    .toList(),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSaveButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isSaving ? null : _saveTask,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: _accentColor,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: _isSaving
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.black,
                ),
              )
            : const Text(
                'Add Task',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
      ),
    );
  }
}
