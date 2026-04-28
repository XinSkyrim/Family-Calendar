import 'dart:math' as math;
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/task.dart';
import '../navigation/app_bottom_nav.dart';
import '../services/onboarding_service.dart';
import '../themes/app_theme.dart';
import '../widgets/bottom_navigation_bar.dart';
import '../widgets/event_card.dart';
import '../widgets/feature_tour_overlay.dart';
import 'add_task_screen.dart';
import 'edit_task_screen.dart';
import 'notifications_screen.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({Key? key}) : super(key: key);

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  static const bgColor = AppTheme.pageBackground;
  static const primaryColor = AppTheme.headline;
  static const accentColor = AppTheme.accent;
  static const secondaryAccent = AppTheme.secondaryAccent;

  static const _hourRowHeight = 50.0;
  static const _leftTimeWidth = 60.0;
  static const _timelineGap = 16.0;
  static const _eventCardHeight = 168.0;
  static const _lineTopOffset = 18.0;
  static const _cardTopGapFromMarker = 0.0;
  static const _cardBottomGap = 14.0;
  static const _dateItemWidth = 70.0;
  static const _dateItemSpacing = 8.0;
  static const _dateHorizontalPadding = 16.0;

  final ScrollController _dateScrollController = ScrollController();
  Stream<QuerySnapshot<Map<String, dynamic>>>? _eventsStream;
  List<_CalendarEvent> _cachedEvents = <_CalendarEvent>[];
  int _selectedNavIndex = 2;
  final GlobalKey _calendarFabKey = GlobalKey();
  int _onboardingIndex = 0;
  bool _isOnboardingVisible = false;
  bool _isOnboardingBusy = false;
  late final List<DateTime> _days;
  late int _selectedDayIndex;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final user = FirebaseAuth.instance.currentUser;

    _days = List.generate(
      7,
      (index) => DateTime(today.year, today.month, today.day + index - 3),
    );
    _selectedDayIndex = 3;

    if (user != null) {
      _eventsStream = FirebaseFirestore.instance
          .collection('events')
          .where('participantIds', arrayContains: user.uid)
          .where('status', isEqualTo: 'active')
          .snapshots();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerSelectedDay(animate: false);
      _maybeStartOnboarding();
    });
  }

  @override
  void dispose() {
    _dateScrollController.dispose();
    super.dispose();
  }

  void _centerSelectedDay({bool animate = true}) {
    if (!_dateScrollController.hasClients) {
      return;
    }

    final viewportWidth = math.min(MediaQuery.of(context).size.width, 430.0);
    final itemExtent = _dateItemWidth + _dateItemSpacing;
    final rawOffset =
        (_selectedDayIndex * itemExtent) +
        _dateHorizontalPadding +
        (_dateItemWidth / 2) -
        (viewportWidth / 2);

    final targetOffset = rawOffset
        .clamp(0.0, _dateScrollController.position.maxScrollExtent)
        .toDouble();

    if (animate) {
      _dateScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } else {
      _dateScrollController.jumpTo(targetOffset);
    }
  }

  DateTime get _selectedDate => _days[_selectedDayIndex];

  Future<void> _maybeStartOnboarding() async {
    final state = await OnboardingService.getCurrentState();
    if (!mounted || state == null || !OnboardingService.shouldStart(state)) {
      return;
    }
    if (state.step != OnboardingService.stepCalendarAddFab) {
      return;
    }
    setState(() {
      _isOnboardingVisible = true;
      _onboardingIndex = 0;
    });
  }

  Future<void> _skipOnboarding() async {
    if (_isOnboardingBusy) {
      return;
    }
    setState(() {
      _isOnboardingBusy = true;
    });
    await OnboardingService.complete();
    if (!mounted) {
      return;
    }
    setState(() {
      _isOnboardingBusy = false;
      _isOnboardingVisible = false;
    });
  }

  Future<void> _finishOnboarding() async {
    await _skipOnboarding();
  }

  Future<void> _nextOnboardingStep() async {
    if (_isOnboardingIndexAtEnd) {
      await _finishOnboarding();
      return;
    }

    setState(() {
      _onboardingIndex += 1;
    });
  }

  Future<void> _previousOnboardingStep() async {
    if (_onboardingIndex == 0) {
      return;
    }
    setState(() {
      _onboardingIndex -= 1;
    });
  }

  bool get _onboardingIndexAtEnd => _onboardingIndex >= _calendarTourSteps.length - 1;

  List<FeatureTourStep> get _calendarTourSteps => [
        FeatureTourStep(
          id: OnboardingService.stepCalendarAddFab,
          targetKey: _calendarFabKey,
          title: 'Add a family event',
          description:
              'Tap this button any time to create a new event on your calendar.',
          preferredPlacement: TourBubblePlacement.above,
          highlightRadius: 40,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final mediaPadding = MediaQuery.of(context).padding;
    final statusBarHeight = mediaPadding.top;
    final bottomInset = mediaPadding.bottom;
    final fabBottomOffset = bottomInset + 112;

    return Scaffold(
      backgroundColor: bgColor,
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
                          const SizedBox(height: 74),
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: _buildDateSelector(),
                          ),
                          const SizedBox(height: 8),
                          Expanded(child: _buildTimeline(context)),
                          const SizedBox.shrink(),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _buildHeader(context),
                    ),
                    Positioned(
                      right: 24,
                      bottom: fabBottomOffset,
                      child: _buildFab(context),
                    ),
                    if (_isOnboardingVisible)
                      Positioned.fill(child: _buildOnboardingOverlay()),
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
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 16),
      decoration: const BoxDecoration(
        color: AppTheme.headerBackground,
        boxShadow: [AppTheme.headerShadow],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildHeaderAvatars(),
          Text(
            DateFormat('MMMM').format(_selectedDate),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: primaryColor,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildHeaderAvatars() {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Row(children: [_buildAvatar('')]);
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Row(children: [_buildAvatar('')]);
        }

        final data = snapshot.data!.data();
        final photoUrl = (data?['photoURL'] ?? '').toString().trim();

        return Row(children: [_buildAvatar(photoUrl)]);
      },
    );
  }

  Widget _buildAvatar(String imageUrl, {double overlap = 0}) {
    final hasImage = imageUrl.trim().isNotEmpty;

    return Transform.translate(
      offset: Offset(overlap, 0),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
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
              ? Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
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
      ),
    );
  }

  Widget _buildNotificationsButton(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
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
              child: Icon(Icons.notifications, size: 18, color: primaryColor),
            ),
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
    );
  }

  Widget _buildDateSelector() {
    return SizedBox(
      height: 90,
      child: ListView.separated(
        controller: _dateScrollController,
        padding: const EdgeInsets.symmetric(horizontal: _dateHorizontalPadding),
        scrollDirection: Axis.horizontal,
        itemCount: _days.length,
        separatorBuilder: (_, __) => const SizedBox(width: _dateItemSpacing),
        itemBuilder: (context, index) {
          final day = _days[index];
          final selected = index == _selectedDayIndex;

          return GestureDetector(
            onTap: () {
              setState(() => _selectedDayIndex = index);
              _centerSelectedDay();
            },
            child: Container(
              width: _dateItemWidth,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0x22E2B736)
                    : Colors.white.withOpacity(0.5),
                border: Border.all(
                  color: selected ? accentColor : const Color(0xFFF1F5F9),
                  width: selected ? 2 : 1,
                ),
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
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat('EEE').format(day),
                    style: TextStyle(
                      color: selected ? accentColor : const Color(0xFF64748B),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    DateFormat('d').format(day),
                    style: TextStyle(
                      color: selected ? accentColor : primaryColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTimeline(BuildContext context) {
    if (_eventsStream == null) {
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
      stream: _eventsStream,
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

        final allEvents =
            snapshot.data?.docs
                .map((doc) => _CalendarEvent.fromFirestore(doc))
                .where((event) => event != null)
                .cast<_CalendarEvent>()
                .toList() ??
            _cachedEvents;

        if (snapshot.hasData) {
          _cachedEvents = allEvents;
        }

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
                (snapshot.data?[0] as Map<String, String>?) ??
                <String, String>{};

            final participantAvatars =
                (snapshot.data?[1] as Map<String, String>?) ??
                <String, String>{};

            final int startHour;
            final int endHour;

            if (filteredEvents.isEmpty) {
              startHour = 0;
              endHour = 23;
            } else {
              final minHour = math.max(
                0,
                math.min(
                  23,
                  filteredEvents.map((e) => e.startTime.hour).reduce(math.min) -
                      1,
                ),
              );

              final maxHour = math.max(
                minHour + 1,
                math.min(
                  23,
                  filteredEvents
                      .map(
                        (e) => e.endTime.hour + (e.endTime.minute > 0 ? 1 : 0),
                      )
                      .reduce(math.max),
                ),
              );

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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
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
                            case _FlowItemType.minuteGap:
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

  _CalendarEvent? _nextEventAfter(
    List<_CalendarEvent> events,
    _CalendarEvent current,
  ) {
    final index = events.indexOf(current);
    if (index == -1 || index + 1 >= events.length) return null;
    return events[index + 1];
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
    final participants = event.participantIds
        .map((id) => participantNames[id] ?? 'Member')
        .toList();

    final avatarUrls = event.participantIds
        .map((id) => participantAvatars[id] ?? '')
        .toList();

    debugPrint('avatarUrls: $avatarUrls');

    return EventCard(
      color: _eventColor(event.eventType),
      category: event.eventType,
      title: _ellipsisTitle(event.title),
      timeRange: _formatTimeRange(
        event.startTime,
        event.endTime,
        event.isAllDay,
      ),
      participants: avatarUrls,
      subtitle: null,
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

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: const Column(
        children: [
          Icon(Icons.event_available, color: Color(0xFF94A3B8), size: 28),
          SizedBox(height: 12),
          Text(
            'No events for this day',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrailingIcon(_CalendarEvent event) {
    IconData icon;
    switch (event.eventType.toLowerCase()) {
      case 'meeting':
        icon = Icons.event;
        break;
      case 'health':
        icon = Icons.favorite;
        break;
      case 'shopping':
        icon = Icons.shopping_cart;
        break;
      case 'family':
        icon = Icons.people;
        break;
      case 'education':
        icon = Icons.school;
        break;
      default:
        icon = Icons.event_note;
    }

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.6),
        shape: BoxShape.circle,
      ),
      child: Center(child: Icon(icon, size: 18, color: primaryColor)),
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

  Widget _buildFab(BuildContext context) {
    return GestureDetector(
      key: _calendarFabKey,
      onTap: () {
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
              color: accentColor.withOpacity(0.3),
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

  Widget _buildOnboardingOverlay() {
    return FeatureTourOverlay(
      step: _calendarTourSteps[_onboardingIndex],
      currentIndex: _onboardingIndex,
      totalSteps: _calendarTourSteps.length,
      isBusy: _isOnboardingBusy,
      onPrevious: _onboardingIndex > 0 ? _previousOnboardingStep : null,
      onNext: _nextOnboardingStep,
      onSkip: _skipOnboarding,
      onComplete: _finishOnboarding,
    );
  }
}

enum _FlowItemType { hourGap, minuteGap, event }

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

  factory _FlowItem.minuteGap({String? label, required double height}) {
    return _FlowItem._(
      type: _FlowItemType.minuteGap,
      height: height,
      leftLabel: label,
      leftTopPadding: 0,
      lineTopPadding: 0,
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
