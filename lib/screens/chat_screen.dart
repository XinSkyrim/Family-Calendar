import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  static const bgColor = Color(0xFFFDFBF7);
  static const primaryColor = Color(0xFF0F172A);
  static const accentColor = Color(0xFFE2B736);

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  final List<ChatMessage> _messages = [];
  final String _conversationId = DateTime.now().millisecondsSinceEpoch
      .toString();

  late final AnimationController _voiceBarsController;

  bool _isSending = false;
  bool _speechReady = false;
  bool _voiceModeEnabled = false;
  bool _isListening = false;
  bool _isAssistantSpeaking = false;
  bool _isVoiceSubmitting = false;
  bool _isRecording = false;
  String _liveTranscript = '';
  final List<String> _recordedPrompts = [];

  @override
  void initState() {
    super.initState();
    _voiceBarsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _initVoiceTools();
  }

  Future<void> _initVoiceTools() async {
    await _initSpeech();
    await _initTts();
  }

  Future<void> _initSpeech() async {
    try {
      final ready = await _speech.initialize(
        onStatus: _handleSpeechStatus,
        onError: _handleSpeechError,
      );

      if (!mounted) return;
      setState(() {
        _speechReady = ready;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _speechReady = false;
      });
    }
  }

  void _handleSpeechError(dynamic error) {
    if (!mounted) return;

    final errorMessage = '${error.errorMsg ?? error}'.toLowerCase();
    final isTimeout = errorMessage.contains('error_speech_timeout');
    final isNoMatch = errorMessage.contains('error_no_match');
    final shouldRetrySilently =
        _voiceModeEnabled && !_isSending && (isTimeout || isNoMatch);

    setState(() {
      _isListening = false;
    });
    _stopVoiceBarsIfIdle();

    if (shouldRetrySilently) {
      unawaited(_restartListeningSilently());
      return;
    }

    if (error.permanent != true) {
      _showError('Voice recognition failed: ${error.errorMsg ?? error}');
    }
  }

  Future<void> _restartListeningSilently() async {
    if (!_voiceModeEnabled || _isSending || _isListening) return;

    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted || !_voiceModeEnabled || _isSending || _isListening) return;

    await _startListening();
  }

  Future<void> _configurePreferredVoice() async {
    try {
      final voices = await _tts.getVoices;
      if (voices is! List) return;

      Map<String, String>? preferredVoice;
      var preferredScore = -1;

      for (final rawVoice in voices.whereType<Map>()) {
        final voice = rawVoice.map(
          (key, value) => MapEntry('$key', '${value ?? ''}'),
        );
        final name = (voice['name'] ?? '').toLowerCase();
        final locale = (voice['locale'] ?? voice['language'] ?? '')
            .toLowerCase();
        final identifier = (voice['identifier'] ?? '').toLowerCase();
        final quality = (voice['quality'] ?? '').toLowerCase();
        final gender = (voice['gender'] ?? '').toLowerCase();

        if (!locale.startsWith('en')) continue;

        var score = 0;
        if (locale.contains('en-us')) score += 6;
        if (locale.contains('en-gb')) score += 5;
        if (locale.contains('en-au')) score += 4;
        if (quality.contains('premium') ||
            quality.contains('enhanced') ||
            quality.contains('high')) {
          score += 6;
        }
        if (name.contains('neural') ||
            name.contains('enhanced') ||
            name.contains('premium') ||
            identifier.contains('enhanced') ||
            identifier.contains('premium')) {
          score += 5;
        }
        if (gender.contains('female')) score += 2;
        if (name.contains('samantha') ||
            name.contains('ava') ||
            name.contains('allison') ||
            name.contains('karen') ||
            name.contains('moira') ||
            name.contains('siri')) {
          score += 3;
        }

        if (score > preferredScore) {
          preferredScore = score;
          preferredVoice = voice;
        }
      }

      if (preferredVoice == null) return;
      await _tts.setVoice(preferredVoice);
    } catch (_) {
      // Fall back to the platform default voice when a custom one is unavailable.
    }
  }

  Future<void> _initTts() async {
    if (Platform.isIOS || Platform.isMacOS) {
      await _tts.setSharedInstance(true);
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        <IosTextToSpeechAudioCategoryOptions>[
          IosTextToSpeechAudioCategoryOptions
              .interruptSpokenAudioAndMixWithOthers,
          IosTextToSpeechAudioCategoryOptions.duckOthers,
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
        ],
        IosTextToSpeechAudioMode.spokenAudio,
      );
    }

    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.64);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.02);
    await _tts.awaitSpeakCompletion(true);
    await _configurePreferredVoice();

    _tts.setStartHandler(() {
      if (!mounted) return;
      setState(() {
        _isAssistantSpeaking = true;
      });
      _startVoiceBars();
      if (_voiceModeEnabled && !_isListening) {
        unawaited(_startListening(interruptAssistant: false, passive: true));
      }
    });

    void finishSpeaking() {
      if (!mounted) return;
      setState(() {
        _isAssistantSpeaking = false;
      });
      _stopVoiceBarsIfIdle();
      if (_voiceModeEnabled && !_isListening) {
        unawaited(_restartListeningSilently());
      }
    }

    _tts.setCompletionHandler(finishSpeaking);
    _tts.setCancelHandler(finishSpeaking);
    _tts.setErrorHandler((_) => finishSpeaking());
  }

  @override
  void dispose() {
    _voiceBarsController.dispose();
    _speech.cancel();
    _tts.stop();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    _appendVisibleMessage(text, includeInRecording: _isRecording);
  }

  Future<void> _stopAssistantSpeech() async {
    if (!_isAssistantSpeaking) return;
    await _tts.stop();
  }

  Future<void> _submitMessage(
    String text, {
    required bool speakReply,
    bool addUserBubble = true,
  }) async {
    if (text.isEmpty || _isSending) {
      _showError(text.isEmpty ? 'Message is empty' : 'Already sending...');
      return;
    }

    setState(() {
      _isSending = true;
      if (addUserBubble) {
        _messages.add(
          ChatMessage(
            role: MessageRole.user,
            senderName: 'Me',
            text: text,
            createdAt: DateTime.now(),
          ),
        );
      }
      _messages.add(
        ChatMessage(
          role: MessageRole.assistant,
          text: 'typing...',
          isTyping: true,
          createdAt: DateTime.now(),
        ),
      );
      _controller.clear();
      _liveTranscript = '';
    });

    _scrollToBottom();

    try {
      final functions = FirebaseFunctions.instanceFor(
        region: 'australia-southeast1',
      );
      final callable = functions.httpsCallable('chatWithAI');

      final result = await callable.call(<String, dynamic>{
        'message': text,
        'conversationId': _conversationId,
      });

      final data = Map<String, dynamic>.from(result.data as Map);
      final reply = (data['reply'] as String?)?.trim();
      final draftEventsData = data['draftEvents'] as List<dynamic>?;

      final draftEvents =
          draftEventsData
              ?.whereType<Map>()
              .map(
                (event) => DraftEvent.fromMap(Map<String, dynamic>.from(event)),
              )
              .toList() ??
          [];

      final assistantMessage = ChatMessage(
        role: MessageRole.assistant,
        text: reply?.isNotEmpty == true
            ? reply!
            : 'Sorry, I could not generate a response.',
        draftEvents: draftEvents,
        createdAt: DateTime.now(),
      );

      setState(() {
        _replaceTyping(assistantMessage);
        _isSending = false;
      });
      _scrollToBottom();

      if (speakReply) {
        await _speakAssistantReply(assistantMessage.text);
      }
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
      if (mounted) {
        setState(() {
          _isSending = false;
        });
        _scrollToBottom();

        if (speakReply &&
            _voiceModeEnabled &&
            !_isAssistantSpeaking &&
            !_isListening) {
          unawaited(_restartListeningSilently());
        }
      }
    }
  }

  void _appendVisibleMessage(String text, {required bool includeInRecording}) {
    if (text.isEmpty) {
      _showError('Message is empty');
      return;
    }

    setState(() {
      if (includeInRecording) {
        _recordedPrompts.add(text);
      }
      _messages.add(
        ChatMessage(
          role: MessageRole.user,
          senderName: 'Me',
          text: text,
          createdAt: DateTime.now(),
        ),
      );
      _controller.clear();
      _liveTranscript = '';
    });

    _scrollToBottom();
  }

  Future<void> _toggleRecording() async {
    if (_isSending) return;

    if (_isRecording) {
      await _finishRecording();
      return;
    }

    if (_isAssistantSpeaking) {
      await _stopAssistantSpeech();
    }

    setState(() {
      _isRecording = true;
      _recordedPrompts.clear();
      _controller.clear();
      _liveTranscript = '';
    });
  }

  Future<void> _finishRecording() async {
    final combinedPrompt = _recordedPrompts
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .join('\n');

    setState(() {
      _isRecording = false;
    });

    if (_voiceModeEnabled || _isListening) {
      await _disableVoiceConversation();
    }

    if (combinedPrompt.isEmpty) {
      _showError('No recorded content yet. Add something before stopping the recording.');
      return;
    }

    _recordedPrompts.clear();
    await _submitMessage(
      combinedPrompt,
      speakReply: false,
      addUserBubble: false,
    );
  }

  Future<void> _speakAssistantReply(String text) async {
    if (text.trim().isEmpty) return;
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> _toggleVoiceConversation() async {
    if (!_isRecording) {
      _showError('Start recording first, then use the mic to capture what you want to send.');
      return;
    }

    if (_voiceModeEnabled) {
      await _disableVoiceConversation();
      return;
    }

    if (_isAssistantSpeaking) {
      await _stopAssistantSpeech();
      return;
    }

    if (!_speechReady) {
      await _initSpeech();
    }

    if (!_speechReady) {
      _showError('Voice input is not available on this device.');
      return;
    }

    if (_isAssistantSpeaking) {
      await _tts.stop();
    }

    setState(() {
      _voiceModeEnabled = true;
    });

    await _startListening();
  }

  Future<void> _disableVoiceConversation() async {
    setState(() {
      _voiceModeEnabled = false;
      _isListening = false;
      _isVoiceSubmitting = false;
      _liveTranscript = '';
    });
    await _speech.stop();
    await _tts.stop();
    _stopVoiceBarsIfIdle();
  }

  Future<void> _startListening({
    bool interruptAssistant = true,
    bool passive = false,
  }) async {
    if (!_speechReady || _isListening || _isSending) return;

    if (interruptAssistant && _isAssistantSpeaking) {
      await _stopAssistantSpeech();
    }

    setState(() {
      _isListening = true;
      if (!passive) {
        _isVoiceSubmitting = false;
        _liveTranscript = '';
      }
    });
    _startVoiceBars();

    await _speech.listen(
      pauseFor: passive
          ? const Duration(seconds: 10)
          : const Duration(seconds: 3),
      listenOptions: stt.SpeechListenOptions(
        listenMode: passive
            ? stt.ListenMode.dictation
            : stt.ListenMode.confirmation,
        partialResults: true,
      ),
      onSoundLevelChange: (level) {
        if (passive && _isAssistantSpeaking && level > 2.5) {
          unawaited(_stopAssistantSpeech());
        }
      },
      onResult: (result) {
        final words = result.recognizedWords.trim();
        if (!mounted) return;
        setState(() {
          if (words.isNotEmpty) {
            _liveTranscript = words;
            _controller.text = words;
            _controller.selection = TextSelection.collapsed(
              offset: _controller.text.length,
            );
          }
        });

        if (passive && words.isNotEmpty && _isAssistantSpeaking) {
          unawaited(_stopAssistantSpeech());
          setState(() {});
        }

        if (result.finalResult) {
          unawaited(_finalizeVoiceInput());
        }
      },
    );
  }

  Future<void> _finalizeVoiceInput() async {
    if (_isVoiceSubmitting) return;

    final text = _liveTranscript.trim().isNotEmpty
        ? _liveTranscript.trim()
        : _controller.text.trim();

    if (text.isEmpty) {
      if (_voiceModeEnabled && !_isListening && !_isSending) {
        await _startListening();
      }
      return;
    }

    _isVoiceSubmitting = true;
    await _speech.stop();

    if (!mounted) return;
    setState(() {
      _isListening = false;
    });

    _stopVoiceBarsIfIdle();
    _appendVisibleMessage(text, includeInRecording: _isRecording);
    _isVoiceSubmitting = false;
  }

  void _handleSpeechStatus(String status) {
    if (!mounted) return;

    if (status == 'listening') {
      setState(() {
        _isListening = true;
      });
      _startVoiceBars();
      return;
    }

    if (status == 'done' || status == 'notListening') {
      setState(() {
        _isListening = false;
      });
      _stopVoiceBarsIfIdle();

      if (_voiceModeEnabled && !_isVoiceSubmitting && !_isSending) {
        unawaited(_finalizeVoiceInput());
      }
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

  void _startVoiceBars() {
    if (!_voiceBarsController.isAnimating) {
      _voiceBarsController.repeat();
    }
  }

  void _stopVoiceBarsIfIdle() {
    if (!_isListening && !_isAssistantSpeaking) {
      _voiceBarsController.stop();
    }
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
    final showVoiceBars = _voiceModeEnabled || _isAssistantSpeaking;

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

                final showMeta =
                    previous == null ||
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
          _buildBottomInput(showVoiceBars),
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
            bottom: BorderSide(color: accentColor.withOpacity(0.10)),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
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
                ),
                const Text(
                  'Group Chat',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: primaryColor,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: 80,
                    height: 40,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(left: 0, child: _buildHeaderAvatar()),
                        Positioned(left: 24, child: _buildHeaderAvatar()),
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
      child: Icon(Icons.person, size: 18, color: Color(0xFF94A3B8)),
    );
  }

  Widget _buildBottomInput(bool showVoiceBars) {
    final statusText = _isListening
        ? 'Listening... capturing your notes'
        : _isAssistantSpeaking
        ? 'AI is speaking...'
        : _isRecording
        ? 'Recording is on. Everything you send will be bundled for the AI.'
        : _voiceModeEnabled
        ? 'Voice mode is on. Tap mic to end.'
        : 'Tap Record to start collecting content for the AI';

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: const BoxDecoration(
          color: bgColor,
          border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: showVoiceBars
                  ? Padding(
                      key: ValueKey(statusText),
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _VoiceStatusBanner(
                        label: statusText,
                        accentColor: accentColor,
                        animation: _voiceBarsController,
                        isAssistant: _isAssistantSpeaking,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: _toggleRecording,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _isRecording ? accentColor : const Color(0xFFF5F2EB),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: _isRecording
                            ? accentColor.withOpacity(0.2)
                            : const Color(0xFFE2E8F0),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isRecording ? Icons.fiber_manual_record : Icons.radio_button_unchecked,
                          size: 16,
                          color: _isRecording ? primaryColor : const Color(0xFF6B7280),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isRecording
                              ? 'Stop recording${_recordedPrompts.isNotEmpty ? ' (${_recordedPrompts.length})' : ''}'
                              : 'Record',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _isRecording
                                ? primaryColor
                                : const Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Container(
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
                      decoration: InputDecoration(
                        hintText: _isListening
                            ? 'Listening to your voice...'
                            : _isRecording
                            ? 'Send notes to this recording...'
                            : 'Tap Record, then add what you want AI to analyze...',
                        hintStyle: const TextStyle(
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
                    onTap: (_isSending && !_isAssistantSpeaking)
                        ? null
                        : _toggleVoiceConversation,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 40,
                      height: 40,
                      margin: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: _voiceModeEnabled
                            ? accentColor
                            : const Color(0xFFF5F2EB),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _voiceModeEnabled ? Icons.mic : Icons.mic_none,
                        size: 18,
                        color: _voiceModeEnabled
                            ? primaryColor
                            : const Color(0xFF6B7280),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _isSending ? null : _send,
                    child: Container(
                      width: 40,
                      height: 40,
                      margin: const EdgeInsets.only(
                        top: 9,
                        right: 9,
                        bottom: 9,
                      ),
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
          ],
        ),
      ),
    );
  }
}

enum MessageRole { user, assistant, family }

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
      return [left, right].where((e) => e.isNotEmpty).join(' | ');
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

  String get displayStatus => (statusLabel ?? '').trim().isNotEmpty
      ? statusLabel!
      : 'TASK ADDED TO CALENDAR';
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
                      '${message.senderName ?? 'Family'}${timeText.isNotEmpty ? ' | $timeText' : ''}',
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
                      '${message.senderName ?? 'Me'}${timeText.isNotEmpty ? ' | $timeText' : ''}',
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
                  ...message.draftEvents.map(
                    (event) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _EventDraftCard(event: event),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceStatusBanner extends StatelessWidget {
  const _VoiceStatusBanner({
    required this.label,
    required this.accentColor,
    required this.animation,
    required this.isAssistant,
  });

  final String label;
  final Color accentColor;
  final Animation<double> animation;
  final bool isAssistant;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accentColor.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          _VoiceBars(
            animation: animation,
            color: isAssistant ? const Color(0xFF7C3AED) : accentColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceBars extends StatelessWidget {
  const _VoiceBars({required this.animation, required this.color});

  final Animation<double> animation;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(6, (index) {
            final phase = animation.value * math.pi * 2 + index * 0.65;
            final height = 8 + (math.sin(phase).abs() * 18);
            return Container(
              width: 4,
              height: height,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(999),
              ),
            );
          }),
        );
      },
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
          Container(height: 1, color: const Color(0xFFF8FAFC)),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.location_on, size: 12, color: Color(0xFF64748B)),
              const SizedBox(width: 8),
              Text(
                event.displayLocation,
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
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
      child: Icon(Icons.person, size: 20, color: Color(0xFF94A3B8)),
    );
  }
}
