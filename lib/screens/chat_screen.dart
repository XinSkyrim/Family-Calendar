import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';


class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<ChatMessage> _messages = [];
  final String _conversationId = DateTime.now().millisecondsSinceEpoch.toString();
  bool _isSending = false;

  @override
  void dispose() {
    _controller.dispose();
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

    // final user = FirebaseAuth.instance.currentUser;
    // if (user == null) {
    //   _showError('Please sign in before using AI Chat.');
    //   return;
    // }

    final typingMessage = ChatMessage(
      role: MessageRole.assistant,
      text: 'typing...',
      isTyping: true,
    );


    setState(() {
      _isSending = true;
      _messages.add(ChatMessage(role: MessageRole.user, text: text));
      _messages.add(ChatMessage(role: MessageRole.assistant, text: 'typing...', isTyping: true));
      _controller.clear();
    });

    try {
      final functions = FirebaseFunctions.instanceFor(region: 'australia-southeast1');
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
          ),
        );
      });
    } finally {
      setState(() {
        _isSending = false;
      });
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
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Chat')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return _MessageBubble(message: message);
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText: 'Type your message...',
                          border: OutlineInputBorder(),
                        ),
                  onSubmitted: (_) => _send(),
                    ),
                  ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _isSending ? null : _send,
                      icon: _isSending
                          ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                          : const Icon(Icons.send),
                    ),
                  ],
                ),
            ),
          ),
        ],
      ),
    );
  }
}
enum MessageRole { user, assistant }

class ChatMessage {
  ChatMessage({
    required this.role,
    required this.text,
    this.isTyping = false,
    this.draftEvents = const [],
  });

  final MessageRole role;
  final String text;
  final bool isTyping;
  final List<DraftEvent> draftEvents;
}

class DraftEvent {
  DraftEvent({
    required this.title,
    this.startISO,
    this.endISO,
    this.dateISO,
    this.timeISO,
  });

  final String title;
  final String? startISO;
  final String? endISO;
  final String? dateISO;
  final String? timeISO;

  factory DraftEvent.fromMap(Map<String, dynamic> map) {
    return DraftEvent(
      title: (map['title'] as String?)
          ?.trim()
          .isNotEmpty == true
          ? map['title'] as String
          : 'Untitled',
      startISO: map['startISO'] as String?,
      endISO: map['endISO'] as String?,
      dateISO: map['dateISO'] as String?,
      timeISO: map['timeISO'] as String?,
    );
  }

  String get scheduleLabel {
    if (startISO != null || endISO != null) {
      return '${startISO ?? 'TBD'} - ${endISO ?? 'TBD'}';
    }
    if (dateISO != null || timeISO != null) {
      return '${dateISO ?? 'Date TBD'} ${timeISO ?? 'Time TBD'}'.trim();
    }
    return 'Time not specified yet';
  }
}
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context).colorScheme.primaryContainer
              : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message.text),
                if (!isUser && message.draftEvents.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...message.draftEvents.map(
                    (event) => Card(
                      margin: const EdgeInsets.only(top: 6),
                      child: ListTile(
                        dense: true,
                        title: Text(event.title),
                        subtitle: Text(event.scheduleLabel),
                  ),
                ),
                  ),
                ],
              ],
          ),
      ),
    );
  }
}
