import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../services/realtime_memo_transcription_service.dart';
import '../themes/app_theme.dart';
import 'add_task_screen.dart';

class MemoDetailScreen extends StatefulWidget {
  final String memoId;
  final String title;
  final String body;
  final bool isCreating;

  const MemoDetailScreen({
    super.key,
    this.memoId = '',
    this.title = '',
    this.body = '',
    this.isCreating = false,
  });

  @override
  State<MemoDetailScreen> createState() => _MemoDetailScreenState();
}

class _MemoDetailScreenState extends State<MemoDetailScreen>
    with SingleTickerProviderStateMixin {
  static const int _maxTitleLength = 30;
  static const int _generatedTitleLength = 20;
  static const _background = AppTheme.pageBackground;
  static const _primaryColor = Color(0xFF0F172A);
  static const _accentColor = Color(0xFFFAC638);
  static const _cardBorder = Color.fromRGBO(250, 198, 56, 0.05);
  static const _bodyText = Color(0xFF334155);
  static const _titleStyle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w800,
    color: _primaryColor,
    height: 1.4,
  );
  static const _bodyStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: _bodyText,
    height: 1.6,
  );
  static const double _minDetailBodyHeight = 112;
  static const double _maxDetailBodyHeight = 440;

  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  late final FocusNode _titleFocusNode;
  late final FocusNode _bodyFocusNode;
  late final ScrollController _bodyScrollController;
  final stt.SpeechToText _speech = stt.SpeechToText();
  final RealtimeMemoTranscriptionService _realtimeTranscription =
      RealtimeMemoTranscriptionService();
  late final AnimationController _voiceBarsController;

  late String _originalTitle;
  late String _originalBody;
  late bool _isCreatingMode;
  late String _currentMemoId;
  Timer? _autosaveTimer;
  bool _isSaving = false;
  bool _isAnalyzingTask = false;
  bool _speechReady = false;
  bool _isListening = false;
  bool _isVoiceTransitioning = false;
  double _soundLevel = 0;
  String _listeningTarget = 'body';
  int _voiceSessionId = 0;

  bool get _hasChanges {
    return _titleController.text.trim() != _originalTitle.trim() ||
        _bodyController.text.trim() != _originalBody.trim();
  }

  @override
  void initState() {
    super.initState();
    _originalTitle = widget.title;
    _originalBody = widget.body;
    _isCreatingMode = widget.isCreating;
    _currentMemoId = widget.memoId;
    _titleController = TextEditingController(text: widget.title)
      ..addListener(_handleFieldChanged);
    _bodyController = TextEditingController(text: widget.body)
      ..addListener(_handleBodyChanged);
    _titleFocusNode = FocusNode()..addListener(_handleFocusChange);
    _bodyFocusNode = FocusNode()..addListener(_handleFocusChange);
    _bodyScrollController = ScrollController();
    _voiceBarsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _initSpeech();
  }

  void _handleFieldChanged() {
    if (!mounted) {
      return;
    }
    _scheduleAutosave();
    setState(() {});
  }

  void _handleBodyChanged() {
    if (!mounted) {
      return;
    }

    _scheduleBodyScrollToLatest();
    _scheduleAutosave();
    setState(() {});
  }

  void _handleFocusChange() {
    if (!mounted || _isListening || _isVoiceTransitioning) {
      return;
    }

    if (_bodyFocusNode.hasFocus) {
      _scheduleBodyScrollToLatest();
    }
  }

  Future<void> _initSpeech() async {
    try {
      final ready = await _speech.initialize(
        onStatus: _handleSpeechStatus,
        onError: _handleSpeechError,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _speechReady = ready;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _speechReady = false;
      });
    }
  }

  bool get _isSpeechActive {
    return _isListening ||
        _speech.isListening ||
        _realtimeTranscription.isActive;
  }

  Future<bool> _ensureSpeechReady() async {
    if (_speechReady) {
      return true;
    }

    await _initSpeech();
    return _speechReady;
  }

  void _resetVoiceUiState() {
    if (!mounted) {
      return;
    }

    setState(() {
      _isListening = false;
      _soundLevel = 0;
    });
    _stopVoiceBars();
  }

  void _scheduleBodyScrollToLatest({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_bodyScrollController.hasClients) {
        return;
      }

      final selection = _bodyController.selection;
      final caretNearEnd =
          !selection.isValid ||
          selection.extentOffset >= _bodyController.text.length - 1;

      if (!force && !_isListening && !_bodyFocusNode.hasFocus) {
        return;
      }

      if (!force && !caretNearEnd) {
        return;
      }

      _bodyScrollController.jumpTo(
        _bodyScrollController.position.maxScrollExtent,
      );
    });
  }

  Future<void> _stopVoiceInputForNavigation() async {
    _voiceSessionId++;

    try {
      await _realtimeTranscription.cancel();
      await _speech.cancel();
    } catch (_) {
      // Keep the page responsive even if the plugin cannot cancel cleanly.
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isListening = false;
      _isVoiceTransitioning = false;
      _soundLevel = 0;
    });
    _stopVoiceBars();
  }

  Future<_SavedMemo?> _saveMemo({
    bool popAfterCreate = false,
    bool showSuccessMessage = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();

    if (user == null) {
      _showMessage('Please sign in to save your note.');
      return null;
    }

    if (title.isEmpty && body.isEmpty) {
      _showMessage('Please enter your note first.');
      return null;
    }

    if (title.length > _maxTitleLength) {
      _showMessage('Note title cannot exceed $_maxTitleLength characters.');
      return null;
    }

    final effectiveTitle = title.isNotEmpty ? title : _fallbackTitle(body);

    setState(() {
      _isSaving = true;
    });

    try {
      if (_isCreatingMode) {
        final docRef = await FirebaseFirestore.instance
            .collection('memos')
            .add({
              'userId': user.uid,
              'title': effectiveTitle,
              'body': body,
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });

        _originalTitle = effectiveTitle;
        _originalBody = body;
        _currentMemoId = docRef.id;

        if (_titleController.text.trim().isEmpty) {
          _titleController.text = effectiveTitle;
          _titleController.selection = TextSelection.collapsed(
            offset: _titleController.text.length,
          );
        }

        if (!mounted) {
          return _SavedMemo(
            memoId: docRef.id,
            title: effectiveTitle,
            body: body,
          );
        }

        setState(() {
          _isCreatingMode = false;
        });

        if (popAfterCreate) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text('Note saved.'),
                behavior: SnackBarBehavior.floating,
              ),
            );
        } else if (showSuccessMessage) {
          _showMessage('Note saved.');
        }

        return _SavedMemo(memoId: docRef.id, title: effectiveTitle, body: body);
      }

      if (_currentMemoId.isEmpty) {
        throw StateError('Missing memo id.');
      }

      await FirebaseFirestore.instance
          .collection('memos')
          .doc(_currentMemoId)
          .update({
            'title': effectiveTitle,
            'body': body,
            'updatedAt': FieldValue.serverTimestamp(),
          });

      _originalTitle = effectiveTitle;
      _originalBody = body;

      if (!mounted) {
        return _SavedMemo(
          memoId: _currentMemoId,
          title: effectiveTitle,
          body: body,
        );
      }

      if (showSuccessMessage) {
        _showMessage('Note updated.');
      }

      return _SavedMemo(
        memoId: _currentMemoId,
        title: effectiveTitle,
        body: body,
      );
    } catch (_) {
      _showMessage('Failed to save note. Please try again.');
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _scheduleAutosave() {
    _autosaveTimer?.cancel();

    if (_isSaving || _isAnalyzingTask) {
      return;
    }

    if (!_hasChanges || !_hasSavableContent) {
      return;
    }

    _autosaveTimer = Timer(const Duration(milliseconds: 700), () {
      _flushAutosave();
    });
  }

  bool get _hasSavableContent {
    return _titleController.text.trim().isNotEmpty ||
        _bodyController.text.trim().isNotEmpty;
  }

  Future<void> _flushAutosave() async {
    _autosaveTimer?.cancel();
    _autosaveTimer = null;

    if (_isSaving || _isAnalyzingTask || !_hasChanges || !_hasSavableContent) {
      return;
    }

    await _saveMemo(popAfterCreate: false, showSuccessMessage: false);
  }

  void _dismissKeyboard() {
    final currentFocus = FocusScope.of(context);
    if (!currentFocus.hasPrimaryFocus && currentFocus.focusedChild != null) {
      currentFocus.unfocus();
    }
  }

  Future<void> _handleBackNavigation() async {
    _dismissKeyboard();
    await _stopVoiceInputForNavigation();
    await _flushAutosave();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  String _fallbackTitle(String body) {
    final trimmedBody = body.trim();
    if (trimmedBody.isEmpty) {
      return 'Untitled Note';
    }

    final firstLine = trimmedBody.split('\n').first.trim();
    if (firstLine.length <= _generatedTitleLength) {
      return firstLine;
    }
    return firstLine.substring(0, _generatedTitleLength).trimRight();
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _analyzeMemoAndOpenTask() async {
    if (_isSaving || _isAnalyzingTask) {
      return;
    }

    final savedMemo = (_isCreatingMode || _hasChanges)
        ? await _saveMemo(popAfterCreate: false, showSuccessMessage: false)
        : _SavedMemo(
            memoId: _currentMemoId,
            title: _originalTitle,
            body: _originalBody,
          );

    if (savedMemo == null) {
      return;
    }

    final memoTitle = savedMemo.title.trim();
    final memoBody = savedMemo.body.trim();

    if (memoTitle.isEmpty && memoBody.isEmpty) {
      _showMessage('This note is empty.');
      return;
    }

    if (memoBody.isEmpty) {
      _showMessage('Detail cannot be empty.');
      return;
    }

    setState(() {
      _isAnalyzingTask = true;
    });

    try {
      await _stopVoiceInputForNavigation();

      final callable = FirebaseFunctions.instanceFor(
        region: 'australia-southeast1',
      ).httpsCallable('analyzeMemoToTask');

      final result = await callable.call(<String, dynamic>{
        'title': memoTitle,
        'body': memoBody,
        'timezone': DateTime.now().timeZoneName,
        'currentDateISO': _currentDateISO(),
      });

      final data = Map<String, dynamic>.from(result.data as Map);
      final draft = _MemoTaskDraft.fromMap(data);

      if (!mounted) {
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AddTaskScreen(
            initialTitle: draft.title.isNotEmpty ? draft.title : memoTitle,
            initialNotes: draft.notes.isNotEmpty ? draft.notes : memoBody,
            initialDate: draft.date,
            initialTime: draft.time,
            initialCategory: draft.category,
          ),
        ),
      );
    } on FirebaseFunctionsException catch (error) {
      _showMessage(_mapFunctionError(error));
    } catch (_) {
      _showMessage('Failed to analyze memo. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isAnalyzingTask = false;
        });
      }
    }
  }

  String _mapFunctionError(FirebaseFunctionsException error) {
    switch (error.code) {
      case 'unauthenticated':
        return 'Please sign in to continue.';
      case 'invalid-argument':
        return 'This memo does not have enough content to analyze.';
      case 'resource-exhausted':
        return 'Too many requests. Please wait a few seconds.';
      default:
        return error.message ?? 'AI analysis failed. Please try again.';
    }
  }

  String _currentDateISO() {
    final now = DateTime.now();
    final year = now.year.toString().padLeft(4, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  Future<void> _toggleListening() async {
    if (_isSaving || _isAnalyzingTask || _isVoiceTransitioning) {
      return;
    }

    if (_isSpeechActive) {
      await _stopListening();
      return;
    }

    if (!mounted) {
      return;
    }

    final target = _titleFocusNode.hasFocus ? 'title' : 'body';

    _titleFocusNode.unfocus();
    _bodyFocusNode.unfocus();
    FocusScope.of(context).unfocus();

    final listeningTarget = target;
    final controller = listeningTarget == 'title'
        ? _titleController
        : _bodyController;
    var voiceBaseText = controller.text;

    if (voiceBaseText.isNotEmpty &&
        !voiceBaseText.endsWith(' ') &&
        !voiceBaseText.endsWith('\n')) {
      voiceBaseText = '$voiceBaseText ';
    }

    setState(() {
      _isVoiceTransitioning = true;
      _listeningTarget = listeningTarget;
      _soundLevel = 0;
    });
    _startVoiceBars();

    final sessionId = ++_voiceSessionId;

    try {
      await _startRealtimeListening(
        sessionId: sessionId,
        controller: controller,
        voiceBaseText: voiceBaseText,
      );
    } catch (_) {
      await _realtimeTranscription.cancel();
      if (!mounted || sessionId != _voiceSessionId) {
        return;
      }

      try {
        await _startDeviceSpeechFallback(
          sessionId: sessionId,
          controller: controller,
          voiceBaseText: voiceBaseText,
        );
      } catch (_) {
        _voiceSessionId++;
        _resetVoiceUiState();
        _showMessage('Unable to start voice input. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isVoiceTransitioning = false;
        });
      }
    }
  }

  Future<void> _startRealtimeListening({
    required int sessionId,
    required TextEditingController controller,
    required String voiceBaseText,
  }) async {
    await _realtimeTranscription.start(
      onTranscriptChanged: (transcript) {
        if (!mounted || sessionId != _voiceSessionId) {
          return;
        }

        _applyVoiceTranscript(controller, voiceBaseText, transcript);
      },
      onSoundLevelChanged: (level) {
        if (!mounted || sessionId != _voiceSessionId) {
          return;
        }

        setState(() {
          _soundLevel = level;
        });
      },
      onSessionEnded: () {
        if (!mounted || sessionId != _voiceSessionId || _isVoiceTransitioning) {
          return;
        }

        setState(() {
          _isListening = false;
          _soundLevel = 0;
        });
        _stopVoiceBars();
      },
    );

    if (!mounted || sessionId != _voiceSessionId) {
      return;
    }

    setState(() {
      _isListening = true;
      _soundLevel = 0;
    });
  }

  Future<void> _startDeviceSpeechFallback({
    required int sessionId,
    required TextEditingController controller,
    required String voiceBaseText,
  }) async {
    final ready = await _ensureSpeechReady();
    if (!ready) {
      throw const RealtimeTranscriptionException(
        'Device speech input is unavailable.',
      );
    }

    await _speech.listen(
      listenFor: const Duration(minutes: 5),
      pauseFor: const Duration(seconds: 8),
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
      ),
      onSoundLevelChange: (level) {
        if (!mounted || sessionId != _voiceSessionId) {
          return;
        }
        setState(() {
          _soundLevel = level;
        });
      },
      onResult: (result) {
        if (!mounted || sessionId != _voiceSessionId) {
          return;
        }

        _applyVoiceTranscript(
          controller,
          voiceBaseText,
          result.recognizedWords,
        );
      },
    );

    if (!mounted || sessionId != _voiceSessionId) {
      return;
    }

    setState(() {
      _isListening = true;
      _soundLevel = 0;
    });
  }

  void _applyVoiceTranscript(
    TextEditingController controller,
    String voiceBaseText,
    String transcript,
  ) {
    final cleanedTranscript = transcript.trim();
    final nextText = cleanedTranscript.isEmpty
        ? voiceBaseText.trimRight()
        : '$voiceBaseText$cleanedTranscript';

    controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
    );
  }

  Future<void> _stopListening() async {
    if (_isVoiceTransitioning) {
      return;
    }

    setState(() {
      _isVoiceTransitioning = true;
    });

    try {
      if (_realtimeTranscription.isActive) {
        await _realtimeTranscription.stop();
      } else if (_speech.isListening || _isListening) {
        await _speech.stop();
      }
    } catch (_) {
      // Even if the platform stop fails, keep local state recoverable.
    } finally {
      _voiceSessionId++;
      _resetVoiceUiState();
      if (mounted) {
        setState(() {
          _isVoiceTransitioning = false;
        });
      }
    }
  }

  void _handleSpeechStatus(String status) {
    if (!mounted) {
      return;
    }

    if (status == stt.SpeechToText.listeningStatus) {
      setState(() {
        _isListening = true;
      });
      _startVoiceBars();
      return;
    }

    if (status == stt.SpeechToText.doneStatus) {
      _voiceSessionId++;
    }

    if (status == stt.SpeechToText.doneStatus ||
        status == stt.SpeechToText.notListeningStatus) {
      setState(() {
        _isListening = false;
        _soundLevel = 0;
      });
      _stopVoiceBars();
    }
  }

  void _handleSpeechError(dynamic error) {
    if (!mounted) {
      return;
    }

    _voiceSessionId++;
    _resetVoiceUiState();

    final errorMessage = '${error?.errorMsg ?? error}'.toLowerCase();
    final isPermissionError =
        errorMessage.contains('permission') ||
        errorMessage.contains('recognizer_disabled');

    if (isPermissionError) {
      _showMessage(
        'Microphone or speech permission is unavailable. Please check system settings.',
      );
      return;
    }

    if (error?.permanent != true) {
      _showMessage('Voice input stopped. Please try again.');
    }
  }

  void _startVoiceBars() {
    if (!_voiceBarsController.isAnimating) {
      _voiceBarsController.repeat();
    }
  }

  void _stopVoiceBars() {
    _voiceBarsController.stop();
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _voiceBarsController.dispose();
    unawaited(_realtimeTranscription.dispose());
    _speech.cancel();
    _titleFocusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _bodyFocusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _bodyScrollController.dispose();
    _titleController
      ..removeListener(_handleFieldChanged)
      ..dispose();
    _bodyController
      ..removeListener(_handleBodyChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
        await _handleBackNavigation();
      },
      child: GestureDetector(
        onTap: _dismissKeyboard,
        behavior: HitTestBehavior.translucent,
        child: Scaffold(
          backgroundColor: _background,
          resizeToAvoidBottomInset: false,
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
                    height: double.infinity,
                    color: _background,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Column(
                            children: [
                              const SizedBox(height: 89),
                              Expanded(child: _buildContent(context)),
                            ],
                          ),
                        ),
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: _buildAppBar(context),
                        ),
                        Positioned(
                          left: 24,
                          right: 24,
                          bottom: 20,
                          child: _buildBottomActions(context),
                        ),
                      ],
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

  Widget _buildAppBar(BuildContext context) {
    return Container(
      height: 89,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      decoration: BoxDecoration(
        color: AppTheme.headerBackground,
        boxShadow: const [AppTheme.headerShadow],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          AppTheme.backButton(context, onPressed: _handleBackNavigation),
          Expanded(
            child: Center(
              child: Text(
                _isCreatingMode ? 'New Note' : 'Note Detail',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _primaryColor,
                  letterSpacing: -0.45,
                ),
              ),
            ),
          ),
          _buildAddTaskAction(),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportConfig = _detailViewportConfig(
          availableHeight: constraints.maxHeight,
          keyboardInset: keyboardInset,
        );

        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            24,
            0,
            24,
            viewportConfig.scrollBottomPadding,
          ),
          child: Column(
            children: [
              const SizedBox(height: 39),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _cardBorder),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFAC638).withValues(alpha: 0.05),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(25, 21, 25, 25),
                child: LayoutBuilder(
                  builder: (context, cardConstraints) {
                    return _buildEditableBody(
                      context,
                      maxBodyHeight: viewportConfig.maxBodyHeight,
                      contentWidth: cardConstraints.maxWidth,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  _DetailViewportConfig _detailViewportConfig({
    required double availableHeight,
    required double keyboardInset,
  }) {
    final scrollBottomPadding = math.max(
      _bottomActionsReservedHeight(),
      keyboardInset + 32,
    );
    final calculatedHeight = availableHeight - scrollBottomPadding - 132;

    return _DetailViewportConfig(
      maxBodyHeight: calculatedHeight
          .clamp(_minDetailBodyHeight, _maxDetailBodyHeight)
          .toDouble(),
      scrollBottomPadding: scrollBottomPadding,
    );
  }

  double _bottomActionsReservedHeight() {
    return (_isListening || _isVoiceTransitioning) ? 208 : 132;
  }

  double _resolveDetailBodyHeight(
    BuildContext context, {
    required String text,
    required String placeholder,
    required double maxBodyHeight,
    required double contentWidth,
  }) {
    final usableWidth = math.max(0.0, contentWidth - 6);
    if (usableWidth == 0) {
      return _minDetailBodyHeight;
    }

    final sampleText = text.isEmpty ? placeholder : text;
    final normalizedText = sampleText.endsWith('\n')
        ? '$sampleText '
        : sampleText;
    final painter = TextPainter(
      text: TextSpan(text: normalizedText, style: _bodyStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: null,
    )..layout(maxWidth: usableWidth);

    return (painter.height + 14)
        .clamp(_minDetailBodyHeight, maxBodyHeight)
        .toDouble();
  }

  Widget _buildEditableBody(
    BuildContext context, {
    required double maxBodyHeight,
    required double contentWidth,
  }) {
    final bodyHeight = _resolveDetailBodyHeight(
      context,
      text: _bodyController.text,
      placeholder: 'Write your memo here...',
      maxBodyHeight: maxBodyHeight,
      contentWidth: contentWidth,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _titleController,
          focusNode: _titleFocusNode,
          maxLines: 2,
          maxLength: _maxTitleLength,
          inputFormatters: [LengthLimitingTextInputFormatter(_maxTitleLength)],
          textInputAction: TextInputAction.next,
          onTapOutside: (_) => _dismissKeyboard(),
          decoration: InputDecoration(
            hintText: 'Note title',
            border: InputBorder.none,
            isCollapsed: true,
            counterText: '',
          ),
          style: _titleStyle,
        ),
        const SizedBox(height: 16),
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: bodyHeight,
          child: Scrollbar(
            controller: _bodyScrollController,
            thumbVisibility: true,
            radius: const Radius.circular(999),
            child: TextField(
              controller: _bodyController,
              focusNode: _bodyFocusNode,
              scrollController: _bodyScrollController,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              minLines: null,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              onTapOutside: (_) => _dismissKeyboard(),
              scrollPadding: EdgeInsets.only(
                bottom: math.max(
                  32,
                  MediaQuery.viewInsetsOf(context).bottom + 16,
                ),
              ),
              decoration: const InputDecoration(
                hintText: 'Write your note here...',
                border: InputBorder.none,
                isCollapsed: true,
              ),
              style: _bodyStyle,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActions(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isListening || _isVoiceTransitioning) ...[
          _buildListeningBanner(),
          const SizedBox(height: 12),
        ],
        _buildVoiceInputButton(),
      ],
    );
  }

  Widget _buildAddTaskAction() {
    final isDisabled = _isAnalyzingTask || _isSaving;

    return Opacity(
      opacity: isDisabled ? 0.72 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: isDisabled ? null : _analyzeMemoAndOpenTask,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: _accentColor.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFFFE3A3)),
            boxShadow: [
              BoxShadow(
                color: _accentColor.withValues(alpha: 0.1),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: _isAnalyzingTask || _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _accentColor,
                    ),
                  )
                : const Icon(
                    Icons.auto_awesome_rounded,
                    color: Color(0xFF9A6B00),
                    size: 20,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceInputButton() {
    const targetLabel = 'Content';
    final isVoiceButtonDisabled =
        _isSaving || _isAnalyzingTask || _isVoiceTransitioning;
    final statusLabel = _isVoiceTransitioning
        ? (_isSpeechActive
              ? 'Stopping voice for $targetLabel'
              : 'Preparing voice for $targetLabel')
        : (_isListening
              ? 'Listening for $targetLabel'
              : 'Voice input for $targetLabel');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          statusLabel,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        IgnorePointer(
          ignoring: isVoiceButtonDisabled,
          child: Opacity(
            opacity: isVoiceButtonDisabled ? 0.72 : 1,
            child: GestureDetector(
              onTap: _toggleListening,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _isListening
                        ? const [Color(0xFFF59E0B), Color(0xFFEA580C)]
                        : const [Color(0xFFFFF6D8), Color(0xFFF7E6A8)],
                  ),
                  border: Border.all(
                    color: _isListening
                        ? const Color(0xFFF59E0B)
                        : const Color(0x33FAC638),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color:
                          (_isListening
                                  ? const Color(0xFFF59E0B)
                                  : const Color(0xFFFAC638))
                              .withValues(alpha: 0.24),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Center(
                  child: _isVoiceTransitioning
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _primaryColor,
                            ),
                          ),
                        )
                      : Icon(
                          _isListening ? Icons.mic : Icons.mic_none_rounded,
                          color: _isListening ? Colors.white : _accentColor,
                          size: 30,
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildListeningBanner() {
    final targetLabel = _listeningTarget == 'title' ? 'Title' : 'Content';
    final statusLabel = _isVoiceTransitioning && !_isListening
        ? 'Preparing voice for $targetLabel'
        : 'Listening to $targetLabel';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x22F59E0B)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _VoiceBars(
              animation: _voiceBarsController,
              level: _soundLevel,
              color: _accentColor,
            ),
          ),
          const SizedBox(width: 14),
          Text(
            statusLabel,
            style: const TextStyle(
              color: Color(0xFF334155),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedMemo {
  const _SavedMemo({
    required this.memoId,
    required this.title,
    required this.body,
  });

  final String memoId;
  final String title;
  final String body;
}

class _DetailViewportConfig {
  const _DetailViewportConfig({
    required this.maxBodyHeight,
    required this.scrollBottomPadding,
  });

  final double maxBodyHeight;
  final double scrollBottomPadding;
}

class _VoiceBars extends StatelessWidget {
  const _VoiceBars({
    required this.animation,
    required this.level,
    required this.color,
  });

  final Animation<double> animation;
  final double level;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final normalizedLevel = level.isFinite
            ? ((level + 2) / 12).clamp(0.15, 1.0)
            : 0.2;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(10, (index) {
            final phase = animation.value * math.pi * 2 + index * 0.55;
            final height = 10 + math.sin(phase).abs() * 20 * normalizedLevel;

            return Container(
              width: 5,
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

class _MemoTaskDraft {
  const _MemoTaskDraft({
    required this.title,
    required this.notes,
    required this.category,
    required this.date,
    required this.time,
  });

  final String title;
  final String notes;
  final String? category;
  final DateTime? date;
  final TimeOfDay? time;

  factory _MemoTaskDraft.fromMap(Map<String, dynamic> map) {
    final date = _parseDate(map['dateISO'] as String?);
    final time = _parseTime(map['time24h'] as String?);

    return _MemoTaskDraft(
      title: (map['title'] as String? ?? '').trim(),
      notes: (map['notes'] as String? ?? '').trim(),
      category: (map['category'] as String?)?.trim(),
      date: date,
      time: time,
    );
  }

  static DateTime? _parseDate(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(value.trim());
  }

  static TimeOfDay? _parseTime(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final parts = value.trim().split(':');
    if (parts.length != 2) {
      return null;
    }

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      return null;
    }
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return null;
    }

    return TimeOfDay(hour: hour, minute: minute);
  }
}
