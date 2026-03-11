import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const bgColor = Color(0xFFFDFBF7);
  static const primaryColor = Color(0xFF0F172A);
  static const accentColor = Color(0xFFE2B736);
  static const bubbleColor = Color(0xFFF5F2EB);
  static const aiBubbleColor = Color(0xFFF3EFFB);

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<ChatMessage> _messages = [];
  final String _conversationId =
  DateTime.now().millisecondsSinceEpoch.toString();

  bool _isSending = false;

  // @override
  // void initState() {
  //   super.initState();
  //
  //   // Optional demo messages so initial UI looks like the design screenshot.
  //   _messages.addAll([
  //     ChatMessage(
  //       role: MessageRole.family,
  //       senderName: 'Mom',
  //       text: 'Did anyone pick up the ingredients for the Sunday roast yet? 🧺',
  //     ),
  //     ChatMessage(
  //       role: MessageRole.user,
  //       senderName: 'Me',
  //       text:
  //       "I'm at the market now! I'll grab everything. Let's make sure it's on the calendar.",
  //     ),
  //     ChatMessage(
  //       role: MessageRole.assistant,
  //       text: "I can help with that! I've detected a new event from your conversation.",
  //       draftEvents: [
  //         DraftEvent(
  //           title: 'Family Sunday Roast',
  //           dateLabel: 'Sunday, Oct 22',
  //           timeLabel: '6:00 PM',
  //           location: 'Home (Kitchen)',
  //           statusLabel: 'TASK ADDED TO CALENDAR',
  //         ),
  //       ],
  //     ),
  //     ChatMessage(
  //       role: MessageRole.family,
  //       senderName: 'Lily',
  //       text: "Perfect! I'll help with the dessert. 🍰",
  //     ),
  //   ]);
  //
  //   WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  // }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    debugPrint('[Chat] send tapped');
    final text = _controller.text.trim();
    debugPrint('[Chat] text="$text", isSending=$_isSending');

    if (text.isEmpty || _isSending) {
      _showError(text.isEmpty ? 'Message is empty' : 'Already sending...');
      return;
    }

    debugPrint('[Chat] projectId=${Firebase.app().options.projectId}');

    setState(() {
      _isSending = true;
      _messages.add(
        ChatMessage(
          role: MessageRole.user,
          senderName: 'Me',
          text: text,
          createdAt: DateTime.now(),
        ),
      );
      _messages.add(
        ChatMessage(
          role: MessageRole.assistant,
          text: 'typing...',
          isTyping: true,
          createdAt: DateTime.now(),
        ),
      );
      _controller.clear();
    });

    _scrollToBottom();

    try {
      final functions =
      FirebaseFunctions.instanceFor(region: 'australia-southeast1');
      final callable = functions.httpsCallable('chatWithAI');

      final result = await callable.call(<String, dynamic>{
        'message': text,
        'conversationId': _conversationId,
      });

      final data = Map<String, dynamic>.from(result.data as Map);
      final reply = (data['reply'] as String?)?.trim();
      final draftEventsData = data['draftEvents'] as List<dynamic>?;

      final draftEvents = draftEventsData
          ?.whereType<Map>()
          .map((event) => DraftEvent.fromMap(Map<String, dynamic>.from(event)))
          .toList() ??
          [];

      setState(() {
        _replaceTyping(
          ChatMessage(
            role: MessageRole.assistant,
            text: reply?.isNotEmpty == true
                ? reply!
                : 'Sorry, I could not generate a response.',
            draftEvents: draftEvents,
            createdAt: DateTime.now(),
          ),
        );
      });
    } on FirebaseFunctionsException catch (e) {
      _showError(_mapFunctionError(e));
      setState(() {
        _replaceTyping(
          ChatMessage(
            role: MessageRole.assistant,
            text: 'I hit an error. Please try again in a moment.',
            createdAt: DateTime.now(),
          ),
        );
      });
    } catch (_) {
      _showError('Network error. Please check your connection and try again.');
      setState(() {
        _replaceTyping(
          ChatMessage(
            role: MessageRole.assistant,
            text: 'I could not reach the server. Please try again.',
            createdAt: DateTime.now(),
          ),
        );
      });
    } finally {
      setState(() {
        _isSending = false;
      });
      _scrollToBottom();
    }
  }

  void _replaceTyping(ChatMessage message) {
    final idx = _messages.lastIndexWhere((m) => m.isTyping);
    if (idx >= 0) {
      _messages[idx] = message;
    } else {
      _messages.add(message);
    }
  }

  String _mapFunctionError(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'unauthenticated':
        return 'Please sign in to continue.';
      case 'resource-exhausted':
        return 'Too many requests. Please wait a few seconds.';
      case 'invalid-argument':
        return 'Please enter a valid message.';
      default:
        return e.message ?? 'Request failed. Please try again.';
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: primaryColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '';
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final suffix = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: _buildAppBar(context),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: _messages.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return const Padding(
                    padding: EdgeInsets.only(bottom: 24),
                    child: Center(child: _DateLabel(label: 'Today')),
                  );
                }

                final message = _messages[index - 1];
                final previous = index > 1 ? _messages[index - 2] : null;

                final showMeta = previous == null ||
                    previous.role != message.role ||
                    previous.senderName != message.senderName;

                return _StyledMessageBubble(
                  message: message,
                  showMeta: showMeta,
                  timeText: _formatTime(message.createdAt),
                );
              },
            ),
          ),
          _buildBottomInput(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(80),
      child: Container(
        decoration: BoxDecoration(
          color: bgColor.withOpacity(0.95),
          border: Border(
            bottom: BorderSide(
              color: accentColor.withOpacity(0.10),
            ),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => Navigator.of(context).maybePop(),
                  child: const SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(
                      Icons.arrow_back,
                      size: 20,
                      color: Colors.black54,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Chat',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: primaryColor,
                      ),
                    ),
                    Text(
                      'The Henderson Family',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: accentColor,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                SizedBox(
                  width: 80,
                  height: 40,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        child: _buildHeaderAvatar(),
                      ),
                      Positioned(
                        left: 24,
                        child: _buildHeaderAvatar(),
                      ),
                      Positioned(
                        left: 48,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: accentColor.withOpacity(0.2),
                            shape: BoxShape.circle,
                            border: Border.all(color: bgColor, width: 2),
                          ),
                          child: const Center(
                            child: Text(
                              '+2',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: accentColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderAvatar() {
    return const CircleAvatar(
      radius: 16,
      backgroundColor: Color(0xFFE9EEF5),
      child: Icon(
        Icons.person,
        size: 18,
        color: Color(0xFF94A3B8),
      ),
    );
  }

  Widget _buildBottomInput() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: const BoxDecoration(
          color: bgColor,
          border: Border(
            top: BorderSide(color: Color(0xFFE2E8F0)),
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFF1F5F9)),
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 15,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                margin: const EdgeInsets.all(9),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.add,
                  size: 16,
                  color: Color(0xFF6B7280),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _isSending ? null : _send(),
                  decoration: const InputDecoration(
                    hintText: 'Message your family...',
                    hintStyle: TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 14,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),
              GestureDetector(
                onTap: _isSending ? null : _send,
                child: Container(
                  width: 40,
                  height: 40,
                  margin: const EdgeInsets.all(9),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF5F2EB),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: _isSending
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: primaryColor,
                      ),
                    )
                        : const Icon(
                      Icons.send,
                      size: 18,
                      color: primaryColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum MessageRole {
  user,
  assistant,
  family,
}

class ChatMessage {
  ChatMessage({
    required this.role,
    required this.text,
    this.senderName,
    this.isTyping = false,
    this.draftEvents = const [],
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final MessageRole role;
  final String text;
  final String? senderName;
  final bool isTyping;
  final List<DraftEvent> draftEvents;
  final DateTime createdAt;
}

class DraftEvent {
  DraftEvent({
    required this.title,
    this.startISO,
    this.endISO,
    this.dateISO,
    this.timeISO,
    this.location,
    this.dateLabel,
    this.timeLabel,
    this.statusLabel,
  });

  final String title;
  final String? startISO;
  final String? endISO;
  final String? dateISO;
  final String? timeISO;
  final String? location;
  final String? dateLabel;
  final String? timeLabel;
  final String? statusLabel;

  factory DraftEvent.fromMap(Map<String, dynamic> map) {
    return DraftEvent(
      title: (map['title'] as String?)?.trim().isNotEmpty == true
          ? map['title'] as String
          : 'Untitled',
      startISO: map['startISO'] as String?,
      endISO: map['endISO'] as String?,
      dateISO: map['dateISO'] as String?,
      timeISO: map['timeISO'] as String?,
      location: map['location'] as String?,
      dateLabel: map['dateLabel'] as String?,
      timeLabel: map['timeLabel'] as String?,
      statusLabel: map['statusLabel'] as String?,
    );
  }

  String get scheduleLabel {
    if ((dateLabel ?? '').isNotEmpty || (timeLabel ?? '').isNotEmpty) {
      final left = dateLabel ?? '';
      final right = timeLabel ?? '';
      return [left, right].where((e) => e.isNotEmpty).join(' • ');
    }

    if (startISO != null || endISO != null) {
      return '${startISO ?? 'TBD'} - ${endISO ?? 'TBD'}';
    }

    if (dateISO != null || timeISO != null) {
      return '${dateISO ?? 'Date TBD'} ${timeISO ?? 'Time TBD'}'.trim();
    }

    return 'Time not specified yet';
  }

  String get displayLocation =>
      (location ?? '').trim().isNotEmpty ? location! : 'Home';

  String get displayStatus =>
      (statusLabel ?? '').trim().isNotEmpty ? statusLabel! : 'TASK ADDED TO CALENDAR';
}

class _DateLabel extends StatelessWidget {
  const _DateLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F2EB),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFF94A3B8),
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _StyledMessageBubble extends StatelessWidget {
  const _StyledMessageBubble({
    required this.message,
    required this.showMeta,
    required this.timeText,
  });

  final ChatMessage message;
  final bool showMeta;
  final String timeText;

  static const primaryColor = Color(0xFF0F172A);
  static const accentColor = Color(0xFFE2B736);
  static const bubbleColor = Color(0xFFF5F2EB);
  static const aiBubbleColor = Color(0xFFF3EFFB);

  @override
  Widget build(BuildContext context) {
    switch (message.role) {
      case MessageRole.user:
        return _buildUserBubble();
      case MessageRole.assistant:
        return _buildAssistantBubble();
      case MessageRole.family:
        return _buildFamilyBubble();
    }
  }

  Widget _buildFamilyBubble() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const _PersonAvatar(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showMeta)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 4),
                    child: Text(
                      '${message.senderName ?? 'Family'}${timeText.isNotEmpty ? ' • $timeText' : ''}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                Container(
                  constraints: const BoxConstraints(maxWidth: 320),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    message.text,
                    style: const TextStyle(
                      fontSize: 15,
                      color: primaryColor,
                      height: 1.63,
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

  Widget _buildUserBubble() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (showMeta)
                  Padding(
                    padding: const EdgeInsets.only(right: 4, bottom: 4),
                    child: Text(
                      '${message.senderName ?? 'Me'}${timeText.isNotEmpty ? ' • $timeText' : ''}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                Container(
                  constraints: const BoxConstraints(maxWidth: 320),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    message.text,
                    style: const TextStyle(
                      fontSize: 15,
                      color: primaryColor,
                      height: 1.63,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const _PersonAvatar(),
        ],
      ),
    );
  }

  Widget _buildAssistantBubble() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Icon(Icons.event, size: 18, color: primaryColor),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showMeta)
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(
                      'AI ASSISTANT',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: accentColor,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                Container(
                  constraints: const BoxConstraints(maxWidth: 360),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: aiBubbleColor,
                    border: Border.all(color: const Color(0xFFF3E8FF)),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    message.isTyping ? 'Typing...' : message.text,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Color(0xFF1E293B),
                      height: 1.63,
                    ),
                  ),
                ),
                if (message.draftEvents.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...message.draftEvents.map((event) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _EventDraftCard(event: event),
                  )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EventDraftCard extends StatelessWidget {
  const _EventDraftCard({required this.event});

  final DraftEvent event;

  static const primaryColor = Color(0xFF0F172A);
  static const accentColor = Color(0xFFE2B736);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFF1F5F9)),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(
                  child: Icon(Icons.event, size: 18, color: primaryColor),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: primaryColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      event.scheduleLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 1,
            color: const Color(0xFFF8FAFC),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.location_on,
                size: 12,
                color: Color(0xFF64748B),
              ),
              const SizedBox(width: 8),
              Text(
                event.displayLocation,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              event.displayStatus.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFF64748B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonAvatar extends StatelessWidget {
  const _PersonAvatar();

  @override
  Widget build(BuildContext context) {
    return const CircleAvatar(
      radius: 18,
      backgroundColor: Color(0xFFE9EEF5),
      child: Icon(
        Icons.person,
        size: 20,
        color: Color(0xFF94A3B8),
      ),
    );
  }
}