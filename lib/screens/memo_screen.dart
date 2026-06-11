import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../navigation/app_bottom_nav.dart';
import '../services/app_session_guidance.dart';
import '../themes/app_theme.dart';
import '../widgets/app_today_top_bar.dart';
import '../widgets/bottom_navigation_bar.dart';
import 'memo_detail_screen.dart';
import 'recorded_voice_memo_detail_screen.dart';

class MemoScreen extends StatefulWidget {
  const MemoScreen({super.key});

  @override
  State<MemoScreen> createState() => _MemoScreenState();
}

class _MemoScreenState extends State<MemoScreen> with TickerProviderStateMixin {
  static const bgColor = AppTheme.pageBackground;
  static const primaryColor = Color(0xFF0F172A);
  static const accentColor = Color(0xFFE2B736);
  static const secondaryAccent = Color(0xFFFDE047);
  static const borderColor = Color.fromRGBO(236, 91, 19, 0.05);
  static const int _cardTitleLimit = 20;
  static const String _voiceMemoEmptyNotePreview =
      'No notes yet. Tap to add notes for this voice note.';

  final int _selectedNavIndex = 0;
  String? _deletingMemoId;
  bool _isBatchManaging = false;
  bool _isBatchDeleting = false;
  final Set<String> _selectedMemoIds = <String>{};
  Set<String> _batchDeletingMemoIds = <String>{};
  List<_MemoItem> _lastMemoItems = const <_MemoItem>[];
  final AudioRecorder _audioRecorder = AudioRecorder();
  late final AnimationController _voiceBarsController;
  AnimationController? _recordButtonHintController;
  late final ValueNotifier<_VoiceUiState> _voiceUi;
  StreamSubscription<Amplitude>? _recordingAmplitudeSub;
  Timer? _recordingTimer;
  DateTime? _recordingStartedAt;
  Duration _recordingAccumulatedElapsed = Duration.zero;
  String? _activeRecordingPath;
  bool _showRecordButtonHint = false;

  bool get _isListening => _voiceUi.value.isListening;
  bool get _isVoiceTransitioning => _voiceUi.value.isVoiceTransitioning;
  bool get _isRecordingSessionActive => _voiceUi.value.isRecordingSessionActive;
  bool get _isCreatingVoiceMemo => _voiceUi.value.isCreatingVoiceMemo;
  bool get _isRecordingPaused => _voiceUi.value.isRecordingPaused;
  double get _soundLevel => _voiceUi.value.soundLevel;
  Duration get _recordingElapsed => _voiceUi.value.elapsed;

  @override
  void initState() {
    super.initState();
    _voiceUi = ValueNotifier(const _VoiceUiState());
    _voiceBarsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _recordButtonHintController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _showRecordButtonHint = AppSessionGuidance.shouldShow(
      'memo_record_button_hint',
    );
    if (_showRecordButtonHint) {
      _recordButtonHintController?.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _recordingAmplitudeSub?.cancel();
    unawaited(WakelockPlus.disable());
    _voiceUi.dispose();
    _voiceBarsController.dispose();
    _recordButtonHintController?.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _hideRecordButtonHint() async {
    if (!_showRecordButtonHint ||
        _recordButtonHintController?.status == AnimationStatus.dismissed) {
      return;
    }

    _showRecordButtonHint = false;
    await _recordButtonHintController?.reverse();
  }

  Future<void> _markRecordButtonHintSeen() async {
    await _hideRecordButtonHint();
  }

  void _updateVoiceUi(_VoiceUiState Function(_VoiceUiState current) transform) {
    final current = _voiceUi.value;
    final next = transform(current);
    if (identical(current, next) || current == next) {
      return;
    }
    _voiceUi.value = next;
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

  void _startVoiceBars() {
    if (!_voiceBarsController.isAnimating) {
      _voiceBarsController.repeat();
    }
  }

  void _stopVoiceBars() {
    _voiceBarsController.stop();
  }

  void _resetVoiceOverlay() {
    _updateVoiceUi(
      (current) => current.copyWith(
        isListening: false,
        isVoiceTransitioning: false,
        isRecordingSessionActive: false,
        isCreatingVoiceMemo: false,
        isRecordingPaused: false,
        soundLevel: 0,
        elapsed: Duration.zero,
      ),
    );
    _activeRecordingPath = null;
    _recordingStartedAt = null;
    _recordingAccumulatedElapsed = Duration.zero;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _recordingAmplitudeSub?.cancel();
    _recordingAmplitudeSub = null;
    unawaited(WakelockPlus.disable());
    _stopVoiceBars();
  }

  Future<void> _startVoiceMemoCreation() async {
    if (_isVoiceTransitioning ||
        _isCreatingVoiceMemo ||
        _isRecordingSessionActive) {
      return;
    }

    unawaited(_markRecordButtonHintSeen());
    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      _showMessage(
        'Microphone permission is unavailable. Please check system settings.',
      );
      return;
    }

    if (!mounted) {
      return;
    }
    _updateVoiceUi(
      (current) => current.copyWith(
        isListening: false,
        isVoiceTransitioning: true,
        isRecordingSessionActive: true,
        isCreatingVoiceMemo: false,
        isRecordingPaused: false,
        soundLevel: 0,
        elapsed: Duration.zero,
      ),
    );
    _startVoiceBars();

    try {
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path =
          '${directory.path}${Platform.pathSeparator}voice_memo_$timestamp.m4a';

      await WakelockPlus.enable();
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: path,
      );

      if (!mounted) {
        return;
      }

      _activeRecordingPath = path;
      _recordingStartedAt = DateTime.now();
      _recordingAccumulatedElapsed = Duration.zero;
      _recordingAmplitudeSub?.cancel();
      _recordingAmplitudeSub = _audioRecorder
          .onAmplitudeChanged(const Duration(milliseconds: 120))
          .listen((amplitude) {
            if (!mounted) {
              return;
            }
            _updateVoiceUi(
              (current) => current.copyWith(soundLevel: amplitude.current),
            );
          });
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted) {
          return;
        }
        _updateVoiceUi(
          (current) => current.copyWith(elapsed: _currentRecordingElapsed()),
        );
      });

