import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../themes/app_theme.dart';
import '../assets/figma_assets.dart';
import '../models/task.dart';
import '../services/task_invitation_service.dart';
import '../widgets/avatar_image.dart';
import 'family_selection_screen.dart';
import 'select_members_screen.dart';

class EditTaskScreen extends StatefulWidget {
  const EditTaskScreen({
    super.key,
    required this.initialTask,
    required this.onUpdate,
    required this.onDelete,
  });

  final Task initialTask;
  final ValueChanged<Task> onUpdate;
  final VoidCallback onDelete;

  @override
  State<EditTaskScreen> createState() => _EditTaskScreenState();
}

class _EditTaskScreenState extends State<EditTaskScreen> {
  static const _background = AppTheme.pageBackground;
  static const _card = Color(0xFFFAF6EB);
  static const _labelColor = Color(0xFFB08F4C);
  static const _primaryColor = Color(0xFF0F172A);
  static const _accentColor = Color(0xFFE2B736);

  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  late Task _task;

  bool _isDeleting = false;
  bool _isUpdating = false;
  bool _isLoadingParticipants = true;

  String? _selectedFamilyId;
  String? _selectedFamilyName;
  List<SelectedTaskMember> _selectedParticipants = [];

  // Keep pending invitations internally, but do not display them as avatars.
  Set<String> _existingPendingParticipantIds = {};

