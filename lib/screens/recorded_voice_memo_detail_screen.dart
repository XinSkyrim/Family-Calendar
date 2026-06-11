import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../themes/app_theme.dart';
import 'add_task_screen.dart';

class RecordedVoiceMemoDetailScreen extends StatefulWidget {
  const RecordedVoiceMemoDetailScreen({
    super.key,
    required this.memoId,
    required this.title,
    required this.body,
    required this.audioUrl,
    required this.localAudioPath,
    required this.audioStoragePath,
    required this.duration,
    required this.createdAt,
  });

  final String memoId;
  final String title;
  final String body;
  final String audioUrl;
  final String localAudioPath;
  final String audioStoragePath;
  final Duration duration;
  final DateTime createdAt;

  @override
  State<RecordedVoiceMemoDetailScreen> createState() =>
      _RecordedVoiceMemoDetailScreenState();
}

class _RecordedVoiceMemoDetailScreenState
    extends State<RecordedVoiceMemoDetailScreen> {
  static const _background = AppTheme.pageBackground;
  static const _primaryColor = Color(0xFF0F172A);
  static const _accentColor = Color(0xFFFAC638);
  static const _voiceTint = Color(0xFFFFF8E3);
  static const double _playerCardHeight = 208;
  static const double _notesCardHeight = 300;

  late final AudioPlayer _player;
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  late final FocusNode _bodyFocusNode;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _memoSub;
  Timer? _autosaveTimer;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  Duration? _scrubPosition;
  bool _isLoadingAudio = true;
  bool _isPlaying = false;
  bool _isSaving = false;
  bool _isGeneratingAiNote = false;
  bool _isSummaryRequestInFlight = false;
  bool _isDeleting = false;
  bool _isConvertingToCalendar = false;
  bool _isScrubbing = false;
  late String _originalTitle;
  late String _originalBody;
  String _aiSummaryStatus = '';
  String? _audioError;

  bool get _hasChanges {
    return _titleController.text.trim() != _originalTitle.trim() ||
        _bodyController.text.trim() != _originalBody.trim();
  }

  bool get _isSummarizingVoiceNote {
    return _isSummaryRequestInFlight || _isGeneratingAiNote;
  }

  @override
  void initState() {
    super.initState();
    _duration = widget.duration;
    _player = AudioPlayer();
    _originalTitle = _isUnsetTitle(widget.title)
        ? _autoTitle(widget.createdAt)
        : widget.title;
    _originalBody = widget.body;
    _titleController = TextEditingController(text: _originalTitle)
      ..addListener(_handleTitleChanged);
    _bodyController = TextEditingController(text: _originalBody)
      ..addListener(_scheduleAutosave);
    _bodyFocusNode = FocusNode();
    _bindPlayer();
    _bindMemoUpdates();
    _loadAudio();
  }

  void _bindPlayer() {
    _playerStateSub = _player.playerStateStream.listen((state) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPlaying = state.playing;
        if (state.processingState == ProcessingState.completed) {
          _isPlaying = false;
        }
      });
    });
    _durationSub = _player.durationStream.listen((duration) {
      if (!mounted || duration == null) {
        return;
      }
      setState(() {
        _duration = duration;
      });
    });
    _positionSub = _player.positionStream.listen((position) {
      if (!mounted || _isScrubbing) {
        return;
      }
      setState(() {
        _position = position;
      });
    });
  }

  Future<void> _loadAudio() async {
    try {
      if (widget.localAudioPath.isNotEmpty &&
          File(widget.localAudioPath).existsSync()) {
        await _player.setFilePath(widget.localAudioPath);
      } else if (await _loadCachedAudio()) {
        // Cached remote audio is ready.
      } else {
        await _loadRemoteAudio();
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingAudio = false;
        _audioError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingAudio = false;
        _audioError = _audioUnavailableMessage(error);
      });
    }
  }

  Future<bool> _loadCachedAudio() async {
    final cacheFile = await _cachedAudioFile();
    if (!await cacheFile.exists()) {
      return false;
    }

    if (await cacheFile.length() <= 0) {
      return false;
    }

    await _player.setFilePath(cacheFile.path);
    return true;
  }

  Future<File> _cachedAudioFile() async {
    final cacheDir = await getTemporaryDirectory();
    final audioDir = Directory(
      '${cacheDir.path}${Platform.pathSeparator}voice_memos',
    );
    if (!await audioDir.exists()) {
      await audioDir.create(recursive: true);
    }

    final rawKey = widget.memoId.trim().isNotEmpty
        ? widget.memoId.trim()
        : widget.audioStoragePath.trim().isNotEmpty
        ? widget.audioStoragePath.trim()
        : widget.audioUrl.trim();
    final safeKey = rawKey.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    return File('${audioDir.path}${Platform.pathSeparator}$safeKey.m4a');
  }

  String _audioUnavailableMessage(Object error) {
    final hasLocalPath = widget.localAudioPath.trim().isNotEmpty;
    final hasRemoteUrl = widget.audioUrl.trim().isNotEmpty;
    final hasStoragePath = widget.audioStoragePath.trim().isNotEmpty;

    if (!hasRemoteUrl && !hasStoragePath) {
      return hasLocalPath
          ? 'Audio upload did not finish, and the local file is no longer available on this device.'
          : 'Audio source is missing.';
    }

    return 'Audio could not be loaded. Please check your connection and Storage permissions.';
  }

  Future<void> _loadRemoteAudio() async {
    final audioUrl = widget.audioUrl.trim();
    final storagePath = widget.audioStoragePath.trim();

    if (audioUrl.isNotEmpty) {
      try {
        await _cacheRemoteAudioFromUrl(audioUrl);
        return;
      } catch (_) {
        if (storagePath.isEmpty) {
          rethrow;
        }
      }
    }

    if (storagePath.isEmpty) {
      throw StateError('Missing audio source.');
    }

    final freshUrl = await FirebaseStorage.instance
        .ref(storagePath)
        .getDownloadURL();
    await _cacheRemoteAudioFromUrl(freshUrl);

    if (widget.memoId.isNotEmpty && freshUrl != audioUrl) {
      unawaited(
        FirebaseFirestore.instance.collection('memos').doc(widget.memoId).set({
          'audioUrl': freshUrl,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)),
      );
    }
  }

  Future<void> _cacheRemoteAudioFromUrl(String url) async {
    final cacheFile = await _cachedAudioFile();
    try {
      await FirebaseStorage.instance.refFromURL(url).writeToFile(cacheFile);
      await _player.setFilePath(cacheFile.path);
    } catch (_) {
      await _player.setUrl(url);
    }
  }

  void _bindMemoUpdates() {
    if (widget.memoId.isEmpty) {
      return;
    }

    _memoSub = FirebaseFirestore.instance
        .collection('memos')
        .doc(widget.memoId)
        .snapshots()
        .listen((doc) {
          final data = doc.data();
          if (!mounted || data == null) {
            return;
          }

          final status = (data['aiSummaryStatus'] as String?) ?? '';
          final isGenerating = status == 'pending' || status == 'processing';
          final body = (data['body'] as String?)?.trim() ?? '';

          if (body.isNotEmpty &&
              body != _originalBody &&
              !_bodyFocusNode.hasFocus &&
              !_hasChanges) {
            _originalBody = body;
            _bodyController.text = body;
          }

          if (_isGeneratingAiNote != isGenerating ||
              _aiSummaryStatus != status) {
            setState(() {
              _isGeneratingAiNote = isGenerating;
              _aiSummaryStatus = status;
            });
          }
        });
  }

  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    if (_isSaving || !_hasChanges) {
      return;
    }
    _autosaveTimer = Timer(const Duration(milliseconds: 700), _flushAutosave);
  }

  Future<void> _flushAutosave() async {
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    if (_isSaving || !_hasChanges) {
      return;
    }
    await _saveMemo(showMessage: false);
  }

  Future<void> _saveMemo({required bool showMessage}) async {
    final title = _titleController.text.trim().isEmpty
        ? _autoTitle(widget.createdAt)
        : _titleController.text.trim();
    final body = _bodyController.text.trim();

    setState(() {
      _isSaving = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('memos')
          .doc(widget.memoId)
          .update({
            'title': title,
            'body': body,
            'memoType': 'voice',
            'audioUrl': widget.audioUrl,
            'audioStoragePath': widget.audioStoragePath,
            'localAudioPath': widget.localAudioPath,
            'audioDurationMillis': _duration.inMilliseconds,
            'createdAtLocalMillis': widget.createdAt.millisecondsSinceEpoch,
            'updatedAt': FieldValue.serverTimestamp(),
          });

      _originalTitle = title;
      _originalBody = body;

      if (showMessage) {
        _showMessage('Voice note saved.');
      }
    } catch (_) {
      _showMessage('Failed to save voice note. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _handleBackNavigation() async {
    FocusScope.of(context).unfocus();
    await _player.pause();
    await _flushAutosave();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _confirmAndDeleteMemo() async {
    if (_isDeleting) {
      return;
    }

    final confirmed = await _showDeleteMemoDialog();
    if (!mounted || !confirmed) {
      return;
    }

    FocusScope.of(context).unfocus();
    _autosaveTimer?.cancel();
    await _player.pause();

    setState(() {
      _isDeleting = true;
    });

    try {
      if (widget.audioStoragePath.isNotEmpty) {
        try {
          await FirebaseStorage.instance.ref(widget.audioStoragePath).delete();
        } catch (_) {
          // The note should still be removable if storage cleanup fails.
        }
      }

      await FirebaseFirestore.instance
          .collection('memos')
          .doc(widget.memoId)
          .delete();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Voice note deleted.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) {
        return;
      }

      _showMessage('Failed to delete voice note. Please try again.');
      setState(() {
        _isDeleting = false;
      });
    }
  }

  Future<void> _summarizeVoiceMemo() async {
    debugPrint(
      'summarize voice memo tapped: memoId=${widget.memoId}, '
      'audioStoragePathEmpty=${widget.audioStoragePath.isEmpty}',
    );

    if (_isSummarizingVoiceNote || _isSaving || _isDeleting) {
      return;
    }

    if (widget.audioStoragePath.isEmpty) {
      _showMessage('Uploaded audio is not available for summarizing.');
      return;
    }

    FocusScope.of(context).unfocus();
    await _flushAutosave();
    if (!mounted) {
      return;
    }

    setState(() {
      _isSummaryRequestInFlight = true;
      _isGeneratingAiNote = true;
      _aiSummaryStatus = 'pending';
    });

    try {
      await FirebaseFirestore.instance
          .collection('memos')
          .doc(widget.memoId)
          .update({
            'aiSummaryStatus': 'pending',
            'aiSummaryError': FieldValue.delete(),
            'updatedAt': FieldValue.serverTimestamp(),
          });

      final callable =
          FirebaseFunctions.instanceFor(
            region: 'australia-southeast1',
          ).httpsCallable(
            'summarizeRecordedVoiceMemo',
            options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
          );
      await callable.call(<String, dynamic>{'memoId': widget.memoId});

      if (!mounted) {
        return;
      }

      setState(() {
        _isSummaryRequestInFlight = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSummaryRequestInFlight = false;
        _isGeneratingAiNote = false;
        _aiSummaryStatus = 'failed';
      });
      _showMessage('Failed to summarize voice note. Please try again.');
    }
  }

  Future<void> _convertSummaryToCalendarEvent() async {
    if (_isConvertingToCalendar ||
        _isSummarizingVoiceNote ||
        _isSaving ||
        _isDeleting) {
      return;
    }

    await _flushAutosave();
    if (!mounted) {
      return;
    }

    final memoTitle = _titleController.text.trim().isEmpty
        ? _autoTitle(widget.createdAt)
        : _titleController.text.trim();
    final memoBody = _bodyController.text.trim();

    if (memoBody.isEmpty) {
      _showMessage('Summarize this voice note or add notes before converting.');
      return;
    }

    FocusScope.of(context).unfocus();
    await _player.pause();

    setState(() {
      _isConvertingToCalendar = true;
    });

    try {
      final callable =
          FirebaseFunctions.instanceFor(
            region: 'australia-southeast1',
          ).httpsCallable(
            'analyzeMemoToTask',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
          );

      final result = await callable
          .call(<String, dynamic>{
            'title': memoTitle,
            'body': memoBody,
            'timezone': DateTime.now().timeZoneName,
            'currentDateISO': _currentDateISO(),
          })
          .timeout(const Duration(seconds: 15));

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
      debugPrint(
        'analyzeMemoToTask failed: code=${error.code}, '
        'message=${error.message}, details=${error.details}',
      );
      await _openManualCalendarFallback(
        memoTitle: memoTitle,
        memoBody: memoBody,
      );
    } on TimeoutException catch (error) {
      debugPrint('analyzeMemoToTask timed out: $error');
      await _openManualCalendarFallback(
        memoTitle: memoTitle,
        memoBody: memoBody,
      );
    } catch (error) {
      debugPrint('analyzeMemoToTask unexpected error: $error');
      await _openManualCalendarFallback(
        memoTitle: memoTitle,
        memoBody: memoBody,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isConvertingToCalendar = false;
        });
      }
    }
  }

  Future<void> _openManualCalendarFallback({
    required String memoTitle,
    required String memoBody,
  }) async {
    if (!mounted) {
      return;
    }

    _showMessage(
      'No calendar details were detected. You can fill them in manually.',
    );

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddTaskScreen(
          initialTitle: memoTitle.isNotEmpty ? memoTitle : null,
          initialNotes: memoBody.isNotEmpty ? memoBody : null,
        ),
      ),
    );
  }

  String _currentDateISO() {
    final now = DateTime.now();
    final year = now.year.toString().padLeft(4, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  Future<bool> _showDeleteMemoDialog() async {
    final title = _titleController.text.trim().isEmpty
        ? _autoTitle(widget.createdAt)
        : _titleController.text.trim();
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 22,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 10,
          backgroundColor: Colors.white,
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: const Color.fromRGBO(236, 91, 19, 0.05),
              ),
              boxShadow: [
                BoxShadow(
                  color: _accentColor.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 45,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppTheme.lightBackground,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Center(
                  child: Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: AppTheme.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: AppTheme.error,
                      size: 31,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Delete this voice note?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: _primaryColor,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'This will permanently remove "$title".',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.mutedText,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: () => Navigator.of(dialogContext).pop(true),
                  child: Container(
                    width: double.infinity,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppTheme.error,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.error.withValues(alpha: 0.18),
                          blurRadius: 15,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        'Delete',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.lightBackground),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _primaryColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    return result ?? false;
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

  Future<void> _togglePlayback() async {
    if (_isLoadingAudio || _audioError != null) {
      return;
    }

    if (_isPlaying) {
      await _player.pause();
      return;
    }

    if (_duration > Duration.zero && _position >= _duration) {
      await _player.seek(Duration.zero);
    }
    await _player.play();
  }

  Future<void> _seekRelative(Duration offset) async {
    if (_isLoadingAudio || _audioError != null) {
      return;
    }
    final duration = _duration > Duration.zero ? _duration : widget.duration;
    final nextMillis = (_position + offset).inMilliseconds
        .clamp(0, math.max(duration.inMilliseconds, 0))
        .toInt();
    await _player.seek(Duration(milliseconds: nextMillis));
  }

  void _beginScrub() {
    if (_isLoadingAudio || _audioError != null || _duration <= Duration.zero) {
      return;
    }
    setState(() {
      _isScrubbing = true;
      _scrubPosition = _position;
    });
  }

  void _updateScrub(double localDx, double width) {
    if (!_isScrubbing || width <= 0 || _duration <= Duration.zero) {
      return;
    }
    final fraction = (localDx / width).clamp(0.0, 1.0);
    setState(() {
      _scrubPosition = Duration(
        milliseconds: (_duration.inMilliseconds * fraction).round(),
      );
    });
  }

  Future<void> _endScrub() async {
    if (!_isScrubbing) {
      return;
    }
    final target = _scrubPosition;
    setState(() {
      _isScrubbing = false;
      _scrubPosition = null;
      if (target != null) {
        _position = target;
      }
    });
    if (target != null) {
      await _player.seek(target);
    }
  }

  void _dismissKeyboard() {
    final focus = FocusScope.of(context);
    if (!focus.hasPrimaryFocus && focus.focusedChild != null) {
      focus.unfocus();
    }
  }

  String _autoTitle(DateTime createdAt) {
    return intl.DateFormat('yyyy-MM-dd HH:mm').format(createdAt.toLocal());
  }

  bool _isUnsetTitle(String title) {
    final normalized = title.trim();
    return normalized.isEmpty || normalized == 'Voice Note';
  }

  void _handleTitleChanged() {
    _scheduleAutosave();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _playerStateSub?.cancel();
    _durationSub?.cancel();
    _positionSub?.cancel();
    _memoSub?.cancel();
    _player.dispose();
    _bodyFocusNode.dispose();
    _titleController
      ..removeListener(_handleTitleChanged)
      ..dispose();
    _bodyController.dispose();
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
        behavior: HitTestBehavior.translucent,
        onTap: _dismissKeyboard,
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
                              _buildAppBar(context),
                              Expanded(child: _buildContent(context)),
                            ],
                          ),
                        ),
                        Positioned(
                          left: 24,
                          right: 24,
                          bottom: 20,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: _AddToCalendarButton(
                              isConverting: _isConvertingToCalendar,
                              isDisabled:
                                  _isSummarizingVoiceNote ||
                                  _isSaving ||
                                  _isDeleting,
                              onTap: _convertSummaryToCalendarEvent,
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _buildAppBarTitle(),
            ),
          ),
          _buildDeleteAction(),
        ],
      ),
    );
  }

  Widget _buildAppBarTitle() {
    return TextField(
      controller: _titleController,
      maxLines: 1,
      textAlign: TextAlign.center,
      textInputAction: TextInputAction.done,
      scrollPhysics: const BouncingScrollPhysics(),
      onSubmitted: (_) => unawaited(_flushAutosave()),
      onTapOutside: (_) => _dismissKeyboard(),
      decoration: InputDecoration(
        hintText: _autoTitle(widget.createdAt),
        border: InputBorder.none,
        isCollapsed: true,
        contentPadding: EdgeInsets.zero,
      ),
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: _primaryColor,
      ),
    );
  }

  Widget _buildDeleteAction() {
    final isDisabled = _isDeleting || _isSaving;

    return Opacity(
      opacity: isDisabled ? 0.72 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: isDisabled ? null : _confirmAndDeleteMemo,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppTheme.error.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppTheme.error.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(
                color: AppTheme.error.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: isDisabled
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.error,
                    ),
                  )
                : const Icon(
                    Icons.delete_outline_rounded,
                    color: AppTheme.error,
                    size: 20,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        24,
        28,
        24,
        math.max(104, keyboardInset + 32),
      ),
      child: Column(
        children: [
          _buildPlayerCard(),
          const SizedBox(height: 18),
          _buildNotesSection(context),
        ],
      ),
    );
  }

  Widget _buildPlayerCard() {
    final duration = _duration > Duration.zero ? _duration : widget.duration;
    final durationMillis = math.max(duration.inMilliseconds, 1);
    final displayPosition = _scrubPosition ?? _position;
    final positionMillis = displayPosition.inMilliseconds
        .clamp(0, durationMillis)
        .toDouble();
    final canSeek =
        !_isLoadingAudio && _audioError == null && duration > Duration.zero;
    final progress = positionMillis / durationMillis;

    return Container(
      width: double.infinity,
      height: _playerCardHeight,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      decoration: BoxDecoration(
        color: _voiceTint,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(Duration(milliseconds: positionMillis.round())),
                style: const TextStyle(
                  color: Color(0xFF475569),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                _formatDuration(duration),
                style: const TextStyle(
                  color: Color(0xFF475569),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 70,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final waveformWidth = math.max(constraints.maxWidth, 1.0);

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: canSeek
                      ? (details) {
                          _beginScrub();
                          _updateScrub(details.localPosition.dx, waveformWidth);
                        }
                      : null,
                  onHorizontalDragUpdate: canSeek
                      ? (details) {
                          _updateScrub(details.localPosition.dx, waveformWidth);
                        }
                      : null,
                  onHorizontalDragEnd: canSeek ? (_) => _endScrub() : null,
                  onHorizontalDragCancel: canSeek ? _endScrub : null,
                  onTapDown: canSeek
                      ? (details) {
                          _beginScrub();
                          _updateScrub(details.localPosition.dx, waveformWidth);
                        }
                      : null,
                  onTapUp: canSeek ? (_) => _endScrub() : null,
                  onTapCancel: canSeek ? _endScrub : null,
                  child: CustomPaint(
                    painter: _VoiceWaveformPainter(
                      progress: progress,
                      activeColor: AppTheme.accent,
                      inactiveColor: const Color(0xFFF1E8D8),
                    ),
                    child: const SizedBox.expand(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          if (_audioError != null)
            Text(
              _audioError!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.error,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _RoundPlayerButton(
                  icon: Icons.replay_10_rounded,
                  onTap: () => _seekRelative(const Duration(seconds: -15)),
                  isPrimary: false,
                ),
                const SizedBox(width: 18),
                _RoundPlayerButton(
                  icon: _isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  onTap: _togglePlayback,
                  isPrimary: true,
                  isBusy: _isLoadingAudio,
                ),
                const SizedBox(width: 18),
                _RoundPlayerButton(
                  icon: Icons.forward_10_rounded,
                  onTap: () => _seekRelative(const Duration(seconds: 15)),
                  isPrimary: false,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildNotesSection(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: _notesCardHeight,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SummarizeWithAiButton(
            onTap: _summarizeVoiceMemo,
            isDisabled: _isSaving || _isDeleting,
            isLoading: _isSummarizingVoiceNote,
          ),
          const SizedBox(height: 14),
          Expanded(
            child: TextField(
              controller: _bodyController,
              focusNode: _bodyFocusNode,
              keyboardType: TextInputType.multiline,
              expands: true,
              maxLines: null,
              minLines: null,
              textAlignVertical: TextAlignVertical.top,
              onTapOutside: (_) => _dismissKeyboard(),
              decoration: const InputDecoration(
                hintText: 'Write notes for this voice note...',
                border: InputBorder.none,
                isCollapsed: true,
              ),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: Color(0xFF334155),
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _RoundPlayerButton extends StatelessWidget {
  const _RoundPlayerButton({
    required this.icon,
    required this.onTap,
    required this.isPrimary,
    this.isBusy = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool isPrimary;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isBusy ? null : onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: isPrimary ? _RecordedVoiceMemoColors.primary : Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isPrimary ? 0.12 : 0.06),
              blurRadius: isPrimary ? 14 : 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: isBusy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
              : Icon(
                  icon,
                  color: isPrimary ? Colors.white : const Color(0xFF111827),
                  size: 26,
                ),
        ),
      ),
    );
  }
}

class _AiSummaryButtonMetrics {
  static const double _height = 44;
  static const double _width = 188;
}

class _RainbowText extends StatelessWidget {
  const _RainbowText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) {
        return const LinearGradient(
          colors: [
            Color(0xFFEF4444),
            Color(0xFFF59E0B),
            Color(0xFFEAB308),
            Color(0xFF22C55E),
            Color(0xFF06B6D4),
            Color(0xFF3B82F6),
            Color(0xFFA855F7),
          ],
        ).createShader(bounds);
      },
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
          height: 20 / 14,
        ),
      ),
    );
  }
}

class _RainbowBorder extends StatelessWidget {
  const _RainbowBorder({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: const LinearGradient(
          colors: [
            Color(0xFFEF4444),
            Color(0xFFF59E0B),
            Color(0xFFEAB308),
            Color(0xFF22C55E),
            Color(0xFF06B6D4),
            Color(0xFF3B82F6),
            Color(0xFFA855F7),
          ],
        ),
      ),
      child: Padding(padding: const EdgeInsets.all(1.4), child: child),
    );
  }
}

class _AddToCalendarButton extends StatelessWidget {
  const _AddToCalendarButton({
    required this.isConverting,
    required this.isDisabled,
    required this.onTap,
  });

  final bool isConverting;
  final bool isDisabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: isDisabled ? 0.72 : 1,
      child: GestureDetector(
        onTap: isDisabled || isConverting ? null : onTap,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [AppTheme.accent, AppTheme.accentDark],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppTheme.accent.withValues(alpha: 0.2),
                blurRadius: 15,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: isConverting
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Converting...',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  )
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.event_available_rounded,
                        color: Colors.black87,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Add to Calendar',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _SummarizeWithAiButton extends StatelessWidget {
  const _SummarizeWithAiButton({
    required this.onTap,
    required this.isDisabled,
    required this.isLoading,
  });

  static const double _height = _AiSummaryButtonMetrics._height;
  static const double _width = _AiSummaryButtonMetrics._width;

  final VoidCallback onTap;
  final bool isDisabled;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Opacity(
        opacity: isDisabled ? 0.6 : 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: _RainbowBorder(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: isDisabled || isLoading ? null : onTap,
                  child: Container(
                    width: _width,
                    height: _height,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF9EE).withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Transform.translate(
                          offset: const Offset(-3, 0),
                          child: isLoading
                              ? const SizedBox(
                                  width: 17,
                                  height: 17,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFFA855F7),
                                  ),
                                )
                              : const Icon(
                                  Icons.auto_awesome_rounded,
                                  color: Color(0xFFA855F7),
                                  size: 18,
                                ),
                        ),
                        const SizedBox(width: 4),
                        _RainbowText(
                          isLoading ? 'Summarizing...' : 'Summarize with AI',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VoiceWaveformPainter extends CustomPainter {
  const _VoiceWaveformPainter({
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final barCount = 42;
    final spacing = size.width / barCount;
    final progressX = size.width * progress.clamp(0, 1);

    for (var index = 0; index < barCount; index++) {
      final phase = index * 0.72;
      final wave = (math.sin(phase) * 0.5 + math.sin(phase * 1.7) * 0.5).abs();
      final height = 14 + wave * 38;
      final x = spacing * index + spacing * 0.5;
      final paint = Paint()
        ..color = x <= progressX ? activeColor : inactiveColor
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(x, centerY - height / 2),
        Offset(x, centerY + height / 2),
        paint,
      );
    }

    final progressPaint = Paint()
      ..color = activeColor
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(progressX, 8),
      Offset(progressX, size.height - 8),
      progressPaint,
    );

    final thumbPaint = Paint()..color = activeColor;
    canvas.drawCircle(Offset(progressX, centerY), 5, thumbPaint);
  }

  @override
  bool shouldRepaint(covariant _VoiceWaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor;
  }
}

class _RecordedVoiceMemoColors {
  static const primary = Color(0xFF111827);
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