      _updateVoiceUi(
        (current) =>
            current.copyWith(isListening: true, isVoiceTransitioning: false),
      );
    } catch (_) {
      _resetVoiceOverlay();
      _showMessage('Unable to start recording. Please try again.');
    }
  }

  Future<void> _openNewTextMemo() async {
    if (_isVoiceTransitioning ||
        _isCreatingVoiceMemo ||
        _isRecordingSessionActive) {
      return;
    }

    unawaited(_markRecordButtonHintSeen());
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const MemoDetailScreen(isCreating: true),
      ),
    );
  }

  Duration _currentRecordingElapsed() {
    final startedAt = _recordingStartedAt;
    if (!_isListening || startedAt == null) {
      return _recordingAccumulatedElapsed;
    }

    return _recordingAccumulatedElapsed + DateTime.now().difference(startedAt);
  }

  Future<void> _toggleRecordingPause() async {
    if (!_isRecordingSessionActive ||
        _isVoiceTransitioning ||
        _isCreatingVoiceMemo) {
      return;
    }

    try {
      if (_isRecordingPaused) {
        await _audioRecorder.resume();
        if (!mounted) {
          return;
        }
        _recordingStartedAt = DateTime.now();
        _startVoiceBars();
        _updateVoiceUi(
          (current) => current.copyWith(
            isListening: true,
            isRecordingPaused: false,
            soundLevel: 0,
            elapsed: _recordingAccumulatedElapsed,
          ),
        );
        return;
      }

      _recordingAccumulatedElapsed = _currentRecordingElapsed();
      await _audioRecorder.pause();
      if (!mounted) {
        return;
      }
      _recordingStartedAt = null;
      _stopVoiceBars();
      _updateVoiceUi(
        (current) => current.copyWith(
          isListening: false,
          isRecordingPaused: true,
          soundLevel: 0,
          elapsed: _recordingAccumulatedElapsed,
        ),
      );
    } catch (_) {
      _showMessage('Unable to pause recording. Please try again.');
    }
  }

  Future<void> _confirmAndDiscardRecording() async {
    if (!_isRecordingSessionActive ||
        _isVoiceTransitioning ||
        _isCreatingVoiceMemo) {
      return;
    }

    final shouldDiscard = await _showDiscardRecordingDialog();
    if (!mounted || !shouldDiscard) {
      return;
    }

    await _stopVoiceMemoCreation(save: false);
  }

  Future<void> _stopVoiceMemoCreation({required bool save}) async {
    if (!_isRecordingSessionActive || _isCreatingVoiceMemo) {
      return;
    }

    final duration = _currentRecordingElapsed();
    _updateVoiceUi(
      (current) => current.copyWith(
        isListening: false,
        isVoiceTransitioning: true,
        isRecordingSessionActive: false,
        isRecordingPaused: false,
        soundLevel: 0,
        elapsed: duration,
      ),
    );
    _stopVoiceBars();

    String? audioPath;

    try {
      if (save) {
        audioPath = await _audioRecorder.stop();
      } else {
        await _audioRecorder.cancel();
      }
    } catch (_) {
      audioPath = _activeRecordingPath;
    } finally {
      _recordingTimer?.cancel();
      _recordingTimer = null;
      await _recordingAmplitudeSub?.cancel();
      _recordingAmplitudeSub = null;
    }

    if (!mounted) {
      return;
    }

    if (!save) {
      _resetVoiceOverlay();
      return;
    }

    final path = audioPath ?? _activeRecordingPath;
    final audioFile = path == null || path.isEmpty ? null : File(path);
    if (audioFile == null || !audioFile.existsSync()) {
      _resetVoiceOverlay();
      _showMessage('No recording file was created. Please try again.');
      return;
    }

    await _createVoiceMemoFromRecording(
      audioFile.path,
      duration: duration,
      audioFileBytes: audioFile.lengthSync(),
    );
  }

  Future<void> _createVoiceMemoFromRecording(
    String audioPath, {
    required Duration duration,
    required int audioFileBytes,
  }) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _resetVoiceOverlay();
      _showMessage('Please sign in to create a note.');
      return;
    }

    if (!mounted) {
      return;
    }

    _updateVoiceUi(
      (current) => current.copyWith(
        isListening: false,
        isVoiceTransitioning: false,
        isRecordingSessionActive: false,
        isCreatingVoiceMemo: true,
        soundLevel: 0,
        elapsed: duration,
      ),
    );

    try {
      final docRef = FirebaseFirestore.instance.collection('memos').doc();
      final createdAt = DateTime.now();
      final title = _voiceMemoAutoTitle(createdAt);
      var audioUrl = '';
      var storagePath = '';

      try {
        storagePath = 'voice_memos/${user.uid}/${docRef.id}.m4a';
        final storageRef = FirebaseStorage.instance.ref(storagePath);
        await storageRef.putFile(
          File(audioPath),
          SettableMetadata(contentType: 'audio/mp4'),
        );
        audioUrl = await storageRef.getDownloadURL();
      } catch (error) {
        if (!mounted) {
          return;
        }

        _resetVoiceOverlay();
        _showMessage(
          'Voice note could not be uploaded. Please check your connection and try again.',
        );
        return;
      }

      await docRef.set({
        'userId': user.uid,
        'memoType': 'voice',
        'title': title,
        'body': '',
        'audioUrl': audioUrl,
        'audioStoragePath': storagePath,
        'localAudioPath': audioPath,
        'localAudioFileBytes': audioFileBytes,
        'audioDurationMillis': duration.inMilliseconds,
        'aiSummaryStatus': 'ready',
        'createdAtLocalMillis': createdAt.millisecondsSinceEpoch,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) {
        return;
      }

      _resetVoiceOverlay();

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RecordedVoiceMemoDetailScreen(
            memoId: docRef.id,
            title: title,
            body: '',
            audioUrl: audioUrl,
            localAudioPath: audioPath,
            audioStoragePath: storagePath,
            duration: duration,
            createdAt: createdAt,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      _updateVoiceUi((current) => current.copyWith(isCreatingVoiceMemo: false));
      _resetVoiceOverlay();
      _showMessage('Failed to create recorded note. Please try again.');
    }
  }

  static String _voiceMemoAutoTitle(DateTime createdAt) {
    return DateFormat('yyyy-MM-dd HH:mm').format(createdAt.toLocal());
  }

  static bool _isUnsetVoiceTitle(String title) {
    final normalized = title.trim();
    return normalized.isEmpty || normalized == 'Voice Note';
  }

  Stream<List<MemoRecord>> _memoStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Stream<List<MemoRecord>>.empty();
    }

    return FirebaseFirestore.instance
        .collection('memos')
        .where('userId', isEqualTo: user.uid)
        .snapshots()
        .map((snapshot) {
          final memos = snapshot.docs.map(MemoRecord.fromFirestore).toList();
          memos.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return memos;
        });
  }

  List<_MemoSection> _buildSections(List<MemoRecord> memos) {
    final sections = <_MemoSection>[];
    String? currentKey;
    List<_MemoItem> currentItems = [];

    for (final memo in memos) {
      final key = _sectionKeyForDate(memo.createdAt);
      if (currentKey != key) {
        if (currentKey != null) {
          sections.add(
            _MemoSection(
              title: currentKey,
              items: List.unmodifiable(currentItems),
            ),
          );
        }
        currentKey = key;
        currentItems = [];
      }

      currentItems.add(
        _MemoItem(
          id: memo.id,
          title: memo.title,
          displayTitle: memo.displayTitle,
          dateLabel: _cardDateLabel(memo.createdAt),
          body: memo.body,
          createdAt: memo.createdAt,
          isVoiceMemo: memo.isVoiceMemo,
          audioUrl: memo.audioUrl,
          localAudioPath: memo.localAudioPath,
          audioStoragePath: memo.audioStoragePath,
          audioDuration: memo.audioDuration,
        ),
      );
    }

    if (currentKey != null) {
      sections.add(
        _MemoSection(title: currentKey, items: List.unmodifiable(currentItems)),
      );
    }

    return sections;
  }

  String _sectionKeyForDate(DateTime date) {
    final localDate = date.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final memoDay = DateTime(localDate.year, localDate.month, localDate.day);
    final difference = today.difference(memoDay).inDays;

    if (difference == 0) {
      return 'Today';
    }
    if (difference == 1) {
      return 'Yesterday';
    }

    if (now.year == localDate.year && now.month == localDate.month) {
      return DateFormat('d MMMM yyyy').format(localDate);
    }

    return DateFormat('MMMM yyyy').format(localDate);
  }

  Future<void> _confirmAndDeleteMemo(_MemoItem item) async {
    if (_deletingMemoId != null || _isBatchDeleting) {
      return;
    }

    final confirmed = await _showDeleteMemoDialog(item);
    if (!mounted) {
      return;
    }

    if (!confirmed) {
      return;
    }

    setState(() {
      _deletingMemoId = item.id;
    });

    try {
      await _deleteMemoItem(item);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Note deleted.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Failed to delete note. Please try again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _deletingMemoId = null;
        });
      }
    }
  }

  Future<void> _confirmAndDeleteSelectedMemos() async {
    if (_selectedMemoIds.isEmpty ||
        _isBatchDeleting ||
        _deletingMemoId != null) {
      return;
    }

    final selectedItems = _lastMemoItems
        .where((item) => _selectedMemoIds.contains(item.id))
        .toList(growable: false);
    if (selectedItems.isEmpty) {
      setState(() {
        _selectedMemoIds.clear();
      });
      return;
    }

    final confirmed = await _showBatchDeleteMemoDialog(selectedItems.length);
    if (!mounted || !confirmed) {
      return;
    }

    setState(() {
      _isBatchDeleting = true;
      _batchDeletingMemoIds = selectedItems.map((item) => item.id).toSet();
    });

    try {
      for (final item in selectedItems) {
        await _deleteMemoItem(item);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _isBatchManaging = false;
        _selectedMemoIds.clear();
        _batchDeletingMemoIds = <String>{};
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              selectedItems.length == 1
                  ? 'Note deleted.'
                  : '${selectedItems.length} notes deleted.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Failed to delete selected notes. Please try again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _isBatchDeleting = false;
          _batchDeletingMemoIds = <String>{};
        });
      }
    }
  }

  Future<void> _deleteMemoItem(_MemoItem item) async {
    if (item.audioStoragePath.isNotEmpty) {
      try {
        await FirebaseStorage.instance.ref(item.audioStoragePath).delete();
      } catch (_) {
        // The memo itself should still be removable if storage cleanup fails.
      }
    }

    await FirebaseFirestore.instance.collection('memos').doc(item.id).delete();
  }

  Future<bool> _showDeleteMemoDialog(_MemoItem item) async {
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
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFAC638).withValues(alpha: 0.08),
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
                  'Delete this note?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'This will permanently remove "${item.title}".',
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
                      gradient: const LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [AppTheme.accent, AppTheme.accentDark],
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.accent.withValues(alpha: 0.2),
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
                          color: Colors.black87,
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
                      backgroundColor: AppTheme.lightBackground,
                      foregroundColor: primaryColor,
                    ),
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
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

  Future<bool> _showBatchDeleteMemoDialog(int count) async {
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
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFAC638).withValues(alpha: 0.08),
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
                      Icons.delete_sweep_outlined,
                      color: AppTheme.error,
                      size: 31,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Delete selected notes?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'This will permanently remove $count selected ${count == 1 ? 'note' : 'notes'}.',
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
                      gradient: const LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [AppTheme.accent, AppTheme.accentDark],
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.accent.withValues(alpha: 0.2),
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
                          color: Colors.black87,
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
                      backgroundColor: AppTheme.lightBackground,
                      foregroundColor: primaryColor,
                    ),
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
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

  Future<bool> _showDiscardRecordingDialog() async {
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
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFAC638).withValues(alpha: 0.08),
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
                  'Discard this recording?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'This recording has not been saved yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
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
                        'Discard',
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
                      backgroundColor: AppTheme.lightBackground,
                      foregroundColor: primaryColor,
                    ),
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text(
                      'Keep Recording',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
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

  void _enterBatchManagement() {
    setState(() {
      _isBatchManaging = true;
      _selectedMemoIds.clear();
    });
  }

  void _exitBatchManagement() {
    if (_isBatchDeleting) {
      return;
    }

    setState(() {
      _isBatchManaging = false;
      _selectedMemoIds.clear();
    });
  }

  void _toggleMemoSelection(_MemoItem item) {
    if (_isBatchDeleting) {
      return;
    }

    setState(() {
      if (_selectedMemoIds.contains(item.id)) {
        _selectedMemoIds.remove(item.id);
      } else {
        _selectedMemoIds.add(item.id);
      }
    });
  }

  Future<void> _openMemoDetail(_MemoItem item) async {
    if (_isBatchManaging) {
      _toggleMemoSelection(item);
      return;
    }

    if (item.isVoiceMemo) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RecordedVoiceMemoDetailScreen(
            memoId: item.id,
            title: item.title,
            body: item.body,
            audioUrl: item.audioUrl,
            localAudioPath: item.localAudioPath,
            audioStoragePath: item.audioStoragePath,
            duration: item.audioDuration,
            createdAt: item.createdAt,
          ),
        ),
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MemoDetailScreen(
            memoId: item.id,
            title: item.title,
            body: item.body,
          ),
        ),
      );
    }
  }

  String _cardDateLabel(DateTime date) {
    final localDate = date.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final memoDay = DateTime(localDate.year, localDate.month, localDate.day);
    final difference = today.difference(memoDay).inDays;

    if (difference == 0 || difference == 1) {
      return DateFormat('h:mm a').format(localDate);
    }
    return DateFormat('dd/MM/yyyy').format(localDate);
  }

  @override
  Widget build(BuildContext context) {
    final mediaPadding = MediaQuery.of(context).padding;
    final statusBarHeight = mediaPadding.top;
    final bottomInset = mediaPadding.bottom;
    final actionBottomOffset = bottomInset + 112;
    final contentBottomSpacing = bottomInset + 62;
    final staticBody = _buildStaticBody(
      statusBarHeight: statusBarHeight,
      contentBottomSpacing: contentBottomSpacing,
    );

    return Scaffold(
      backgroundColor: bgColor,
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          if (_showRecordButtonHint) {
            unawaited(_hideRecordButtonHint());
          }
        },
        child: ValueListenableBuilder<_VoiceUiState>(
          valueListenable: _voiceUi,
          child: staticBody,
          builder: (context, voiceUi, child) {
            return Stack(
              children: [
                child!,
                SafeArea(
                  bottom: false,
                  child: Center(
                    child: SizedBox(
                      width: 430,
                      height: double.infinity,
                      child: Stack(
                        children: [
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: _buildHeader(),
                          ),
                          if (voiceUi.isOverlayVisible)
                            Positioned.fill(
                              child: _buildVoiceComposerOverlay(),
                            ),
                          if (_showRecordButtonHint &&
                              !voiceUi.isRecordingSessionActive)
                            Positioned(
                              right: 24,
                              bottom: actionBottomOffset + 74,
                              child: _buildRecordButtonHint(),
                            ),
                          Positioned(
                            right: 24,
                            bottom: actionBottomOffset,
                            child: _buildBottomActionRow(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildStaticBody({
    required double statusBarHeight,
    required double contentBottomSpacing,
  }) {
    return Stack(
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
                        Expanded(child: _buildContent()),
                        SizedBox(height: contentBottomSpacing),
                      ],
                    ),
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
    );
  }

  Widget _buildHeader() {
    return Stack(
      children: [
        AppTodayTopBar(
          title: DateFormat('d MMMM').format(DateTime.now()),
          showNotifications: false,
        ),
        Positioned(top: 10, right: 24, child: _buildHeaderActions()),
      ],
    );
  }

  Widget _buildHeaderActions() {
    if (_isBatchManaging) {
      final canDelete = _selectedMemoIds.isNotEmpty && !_isBatchDeleting;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _HeaderActionButton(
            icon: Icons.delete_outline_rounded,
            tooltip: 'Delete selected notes',
            color: canDelete ? AppTheme.error : AppTheme.inactiveIcon,
            isBusy: _isBatchDeleting,
            onTap: canDelete ? _confirmAndDeleteSelectedMemos : null,
          ),
          const SizedBox(width: 8),
          _HeaderActionButton(
            icon: Icons.close_rounded,
            tooltip: 'Done',
            color: accentColor,
            onTap: _exitBatchManagement,
          ),
        ],
      );
    }

    return _HeaderActionButton(
      icon: Icons.more_horiz_rounded,
      tooltip: 'Manage notes',
      color: accentColor,
      onTap: _enterBatchManagement,
    );
  }

  Widget _buildContent() {
    return StreamBuilder<List<MemoRecord>>(
      stream: _memoStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Unable to load notes right now.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.6,
                ),
              ),
            ),
          );
        }

        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Please sign in to view your notes.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.6,
                ),
              ),
            ),
          );
        }

        final sections = _buildSections(snapshot.data ?? const <MemoRecord>[]);
        final entries = _buildListEntries(sections);
        _lastMemoItems = sections
            .expand((section) => section.items)
            .toList(growable: false);
        if (sections.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'No notes yet. Use the center record button or the note button to create one.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.6,
                ),
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 128),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            final sectionTitle = entry.sectionTitle;
            if (sectionTitle != null) {
              return _buildSectionHeader(sectionTitle);
            }

            return _buildMemoListItem(entry.item!);
          },
        );
      },
    );
  }

  List<_MemoListEntry> _buildListEntries(List<_MemoSection> sections) {
    final entries = <_MemoListEntry>[];
    for (final section in sections) {
      entries.add(_MemoListEntry.header(section.title));
      for (final item in section.items) {
        entries.add(_MemoListEntry.item(item));
      }
    }
    return entries;
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: accentColor,
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
        ),
      ),
    );
  }

  Widget _buildMemoListItem(_MemoItem item) {
    final isDeleting =
        _deletingMemoId == item.id || _batchDeletingMemoIds.contains(item.id);
    final card = _MemoCard(
      key: ValueKey(item.id),
      item: item,
      isSelectionMode: _isBatchManaging,
      isSelected: _selectedMemoIds.contains(item.id),
      isDeleting: isDeleting,
      onTap: () {
        _openMemoDetail(item);
      },
    );

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: _isBatchManaging
            ? card
            : _SwipeRevealDelete(
                isEnabled: !isDeleting,
                isDeleting: isDeleting,
                onDelete: () => _confirmAndDeleteMemo(item),
                child: card,
              ),
      ),
    );
  }

  Widget _buildBottomActionRow() {
    if (!_isRecordingSessionActive) {
      return _buildRecordButton();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RecordingControlButton(
          icon: Icons.delete_outline_rounded,
          color: AppTheme.error,
          backgroundColor: Colors.white,
          shadowColor: AppTheme.error.withValues(alpha: 0.16),
          tooltip: 'Discard recording',
          onTap: _confirmAndDiscardRecording,
        ),
        const SizedBox(width: 14),
        _RecordingControlButton(
          icon: _isRecordingPaused
              ? Icons.play_arrow_rounded
              : Icons.pause_rounded,
          color: primaryColor,
          backgroundColor: Colors.white,
          shadowColor: Colors.black.withValues(alpha: 0.08),
          tooltip: _isRecordingPaused ? 'Resume recording' : 'Pause recording',
          onTap: _toggleRecordingPause,
        ),
        const SizedBox(width: 14),
        _RecordingControlButton(
          icon: Icons.check_rounded,
          color: Colors.white,
          backgroundColor: const Color(0xFF22C55E),
          shadowColor: const Color(0xFF22C55E).withValues(alpha: 0.28),
          tooltip: 'Save recording',
          onTap: () => _stopVoiceMemoCreation(save: true),
        ),
      ],
    );
  }

  Widget _buildRecordButton() {
    final isBusy = _isVoiceTransitioning || _isCreatingVoiceMemo;
    final isRecording = _isRecordingSessionActive;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: isBusy || isRecording ? null : _openNewTextMemo,
      onTap: isBusy
          ? null
          : isRecording
          ? () => _stopVoiceMemoCreation(save: true)
          : _startVoiceMemoCreation,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isRecording
                ? const [Color(0xFFF87171), Color(0xFFDC2626)]
                : const [accentColor, secondaryAccent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: (isRecording ? const Color(0xFFDC2626) : accentColor)
                  .withValues(alpha: 0.3),
              blurRadius: 25,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Center(
          child: isBusy
              ? const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Icon(
                  isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                  size: 28,
                  color: Colors.white,
                ),
        ),
      ),
    );
  }

  Widget _buildRecordButtonHint() {
    final hintAnimation = _recordButtonHintController;

    return SizedBox(
      height: 36,
      child: IgnorePointer(
        ignoring: true,
        child: hintAnimation == null
            ? Opacity(
                opacity: _showRecordButtonHint ? 1 : 0,
                child: _buildRecordButtonHintPill(),
              )
            : FadeTransition(
                opacity: CurvedAnimation(
                  parent: hintAnimation,
                  curve: Curves.easeOutCubic,
                ),
                child: _buildRecordButtonHintPill(),
              ),
      ),
    );
  }

  Widget _buildRecordButtonHintPill() {
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
        'Tap for voice, hold for text',
        style: TextStyle(
          color: AppTheme.accent,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildVoiceComposerOverlay() {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              color: const Color(0xFFF8F7F6).withValues(alpha: 0.32),
            ),
          ),
        ),
        Container(color: const Color(0xFF0F172A).withValues(alpha: 0.08)),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 96, 24, 188),
            child: Column(
              children: [
                const Spacer(),
                RepaintBoundary(child: _buildVoiceWaveBubble()),
                const SizedBox(height: 18),
                _buildRecordingDurationCard(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVoiceWaveBubble() {
    final bubbleColor = _isCreatingVoiceMemo
        ? const Color(0xFFFFF8E3)
        : _isRecordingPaused
        ? const Color(0xFFF8FAFC)
        : _isRecordingSessionActive
        ? const Color(0xFFFFF1C9)
        : const Color(0xFFF8FAFC);
    final waveColor = _isRecordingSessionActive
        ? const Color(0xFF9A6B00)
        : accentColor;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        Container(
          width: 236,
          height: 128,
          decoration: BoxDecoration(
            color: bubbleColor.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: waveColor.withValues(alpha: 0.14),
                blurRadius: 26,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Center(
            child: _isCreatingVoiceMemo
                ? const SizedBox(
                    width: 38,
                    height: 38,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                    ),
                  )
                : _isRecordingSessionActive
                ? _isRecordingPaused
                      ? const Icon(
                          Icons.pause_rounded,
                          size: 42,
                          color: Color(0xFF64748B),
                        )
                      : _VoiceBars(
                          animation: _voiceBarsController,
                          level: _soundLevel,
                          color: waveColor,
                        )
                : const Icon(
                    Icons.mic_none_rounded,
                    size: 40,
                    color: accentColor,
                  ),
          ),
        ),
        Positioned(
          bottom: -9,
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: bubbleColor.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecordingDurationCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _isListening
                      ? const Color(0xFFEF4444)
                      : _isRecordingPaused
                      ? const Color(0xFF64748B)
                      : accentColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _isRecordingPaused
                    ? 'Recording paused'
                    : _isRecordingSessionActive
                    ? 'Recording audio'
                    : 'Voice note',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF475569),
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              _formatDuration(_recordingElapsed),
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w900,
                color: primaryColor,
                height: 1,
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

class _RecordingControlButton extends StatelessWidget {
  const _RecordingControlButton({
    required this.icon,
    required this.color,
    required this.backgroundColor,
    required this.shadowColor,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final Color backgroundColor;
  final Color shadowColor;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: backgroundColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(child: Icon(icon, color: color, size: 28)),
        ),
      ),
    );
  }
}

class _VoiceUiState {
  const _VoiceUiState({
    this.isListening = false,
    this.isVoiceTransitioning = false,
    this.isRecordingSessionActive = false,
    this.isCreatingVoiceMemo = false,
    this.isRecordingPaused = false,
    this.soundLevel = 0,
    this.elapsed = Duration.zero,
  });

  final bool isListening;
  final bool isVoiceTransitioning;
  final bool isRecordingSessionActive;
  final bool isCreatingVoiceMemo;
  final bool isRecordingPaused;
  final double soundLevel;
  final Duration elapsed;

  bool get isOverlayVisible {
    return isRecordingSessionActive ||
        isVoiceTransitioning ||
        isCreatingVoiceMemo;
  }

  _VoiceUiState copyWith({
    bool? isListening,
    bool? isVoiceTransitioning,
    bool? isRecordingSessionActive,
    bool? isCreatingVoiceMemo,
    bool? isRecordingPaused,
    double? soundLevel,
    Duration? elapsed,
  }) {
    return _VoiceUiState(
      isListening: isListening ?? this.isListening,
      isVoiceTransitioning: isVoiceTransitioning ?? this.isVoiceTransitioning,
      isRecordingSessionActive:
          isRecordingSessionActive ?? this.isRecordingSessionActive,
      isCreatingVoiceMemo: isCreatingVoiceMemo ?? this.isCreatingVoiceMemo,
      isRecordingPaused: isRecordingPaused ?? this.isRecordingPaused,
      soundLevel: soundLevel ?? this.soundLevel,
      elapsed: elapsed ?? this.elapsed,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is _VoiceUiState &&
        other.isListening == isListening &&
        other.isVoiceTransitioning == isVoiceTransitioning &&
        other.isRecordingSessionActive == isRecordingSessionActive &&
        other.isCreatingVoiceMemo == isCreatingVoiceMemo &&
        other.isRecordingPaused == isRecordingPaused &&
        other.soundLevel == soundLevel &&
        other.elapsed == elapsed;
  }

  @override
  int get hashCode => Object.hash(
    isListening,
    isVoiceTransitioning,
    isRecordingSessionActive,
    isCreatingVoiceMemo,
    isRecordingPaused,
    soundLevel,
    elapsed,
  );
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
          mainAxisSize: MainAxisSize.min,
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

class MemoRecord {
  static const int _cardTitleLimit = _MemoScreenState._cardTitleLimit;

  const MemoRecord({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.isVoiceMemo,
    required this.audioUrl,
    required this.localAudioPath,
    required this.audioStoragePath,
    required this.audioDuration,
  });

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool isVoiceMemo;
  final String audioUrl;
  final String localAudioPath;
  final String audioStoragePath;
  final Duration audioDuration;

  String get displayTitle {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isNotEmpty) {
      return _truncateForCard(trimmedTitle);
    }

    final trimmedBody = body.trim();
    if (trimmedBody.isEmpty) {
      return isVoiceMemo ? 'Voice Note' : 'Untitled Note';
    }

    final firstLine = trimmedBody.split('\n').first.trim();
    if (firstLine.length <= _cardTitleLimit) {
      return firstLine;
    }
    return firstLine.substring(0, _cardTitleLimit).trimRight();
  }

  static String _truncateForCard(String value) {
    if (value.length <= _cardTitleLimit) {
      return value;
    }
    return '${value.substring(0, _cardTitleLimit).trimRight()}...';
  }

  factory MemoRecord.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final timestamp = data['createdAt'];
    final localTimestamp = data['createdAtLocalMillis'];
    final durationMillis = data['audioDurationMillis'];
    final createdAt = timestamp is Timestamp
        ? timestamp.toDate()
        : localTimestamp is int
        ? DateTime.fromMillisecondsSinceEpoch(localTimestamp)
        : DateTime.fromMillisecondsSinceEpoch(0);
    final isVoiceMemo =
        data['memoType'] == 'voice' || data['inputMode'] == 'voice';
    final title = (data['title'] as String?) ?? '';

    return MemoRecord(
      id: doc.id,
      title: isVoiceMemo && _MemoScreenState._isUnsetVoiceTitle(title)
          ? _MemoScreenState._voiceMemoAutoTitle(createdAt)
          : title,
      body: (data['body'] as String?) ?? '',
      createdAt: createdAt,
      isVoiceMemo: isVoiceMemo,
      audioUrl: (data['audioUrl'] as String?) ?? '',
      localAudioPath: (data['localAudioPath'] as String?) ?? '',
      audioStoragePath: (data['audioStoragePath'] as String?) ?? '',
      audioDuration: Duration(
        milliseconds: durationMillis is int ? durationMillis : 0,
      ),
    );
  }
}

class _MemoSection {
  final String title;
  final List<_MemoItem> items;

  const _MemoSection({required this.title, required this.items});
}

class _MemoListEntry {
  final String? sectionTitle;
  final _MemoItem? item;

  const _MemoListEntry.header(this.sectionTitle) : item = null;

  const _MemoListEntry.item(this.item) : sectionTitle = null;
}

class _MemoItem {
  final String id;
  final String title;
  final String displayTitle;
  final String dateLabel;
  final String body;
  final DateTime createdAt;
  final bool isVoiceMemo;
  final String audioUrl;
  final String localAudioPath;
  final String audioStoragePath;
  final Duration audioDuration;

  const _MemoItem({
    required this.id,
    required this.title,
    required this.displayTitle,
    required this.dateLabel,
    required this.body,
    required this.createdAt,
    required this.isVoiceMemo,
    required this.audioUrl,
    required this.localAudioPath,
    required this.audioStoragePath,
    required this.audioDuration,
  });
}

class _SwipeRevealDelete extends StatefulWidget {
  final Widget child;
  final bool isEnabled;
  final bool isDeleting;
  final VoidCallback onDelete;

  const _SwipeRevealDelete({
    required this.child,
    required this.isEnabled,
    required this.isDeleting,
    required this.onDelete,
  });

  @override
  State<_SwipeRevealDelete> createState() => _SwipeRevealDeleteState();
}

class _SwipeRevealDeleteState extends State<_SwipeRevealDelete> {
  static const double _revealWidth = 72;
  double _offset = 0;

  void _setOffset(double value) {
    setState(() {
      _offset = value.clamp(0, _revealWidth).toDouble();
    });
  }

  void _settleOffset() {
    _setOffset(_offset > _revealWidth * 0.42 ? _revealWidth : 0);
  }

  @override
  void didUpdateWidget(covariant _SwipeRevealDelete oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((!widget.isEnabled || widget.isDeleting) && _offset != 0) {
      _offset = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.isEnabled ? widget.onDelete : null,
                child: Container(
                  width: _revealWidth,
                  height: double.infinity,
                  color: Colors.transparent,
                  child: Center(
                    child: widget.isDeleting
                        ? Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: AppTheme.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: const Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    AppTheme.error,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: AppTheme.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: const Icon(
                              Icons.delete_outline_rounded,
                              color: AppTheme.error,
                              size: 22,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: widget.isEnabled
                ? (details) => _setOffset(_offset - details.delta.dx)
                : null,
            onHorizontalDragEnd: widget.isEnabled
                ? (_) => _settleOffset()
                : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              transform: Matrix4.translationValues(-_offset, 0, 0),
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoCard extends StatelessWidget {
  final _MemoItem item;
  final VoidCallback? onTap;
  final bool isSelectionMode;
  final bool isSelected;
  final bool isDeleting;

  const _MemoCard({
    super.key,
    required this.item,
    this.onTap,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.isDeleting = false,
  });

  @override
  Widget build(BuildContext context) {
    final isVoice = item.isVoiceMemo;
    final cardColor = Colors.white;
    final borderColor = _MemoScreenState.borderColor;
    final previewText = item.body.trim().isNotEmpty
        ? item.body
        : (isVoice ? _MemoScreenState._voiceMemoEmptyNotePreview : '');
    final icon = isVoice ? Icons.mic_rounded : Icons.edit_note_rounded;
    final iconColor = _MemoScreenState.accentColor;
    final iconBackground = _MemoScreenState.accentColor.withValues(alpha: 0.1);

    final card = Container(
      constraints: const BoxConstraints(minHeight: 100),
      decoration: BoxDecoration(
        color: cardColor,
        border: Border.all(
          color: isSelected ? _MemoScreenState.accentColor : borderColor,
          width: isSelected ? 1.4 : 1,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: (isSelected ? _MemoScreenState.accentColor : Colors.black)
                .withValues(alpha: isSelected ? 0.12 : 0.05),
            blurRadius: isSelected ? 12 : 2,
            offset: Offset(0, isSelected ? 4 : 1),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (isSelectionMode) ...[
                _MemoSelectionIndicator(isSelected: isSelected),
                const SizedBox(width: 10),
              ],
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Icon(icon, color: iconColor, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _MemoScreenState.primaryColor,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                item.dateLabel,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            previewText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: Color(0xFF64748B),
              height: 1.4,
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        alignment: Alignment.center,
        children: [
          card,
          if (isDeleting)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: AppTheme.error,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MemoSelectionIndicator extends StatelessWidget {
  final bool isSelected;

  const _MemoSelectionIndicator({required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: isSelected ? _MemoScreenState.accentColor : Colors.white,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: isSelected
              ? _MemoScreenState.accentColor
              : const Color(0xFFE2E8F0),
          width: 1.6,
        ),
      ),
      child: isSelected
          ? const Icon(Icons.check_rounded, color: Colors.white, size: 17)
          : null,
    );
  }
}

class _HeaderActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final bool isBusy;
  final VoidCallback? onTap;

  const _HeaderActionButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    this.isBusy = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: isBusy ? null : onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: onTap == null ? 0.08 : 0.1),
            borderRadius: BorderRadius.circular(48),
          ),
          child: Center(
            child: isBusy
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  )
                : Icon(icon, size: 16, color: color),
          ),
        ),
      ),
    );
  }
}