  @override
  void initState() {
    super.initState();
    _task = widget.initialTask;
    _titleController = TextEditingController(text: _task.title);
    _notesController = TextEditingController(text: _task.notes);
    _loadInitialParticipants();
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

  Future<Map<String, dynamic>?> _findFamilyMemberByUid(
    String familyId,
    String uid,
  ) async {
    if (familyId.isEmpty || uid.isEmpty) {
      return null;
    }

    final firestore = FirebaseFirestore.instance;
    final membersRef = firestore
        .collection('families')
        .doc(familyId)
        .collection('members');

    final directDoc = await membersRef.doc(uid).get();
    if (directDoc.exists) {
      return directDoc.data();
    }

    final uidQuery = await membersRef
        .where('uid', isEqualTo: uid)
        .limit(1)
        .get();
    if (uidQuery.docs.isNotEmpty) {
      return uidQuery.docs.first.data();
    }

    final userIdQuery = await membersRef
        .where('userId', isEqualTo: uid)
        .limit(1)
        .get();
    if (userIdQuery.docs.isNotEmpty) {
      return userIdQuery.docs.first.data();
    }

    return null;
  }

  Future<void> _loadInitialParticipants() async {
    final taskId = _task.id;
    if (taskId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isLoadingParticipants = false;
      });
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('events')
          .doc(taskId)
          .get();

      final data = doc.data() ?? {};
      final familyId = (data['familyId'] ?? '').toString().trim();

      final participantIds = ((data['participantIds'] as List?) ?? [])
          .map((e) => e.toString())
          .where((id) => id.trim().isNotEmpty)
          .toSet();

      final pendingParticipantIds =
          ((data['pendingParticipantIds'] as List?) ?? [])
              .map((e) => e.toString())
              .where((id) => id.trim().isNotEmpty)
              .toSet();

      final List<SelectedTaskMember> members = [];
      final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final displayParticipantIds = <String>{
        ...participantIds,
        ...pendingParticipantIds,
      }..removeWhere((id) => id == currentUid);

      for (final uid in displayParticipantIds) {
        final userData = await _findUserByUid(uid);
        final memberData = await _findFamilyMemberByUid(familyId, uid);
        final name =
            (userData?['fullName'] ??
                    userData?['name'] ??
                    userData?['displayName'] ??
                    memberData?['nickname'] ??
                    memberData?['fullName'] ??
                    memberData?['name'] ??
                    'Unknown Member')
                .toString()
                .trim();

        final avatarUrl =
            (userData?['photoURL'] ??
                    userData?['photoUrl'] ??
                    userData?['avatar'] ??
                    memberData?['photoURL'] ??
                    memberData?['photoUrl'] ??
                    memberData?['avatar'] ??
                    '')
                .toString()
                .trim();

        members.add(
          SelectedTaskMember(
            id: uid,
            name: name.isEmpty ? 'Unknown Member' : name,
            avatarUrl: avatarUrl,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _selectedFamilyId = familyId.isEmpty ? null : familyId;
        _selectedParticipants = members;
        _existingPendingParticipantIds = pendingParticipantIds;
        _isLoadingParticipants = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingParticipants = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _task.date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      setState(() {
        final duration = _task.endTime.difference(_task.startTime);

        final newStart = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _task.startTime.hour,
          _task.startTime.minute,
        );

        final newEnd = newStart.add(duration);

        _task = _task.copyWith(
          date: DateTime(picked.year, picked.month, picked.day),
          startTime: newStart,
          endTime: newEnd,
        );
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _task.startTime.hour,
        minute: _task.startTime.minute,
      ),
    );

    if (picked != null) {
      setState(() {
        final duration = _task.endTime.difference(_task.startTime);

        final newStart = DateTime(
          _task.date.year,
          _task.date.month,
          _task.date.day,
          picked.hour,
          picked.minute,
        );

        final newEnd = newStart.add(duration);

        _task = _task.copyWith(startTime: newStart, endTime: newEnd);
      });
    }
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

  List<String> _buildParticipantIds(String currentUid) {
    final ids = <String>{currentUid};

    for (final member in _selectedParticipants) {
      if (member.id.trim().isNotEmpty) {
        ids.add(member.id.trim());
      }
    }

    return ids.toList();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _applyUpdate() async {
    final user = FirebaseAuth.instance.currentUser;
    final taskId = _task.id;

    if (user == null) {
      if (!mounted) return;
      _showMessage('Please sign in first.');
      return;
    }

    if (taskId.isEmpty) {
      if (!mounted) return;
      _showMessage('Task not found');
      return;
    }

    final title = _titleController.text.trim().isEmpty
        ? _task.title
        : _titleController.text.trim();

    final notes = _notesController.text.trim();

    final updated = _task.copyWith(title: title, notes: notes);

    setState(() {
      _isUpdating = true;
    });

    try {
      final eventRef = FirebaseFirestore.instance
          .collection('events')
          .doc(taskId);
      final eventSnapshot = await eventRef.get();

      if (!eventSnapshot.exists) {
        if (!mounted) return;
        _showMessage('Task not found');
        return;
      }

      final eventData = eventSnapshot.data() ?? <String, dynamic>{};

      final oldParticipantIds = ((eventData['participantIds'] as List?) ?? [])
          .map((e) => e.toString())
          .where((id) => id.trim().isNotEmpty)
          .toSet();

      final oldPendingIds =
          ((eventData['pendingParticipantIds'] as List?) ?? [])
              .map((e) => e.toString())
              .where((id) => id.trim().isNotEmpty)
              .toSet();

      final oldAcceptedIds =
          ((eventData['acceptedParticipantIds'] as List?) ?? [])
              .map((e) => e.toString())
              .where((id) => id.trim().isNotEmpty)
              .toSet();

      final oldDeclinedIds =
          ((eventData['declinedParticipantIds'] as List?) ?? [])
              .map((e) => e.toString())
              .where((id) => id.trim().isNotEmpty)
              .toSet();

      final selectedIds = _buildParticipantIds(user.uid).toSet();

      final newInviteeIds = selectedIds
          .where(
            (id) =>
                id != user.uid &&
                !oldParticipantIds.contains(id) &&
                !oldPendingIds.contains(id),
          )
          .toList();

      final nextParticipantIds = oldParticipantIds
          .where((id) => selectedIds.contains(id) || id == user.uid)
          .toSet();

      nextParticipantIds.add(user.uid);

      final nextPendingIds = <String>{
        ...oldPendingIds,
        ..._existingPendingParticipantIds,
      };

      nextPendingIds.removeWhere((id) => id == user.uid);
      nextPendingIds.addAll(newInviteeIds);

      final nextAcceptedIds = oldAcceptedIds
          .where((id) => selectedIds.contains(id) || id == user.uid)
          .toSet();

      nextAcceptedIds.add(user.uid);

      final nextDeclinedIds = oldDeclinedIds
          .where((id) => selectedIds.contains(id))
          .toSet();

      nextDeclinedIds.removeAll(newInviteeIds);

      await eventRef.update({
        'title': updated.title,
        'description': updated.notes,
        'eventType': _mapCategoryToEventType(updated.category),
        'startTime': Timestamp.fromDate(updated.startTime),
        'endTime': Timestamp.fromDate(updated.endTime),
        'familyId': _selectedFamilyId,
        'participantIds': nextParticipantIds.toList(),
        'pendingParticipantIds': nextPendingIds.toList(),
        'acceptedParticipantIds': nextAcceptedIds.toList(),
        'declinedParticipantIds': nextDeclinedIds.toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (newInviteeIds.isNotEmpty) {
        await TaskInvitationService.createTaskInvitationNotifications(
          eventId: taskId,
          eventTitle: updated.title,
          creatorId: user.uid,
          invitedUserIds: newInviteeIds,
        );
      }

      if (!mounted) return;

      Navigator.of(context).pop(true);
      return;
    } catch (e) {
      if (!mounted) return;
      _showMessage('Failed to update task, it may have been deleted');
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  Future<void> _deleteTask() async {
    final user = FirebaseAuth.instance.currentUser;
    final taskId = _task.id;

    if (user == null) {
      if (!mounted) return;
      _showMessage('Please sign in first.');
      return;
    }

    if (taskId.isEmpty) {
      if (!mounted) return;
      _showMessage('Task not found.');
      return;
    }

    setState(() {
      _isDeleting = true;
    });

    try {
      final firestore = FirebaseFirestore.instance;

      final notificationsSnapshot = await firestore
          .collection('notifications')
          .where('eventId', isEqualTo: taskId)
          .get();

      final batch = firestore.batch();

      batch.delete(firestore.collection('events').doc(taskId));

      for (final doc in notificationsSnapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _showMessage('The task delete failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }

  String _mapCategoryToEventType(String category) {
    switch (category.toLowerCase()) {
      case 'education':
        return 'education';
      case 'family':
        return 'family';
      case 'leisure':
        return 'leisure';
      default:
        return 'family';
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
            child: Center(
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
                            _buildTitleSection(),
                            const SizedBox(height: 20),
                            _buildDateTimeCard(),
                            const SizedBox(height: 20),
                            _buildNotesSection(),
                            const SizedBox(height: 20),
                            _buildParticipantsSection(),
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
            'Edit Task',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.headline,
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
              counterText: '',
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
                color: selected ? color.withValues(alpha: 0.15) : _card,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected
                      ? color.withValues(alpha: 0.25)
                      : const Color(0xFFE5E7EB),
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
                      color: selected ? color : color.withValues(alpha: 0.4),
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
            onTap: _pickDate,
          ),
          const Divider(height: 24, thickness: 1, color: Color(0xFFEDE6D3)),
          _buildDateTimeRow(
            icon: Icons.access_time,
            label: 'Time',
            value: _formatTimeRange(_task.startTime, _task.endTime),
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
                    color: Colors.black.withValues(alpha: 0.04),
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
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Add some extra details here...',
              hintStyle: TextStyle(
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.w500,
              ),
              border: InputBorder.none,
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
        if (_isLoadingParticipants)
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
          Wrap(
            children: _selectedParticipants
                .map(_buildParticipantAvatar)
                .toList(),
          ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _isUpdating ? null : _applyUpdate,
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: _accentColor,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: _isUpdating
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.black,
                    ),
                  )
                : const Text(
                    'Update Task',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: OutlinedButton(
            onPressed: _isDeleting ? null : _deleteTask,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Colors.redAccent),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: _isDeleting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.redAccent,
                    ),
                  )
                : const Text(
                    'Delete Task',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
          ),
        ),
      ],
    );
  }
}
