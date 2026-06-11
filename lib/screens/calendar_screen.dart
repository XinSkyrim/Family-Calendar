import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/task.dart';
import '../navigation/app_bottom_nav.dart';
import '../services/app_session_guidance.dart';
import '../themes/app_theme.dart';
import '../widgets/bottom_navigation_bar.dart';
import '../widgets/event_card.dart';
import 'add_task_screen.dart';
import 'edit_task_screen.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with TickerProviderStateMixin {
  static const bgColor = AppTheme.pageBackground;
  static const accentColor = AppTheme.accent;
  static const secondaryAccent = AppTheme.secondaryAccent;

  static const _hourRowHeight = 50.0;
  static const _leftTimeWidth = 60.0;
  static const _timelineGap = 16.0;
  static const _lineTopOffset = 18.0;
  static const _cardTopGapFromMarker = 0.0;
  static const _cardBottomGap = 14.0;
  static const _dateItemWidth = 42.0;
  static const _dateItemSpacing = 8.0;
  static const _hintTextColor = AppTheme.accent;

  final GlobalKey _dateSelectorKey = GlobalKey();
  AnimationController? _addTaskHintController;
  List<_CalendarEvent> _cachedEvents = <_CalendarEvent>[];
  final int _selectedNavIndex = 1;
  DateTime _today = _dateOnly(DateTime.now());
  DateTime _selectedDate = _dateOnly(DateTime.now());
  DateTime _visibleMonth = _monthOnly(DateTime.now());
  bool _isDatePickerExpanded = false;
  bool _showAddTaskHint = false;

  static DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  static DateTime _monthOnly(DateTime date) {
    return DateTime(date.year, date.month);
  }

  @override
  void initState() {
    super.initState();
    _today = _dateOnly(DateTime.now());
    _addTaskHintController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _showAddTaskHint = AppSessionGuidance.shouldShow('calendar_add_task_hint');
    if (_showAddTaskHint) {
      _addTaskHintController?.forward(from: 0);
    }

    _selectedDate = _today;
    _visibleMonth = _monthOnly(_today);
  }

  @override
  void dispose() {
    _addTaskHintController?.dispose();
    super.dispose();
  }

  void _selectDate(DateTime date) {
    final normalized = _dateOnly(date);
    setState(() {
      _selectedDate = normalized;
      _visibleMonth = _monthOnly(normalized);
    });
  }

  void _changeVisibleMonth(int offset) {
    final nextMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + offset,
    );

    setState(() => _visibleMonth = nextMonth);
  }

  void _toggleDatePicker() {
    setState(() => _isDatePickerExpanded = !_isDatePickerExpanded);
  }

  void _handleScreenPointerDown(PointerDownEvent event) {
    if (_showAddTaskHint) {
      _hideAddTaskHint();
    }

    if (!_isDatePickerExpanded) {
      return;
    }

    final renderBox =
        _dateSelectorKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) {
      return;
    }

    final localPosition = renderBox.globalToLocal(event.position);
    final dateSelectorBounds = Offset.zero & renderBox.size;
    if (dateSelectorBounds.contains(localPosition)) {
      return;
    }

    setState(() {
      _visibleMonth = _monthOnly(_selectedDate);
      _isDatePickerExpanded = false;
    });
  }

  int _daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  List<DateTime> _visibleWeekDays() {
    final selectedInVisibleMonth =
        _selectedDate.year == _visibleMonth.year &&
        _selectedDate.month == _visibleMonth.month;
    final anchor = selectedInVisibleMonth ? _selectedDate : _visibleMonth;
    final start = anchor.subtract(Duration(days: anchor.weekday % 7));
    return List.generate(
      7,
      (index) => DateTime(start.year, start.month, start.day + index),
    );
  }

  List<DateTime> _visibleMonthDays() {
    final firstDay = DateTime(_visibleMonth.year, _visibleMonth.month);
    final leadingEmptyDays = firstDay.weekday % 7;
    final dayCount = _daysInMonth(_visibleMonth.year, _visibleMonth.month);
    final firstVisibleDay = firstDay.subtract(Duration(days: leadingEmptyDays));
    final cells = <DateTime>[
      for (var i = 0; i < leadingEmptyDays; i++)
        DateTime(
          firstVisibleDay.year,
          firstVisibleDay.month,
          firstVisibleDay.day + i,
        ),
      for (var day = 1; day <= dayCount; day++)
        DateTime(_visibleMonth.year, _visibleMonth.month, day),
    ];

    while (cells.length % 7 != 0) {
      final lastDay = cells.last;
      cells.add(DateTime(lastDay.year, lastDay.month, lastDay.day + 1));
    }

    return cells;
  }

  String get _selectedDateLabel {
    final selectedInVisibleMonth =
        _selectedDate.year == _visibleMonth.year &&
        _selectedDate.month == _visibleMonth.month;
    if (!selectedInVisibleMonth) {
      return 'Select a date';
    }

    if (_isSameDay(_selectedDate, _today)) {
      return 'Today';
    }

    return DateFormat('EEE, d MMM').format(_selectedDate);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>>? _eventsStreamForSelectedDate() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return null;
    }

    final dayStart = _dateOnly(_selectedDate);
    final dayEnd = dayStart.add(const Duration(days: 1));

    return FirebaseFirestore.instance
        .collection('events')
        .where('participantIds', arrayContains: user.uid)
        .where('status', isEqualTo: 'active')
        .where(
          'startTime',
          isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart),
        )
        .where('startTime', isLessThan: Timestamp.fromDate(dayEnd))
        .orderBy('startTime')
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>>? _fallbackEventsStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return null;
    }

    return FirebaseFirestore.instance
        .collection('events')
        .where('participantIds', arrayContains: user.uid)
        .where('status', isEqualTo: 'active')
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final mediaPadding = MediaQuery.of(context).padding;
    final statusBarHeight = mediaPadding.top;
    final bottomInset = mediaPadding.bottom;
    final fabBottomOffset = bottomInset + 112;

    return Scaffold(
      backgroundColor: bgColor,
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _handleScreenPointerDown,
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: statusBarHeight,
              child: const ColoredBox(color: AppTheme.headerBackground),
            ),
            SafeArea(
              bottom: false,
              child: Center(
                child: Container(
                  width: 430,
                  constraints: const BoxConstraints(maxWidth: 430),
                  height: double.infinity,
                  color: bgColor,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Column(
                          children: [
                            _buildDateSelector(),
                            const SizedBox(height: 12),
                            Expanded(child: _buildTimeline(context)),
                            const SizedBox.shrink(),
                          ],
                        ),
                      ),
                      if (_showAddTaskHint)
                        Positioned(
                          right: 24,
                          bottom: fabBottomOffset + 74,
                          child: _buildAddTaskHint(),
                        ),
                      Positioned(
                        right: 24,
                        bottom: fabBottomOffset,
                        child: _buildFab(context),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: AppBottomNavigationBar(
                          currentIndex: _selectedNavIndex,
                          onItemTapped: (index) {
                            navigateFromBottomNav(
                              context,
                              targetIndex: index,
                              currentIndex: _selectedNavIndex,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateSelector() {
    final displayDays = _isDatePickerExpanded
        ? _visibleMonthDays()
        : _visibleWeekDays();

    return Container(
      key: _dateSelectorKey,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      decoration: BoxDecoration(
        color: AppTheme.headerBackground,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4A463F).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('MMMM yyyy').format(_visibleMonth),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.headline,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _selectedDateLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.headline.withValues(alpha: 0.56),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _CalendarDateNavButton(
                icon: Icons.chevron_left_rounded,
                onTap: () => _changeVisibleMonth(-1),
              ),
              const SizedBox(width: 6),
              _CalendarDateNavButton(
                icon: Icons.chevron_right_rounded,
                onTap: () => _changeVisibleMonth(1),
              ),
            ],
          ),
          const SizedBox(height: 18),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _CalendarDateGrid(
              days: displayDays,
              expanded: _isDatePickerExpanded,
              visibleMonth: _visibleMonth,
              selectedDate: _selectedDate,
              today: _today,
              onSelectDate: _selectDate,
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleDatePicker,
            child: SizedBox(
              height: 20,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 48,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD2C5B2),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _isDatePickerExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: const Color(0xFFD2C5B2),
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

  Widget _buildTimeline(BuildContext context) {
    final eventsStream = _eventsStreamForSelectedDate();
    if (eventsStream == null) {
      return const Center(
        child: Text(
          'Please sign in first.',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: eventsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final fallbackStream = _fallbackEventsStream();
          if (fallbackStream == null) {
            return const Center(
              child: Text(
                'Failed to load events.',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }

          return _buildTimelineFromStream(fallbackStream);
        }

        final allEvents = _eventsFromSnapshot(snapshot);

        if (snapshot.hasData) {
          _cachedEvents = allEvents;
        }

        return _buildTimelineEvents(context, allEvents);
      },
    );
  }

  Widget _buildTimelineFromStream(
    Stream<QuerySnapshot<Map<String, dynamic>>> stream,
  ) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Failed to load events.',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }

        final allEvents = _eventsFromSnapshot(snapshot);
        if (snapshot.hasData) {
          _cachedEvents = allEvents;
        }

        return _buildTimelineEvents(context, allEvents);
      },
    );
  }

  List<_CalendarEvent> _eventsFromSnapshot(
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
  ) {
    return snapshot.data?.docs
            .map((doc) => _CalendarEvent.fromFirestore(doc))
            .where((event) => event != null)
            .cast<_CalendarEvent>()
            .toList() ??
        _cachedEvents;
  }

  Widget _buildTimelineEvents(
    BuildContext context,
    List<_CalendarEvent> allEvents,
  ) {
    final filteredEvents =
        allEvents
            .where((event) => _isSameDay(event.startTime, _selectedDate))
            .toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));

    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        _loadParticipantNames(filteredEvents),
        _loadParticipantAvatars(filteredEvents),
      ]),
      builder: (context, snapshot) {
        final participantNames =
            (snapshot.data?[0] as Map<String, String>?) ?? <String, String>{};

        final participantAvatars =
            (snapshot.data?[1] as Map<String, String>?) ?? <String, String>{};

        final int startHour;
        final int endHour;

        if (filteredEvents.isEmpty) {
          startHour = 0;
          endHour = 23;
        } else {
          startHour = 0;
          endHour = 24;
        }

        final flowItems = _buildFlowItems(
          context,
          filteredEvents,
          participantNames,
          startHour,
          endHour,
        );

        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: _leftTimeWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: flowItems
                        .map(
                          (item) => SizedBox(
                            height: item.height,
                            child: Align(
                              alignment: item.alignment,
                              child: item.leftLabel == null
                                  ? const SizedBox.shrink()
                                  : Padding(
                                      padding: EdgeInsets.only(
                                        top: item.leftTopPadding,
                                      ),
                                      child: Text(
                                        item.leftLabel!,
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(
                                          color: Color(0xFF94A3B8),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(width: _timelineGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: flowItems.map((item) {
                      switch (item.type) {
                        case _FlowItemType.hourGap:
                          return SizedBox(
                            height: item.height,
                            child: Align(
                              alignment: item.alignment,
                              child: Padding(
                                padding: EdgeInsets.only(
                                  top: item.lineTopPadding,
                                ),
                                child: Container(
                                  width: double.infinity,
                                  height: 2,
                                  color: const Color(0xFFF1F5F9),
                                ),
                              ),
                            ),
                          );
                        case _FlowItemType.event:
                          return Padding(
                            padding: EdgeInsets.only(
                              top: item.eventTopPadding,
                              bottom: item.eventBottomPadding,
                            ),
                            child: SizedBox(
                              height:
                                  item.height -
                                  item.eventTopPadding -
                                  item.eventBottomPadding,
                              child: _buildEventCard(
                                context,
                                item.event!,
                                participantNames,
                                participantAvatars,
                              ),
                            ),
                          );
                      }
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<Map<String, String>> _loadParticipantAvatars(
    List<_CalendarEvent> events,
  ) async {
    final ids = events.expand((e) => e.participantIds).toSet().toList();
    if (ids.isEmpty) return {};

    final result = <String, String>{};
    final firestore = FirebaseFirestore.instance;

    for (int i = 0; i < ids.length; i += 10) {
      final batch = ids.sublist(i, math.min(i + 10, ids.length));

      final snapshot = await firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: batch)
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final photo = (data['photoURL'] ?? '').toString().trim();

        result[doc.id] = photo;
      }
    }
    return result;
  }

  List<_FlowItem> _buildFlowItems(
    BuildContext context,
    List<_CalendarEvent> events,
    Map<String, String> participantNames,
    int startHour,
    int endHour,
  ) {
    final items = <_FlowItem>[];
    final sortedEvents = [...events]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    for (int hour = startHour; hour <= endHour; hour++) {
      items.add(
        _FlowItem.hourGap(
          label: '${hour.toString().padLeft(2, '0')}:00',
          height: _hourRowHeight,
        ),
      );

      final hourEvents = sortedEvents
          .where((event) => event.startTime.hour == hour)
          .toList();

      for (final event in hourEvents) {
        items.add(_FlowItem.event(event));
      }
    }

    return items;
  }

  String _ellipsisTitle(String text) {
    final value = text.trim();
    if (value.length <= 12) return value;
    return '${value.substring(0, 12)}...';
  }

  Widget _buildEventCard(
    BuildContext context,
    _CalendarEvent event,
    Map<String, String> participantNames,
    Map<String, String> participantAvatars,
  ) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final displayParticipantIds = event.participantIds
        .where((id) => id != currentUid)
        .toList();
    final participants = displayParticipantIds
        .map((id) => participantNames[id] ?? 'Member')
        .toList();

    return EventCard(
      color: _eventColor(event.eventType),
      category: event.eventType,
      title: _ellipsisTitle(event.title),
      timeRange: _formatTimeRange(
        event.startTime,
        event.endTime,
        event.isAllDay,
      ),
      participants: const [],
      subtitle: event.description.trim().isEmpty
          ? null
          : event.description.trim(),
      trailingIcon: null,
      onTap: () {
        final task = Task(
          id: event.id,
          title: event.title,
          category: event.eventType,
          date: DateTime(
            event.startTime.year,
            event.startTime.month,
            event.startTime.day,
          ),
          startTime: event.startTime,
          endTime: event.endTime,
          notes: event.description,
          participants: participants,
          reminderEnabled: false,
        );

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EditTaskScreen(
              initialTask: task,
              onUpdate: (_) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Task updated')));
              },
              onDelete: () {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Task deleted')));
              },
            ),
          ),
        );
      },
    );
  }

  Color _eventColor(String eventType) {
    switch (eventType.toLowerCase()) {
      case 'meeting':
        return const Color(0xFFE0F2FE);
      case 'health':
        return const Color(0xFFE0F2FE);
      case 'family':
        return const Color(0xFFE0F2FE);
      case 'shopping':
        return const Color(0xFFE0F2FE);
      case 'education':
        return const Color(0xFFE0F2FE);
      default:
        return const Color(0xFFE0F2FE);
    }
  }

  String _formatTimeRange(DateTime start, DateTime end, bool isAllDay) {
    if (isAllDay) return 'All day';
    final formatter = DateFormat('h:mm a');
    return '${formatter.format(start)} - ${formatter.format(end)}';
  }

  Future<Map<String, String>> _loadParticipantNames(
    List<_CalendarEvent> events,
  ) async {
    final ids = events.expand((event) => event.participantIds).toSet().toList();
    if (ids.isEmpty) return <String, String>{};

    final firestore = FirebaseFirestore.instance;
    final result = <String, String>{};

    for (int i = 0; i < ids.length; i += 10) {
      final batch = ids.sublist(i, math.min(i + 10, ids.length));
      final snapshot = await firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: batch)
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final name =
            (data['fullName'] ?? data['username'] ?? data['email'] ?? '')
                .toString()
                .trim();
        if (name.isNotEmpty) {
          result[doc.id] = name;
        }
      }
    }

    for (final id in ids) {
      result.putIfAbsent(id, () => 'Member');
    }

    return result;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    final localA = a.toLocal();
    final localB = b.toLocal();
    return localA.year == localB.year &&
        localA.month == localB.month &&
        localA.day == localB.day;
  }

  void _hideAddTaskHint() {
    if (!_showAddTaskHint ||
        _addTaskHintController?.status == AnimationStatus.dismissed) {
      return;
    }

    _showAddTaskHint = false;
    _addTaskHintController?.reverse();
  }

  Widget _buildAddTaskHint() {
    final hintAnimation = _addTaskHintController;

    return SizedBox(
      height: 36,
      child: IgnorePointer(
        ignoring: true,
        child: hintAnimation == null
            ? Opacity(
                opacity: _showAddTaskHint ? 1 : 0,
                child: _buildAddTaskHintPill(),
              )
            : FadeTransition(
                opacity: CurvedAnimation(
                  parent: hintAnimation,
                  curve: Curves.easeOutCubic,
                ),
                child: _buildAddTaskHintPill(),
              ),
      ),
    );
  }

  Widget _buildAddTaskHintPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFF1E8D8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: const Text(
        'Tap to add a task',
        style: TextStyle(
          color: _hintTextColor,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildFab(BuildContext context) {
    return GestureDetector(
      onTap: () {
        _hideAddTaskHint();
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const AddTaskScreen()));
      },
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [accentColor, secondaryAccent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.3),
              blurRadius: 25,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: const Center(
          child: Icon(Icons.add, size: 28, color: Colors.white),
        ),
      ),
    );
  }
}

enum _FlowItemType { hourGap, event }

class _FlowItem {
  final _FlowItemType type;
  final double height;
  final String? leftLabel;
  final double leftTopPadding;
  final double lineTopPadding;
  final Alignment alignment;
  final double eventTopPadding;
  final double eventBottomPadding;
  final _CalendarEvent? event;

  const _FlowItem._({
    required this.type,
    required this.height,
    required this.leftLabel,
    required this.leftTopPadding,
    required this.lineTopPadding,
    required this.alignment,
    required this.eventTopPadding,
    required this.eventBottomPadding,
    required this.event,
  });

  factory _FlowItem.hourGap({required String label, required double height}) {
    return _FlowItem._(
      type: _FlowItemType.hourGap,
      height: height,
      leftLabel: label,
      leftTopPadding: 8,
      lineTopPadding: _CalendarScreenState._lineTopOffset,
      alignment: Alignment.topCenter,
      eventTopPadding: 0,
      eventBottomPadding: 0,
      event: null,
    );
  }

  factory _FlowItem.event(_CalendarEvent event) {
    const double cardHeight = 145.0;

    return _FlowItem._(
      type: _FlowItemType.event,
      height:
          cardHeight +
          _CalendarScreenState._cardTopGapFromMarker +
          _CalendarScreenState._cardBottomGap,
      leftLabel: null,
      leftTopPadding: 0,
      lineTopPadding: 0,
      alignment: Alignment.topCenter,
      eventTopPadding: _CalendarScreenState._cardTopGapFromMarker,
      eventBottomPadding: _CalendarScreenState._cardBottomGap,
      event: event,
    );
  }
}

class _CalendarDateGrid extends StatelessWidget {
  const _CalendarDateGrid({
    required this.days,
    required this.expanded,
    required this.visibleMonth,
    required this.selectedDate,
    required this.today,
    required this.onSelectDate,
  });

  final List<DateTime> days;
  final bool expanded;
  final DateTime visibleMonth;
  final DateTime selectedDate;
  final DateTime today;
  final ValueChanged<DateTime> onSelectDate;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Wrap(
          spacing: _CalendarScreenState._dateItemSpacing,
          children: const ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT']
              .map(
                (label) => SizedBox(
                  width: _CalendarScreenState._dateItemWidth,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFD4B76A),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: _CalendarScreenState._dateItemSpacing,
          runSpacing: expanded ? 10 : 0,
          children: days.map((day) {
            final selected = _isSameDay(day, selectedDate);
            final isToday = _isSameDay(day, today);
            final inVisibleMonth =
                day.year == visibleMonth.year &&
                day.month == visibleMonth.month;
            final previousDay = DateTime(day.year, day.month, day.day - 1);
            final nextDay = DateTime(day.year, day.month, day.day + 1);
            final touchesVisibleMonth =
                (previousDay.year == visibleMonth.year &&
                    previousDay.month == visibleMonth.month) ||
                (nextDay.year == visibleMonth.year &&
                    nextDay.month == visibleMonth.month);
            final showMonthLabel =
                expanded && !inVisibleMonth && touchesVisibleMonth;

            return GestureDetector(
              onTap: () => onSelectDate(day),
              child: Container(
                width: _CalendarScreenState._dateItemWidth,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? _CalendarScreenState.accentColor
                      : inVisibleMonth
                      ? Colors.transparent
                      : Colors.white.withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(16),
                  border: isToday && !selected
                      ? Border.all(
                          color: _CalendarScreenState.accentColor,
                          width: 1.2,
                        )
                      : null,
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.10),
                            blurRadius: 15,
                            offset: const Offset(0, 8),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      DateFormat('d').format(day),
                      style: TextStyle(
                        color: selected
                            ? const Color(0xFF271900)
                            : inVisibleMonth
                            ? AppTheme.headline
                            : AppTheme.headline.withValues(alpha: 0.34),
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (showMonthLabel) ...[
                      const SizedBox(height: 1),
                      Text(
                        DateFormat('MMM').format(day).toUpperCase(),
                        style: TextStyle(
                          color: AppTheme.headline.withValues(alpha: 0.34),
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _CalendarDateNavButton extends StatelessWidget {
  const _CalendarDateNavButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.78),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFF1E8D8)),
        ),
        child: Icon(icon, size: 22, color: AppTheme.headline),
      ),
    );
  }
}

class _CalendarEvent {
  final String id;
  final String title;
  final String description;
  final String eventType;
  final String familyId;
  final bool isAllDay;
  final String location;
  final List<String> participantIds;
  final int reminderMinutes;
  final String repeatType;
  final DateTime startTime;
  final DateTime endTime;
  final String status;
  final String createdBy;
  final DateTime? createdAt;

  _CalendarEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.eventType,
    required this.familyId,
    required this.isAllDay,
    required this.location,
    required this.participantIds,
    required this.reminderMinutes,
    required this.repeatType,
    required this.startTime,
    required this.endTime,
    required this.status,
    required this.createdBy,
    required this.createdAt,
  });

  static _CalendarEvent? fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) return null;

    final startTimestamp = data['startTime'];
    final endTimestamp = data['endTime'];

    if (startTimestamp is! Timestamp || endTimestamp is! Timestamp) {
      return null;
    }

    return _CalendarEvent(
      id: doc.id,
      title: (data['title'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      eventType: (data['eventType'] ?? 'event').toString(),
      familyId: (data['familyId'] ?? '').toString(),
      isAllDay: data['isAllDay'] == true,
      location: (data['location'] ?? '').toString(),
      participantIds: List<String>.from(data['participantIds'] ?? const []),
      reminderMinutes: (data['reminderMinutes'] ?? 0) is int
          ? data['reminderMinutes'] as int
          : int.tryParse('${data['reminderMinutes']}') ?? 0,
      repeatType: (data['repeatType'] ?? 'none').toString(),
      startTime: startTimestamp.toDate(),
      endTime: endTimestamp.toDate(),
      status: (data['status'] ?? '').toString(),
      createdBy: (data['createdBy'] ?? '').toString(),
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
    );
  }
}
