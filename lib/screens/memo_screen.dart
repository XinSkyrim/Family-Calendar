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

import '../navigation/app_bottom_nav.dart';
import '../services/onboarding_service.dart';
import '../themes/app_theme.dart';
import '../widgets/app_header.dart';
import '../widgets/bottom_navigation_bar.dart';
import '../widgets/feature_tour_overlay.dart';
import 'memo_detail_screen.dart';
import 'recorded_voice_memo_detail_screen.dart';

class MemoScreen extends StatefulWidget {
  const MemoScreen({super.key});

  @override
  State<MemoScreen> createState() => _MemoScreenState();
}

class _MemoScreenState extends State<MemoScreen>
    with SingleTickerProviderStateMixin {
  static const bgColor = AppTheme.pageBackground;
  static const primaryColor = Color(0xFF0F172A);
  static const accentColor = Color(0xFFE2B736);
  static const secondaryAccent = Color(0xFFFDE047);
  static const borderColor = Color.fromRGBO(236, 91, 19, 0.05);
  static const int _cardTitleLimit = 20;
  static const String _voiceMemoEmptyNotePreview =
      'No notes yet. Tap to add notes for this voice memo.';

  final int _selectedNavIndex = 0;
  String? _deleteActionMemoId;
  String? _deletingMemoId;
  final AudioRecorder _audioRecorder = AudioRecorder();
  late final AnimationController _voiceBarsController;
  late final ValueNotifier<_VoiceUiState> _voiceUi;
  StreamSubscription<Amplitude>? _recordingAmplitudeSub;
  Timer? _recordingTimer;
  DateTime? _recordingStartedAt;
  String? _activeRecordingPath;
  final GlobalKey _textMemoButtonKey = GlobalKey();
  final GlobalKey _voiceMemoButtonKey = GlobalKey();
  final GlobalKey _todayNavKey = GlobalKey();
  int _onboardingIndex = 0;
  bool _isOnboardingVisible = false;
  bool _isOnboardingBusy = false;

  bool get _isListening => _voiceUi.value.isListening;
  bool get _isVoiceTransitioning => _voiceUi.value.isVoiceTransitioning;
  bool get _isRecordingSessionActive => _voiceUi.value.isRecordingSessionActive;
  bool get _isCreatingVoiceMemo => _voiceUi.value.isCreatingVoiceMemo;
  double get _soundLevel => _voiceUi.value.soundLevel;
  Duration get _recordingElapsed => _voiceUi.value.elapsed;
  bool get _isVoiceOverlayVisible {
    return _voiceUi.value.isOverlayVisible;
  }

  @override
  void initState() {
    super.initState();
    _voiceUi = ValueNotifier(const _VoiceUiState());
    _voiceBarsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeStartOnboarding();
    });
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _recordingAmplitudeSub?.cancel();
    _voiceUi.dispose();
    _voiceBarsController.dispose();
    _audioRecorder.dispose();
    super.dispose();
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

  Future<void> _maybeStartOnboarding() async {
    final state = await OnboardingService.getCurrentState();
    if (!mounted || state == null || !OnboardingService.shouldStart(state)) {
      return;
    }

    if (state.step == OnboardingService.stepCalendarAddFab ||
        state.step == OnboardingService.stepCompleted) {
      return;
    }

    final restoredIndex = _memoTourSteps.indexWhere((step) => step.id == state.step);
    setState(() {
      _isOnboardingVisible = true;
      _onboardingIndex = restoredIndex >= 0 ? restoredIndex : 0;
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

  Future<void> _completeOnboarding() async {
    await _skipOnboarding();
  }

  Future<void> _previousOnboardingStep() async {
    if (_isOnboardingBusy || _onboardingIndex == 0) {
      return;
    }

    final nextIndex = _onboardingIndex - 1;
    setState(() {
      _isOnboardingBusy = true;
    });
    await OnboardingService.markStep(_memoTourSteps[nextIndex].id);
    if (!mounted) {
      return;
    }
    setState(() {
      _onboardingIndex = nextIndex;
      _isOnboardingBusy = false;
    });
  }

  Future<void> _nextOnboardingStep() async {
    if (_isOnboardingBusy) {
      return;
    }

    final currentStep = _memoTourSteps[_onboardingIndex];
    setState(() {
      _isOnboardingBusy = true;
    });

    if (currentStep.id == OnboardingService.stepNavToday) {
      await OnboardingService.markStep(OnboardingService.stepCalendarAddFab);
      if (!mounted) {
        return;
      }
      setState(() {
        _isOnboardingBusy = false;
        _isOnboardingVisible = false;
      });
      navigateFromBottomNav(
        context,
        targetIndex: 2,
        currentIndex: _selectedNavIndex,
      );
      return;
    }

    final nextIndex = _onboardingIndex + 1;
    await OnboardingService.markStep(_memoTourSteps[nextIndex].id);
    if (!mounted) {
      return;
    }
    setState(() {
      _onboardingIndex = nextIndex;
      _isOnboardingBusy = false;
    });
  }

  List<FeatureTourStep> get _memoTourSteps => [
        FeatureTourStep(
          id: OnboardingService.stepMemoTextButton,
          targetKey: _textMemoButtonKey,
          title: 'Create a text memo',
          description: 'Tap here to write a memo with title and notes.',
          preferredPlacement: TourBubblePlacement.above,
          highlightRadius: 28,
        ),
        FeatureTourStep(
          id: OnboardingService.stepMemoVoiceButton,
          targetKey: _voiceMemoButtonKey,
          title: 'Record voice memos',
          description: 'Tap here to quickly capture ideas with your voice.',
          preferredPlacement: TourBubblePlacement.above,
          highlightRadius: 28,
        ),
        FeatureTourStep(
          id: OnboardingService.stepNavToday,
          targetKey: _todayNavKey,
          title: 'Open your calendar',
          description: 'Go to Today to see and manage family schedules.',
          preferredPlacement: TourBubblePlacement.above,
          highlightRadius: 22,
        ),
      ];

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
        soundLevel: 0,
        elapsed: Duration.zero,
      ),
    );
    _activeRecordingPath = null;
    _recordingStartedAt = null;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _recordingAmplitudeSub?.cancel();
    _recordingAmplitudeSub = null;
    _stopVoiceBars();
  }

  Future<void> _startVoiceMemoCreation() async {
    if (_isVoiceTransitioning ||
        _isCreatingVoiceMemo ||
        _isRecordingSessionActive) {
      return;
    }

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

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 96000,
          sampleRate: 44100,
          numChannels: 1,
          noiseSuppress: true,
          echoCancel: true,
        ),
        path: path,
      );

      if (!mounted) {
        return;
      }

      _activeRecordingPath = path;
      _recordingStartedAt = DateTime.now();
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
        final startedAt = _recordingStartedAt;
        if (!mounted || startedAt == null) {
          return;
        }
        _updateVoiceUi(
          (current) =>
              current.copyWith(elapsed: DateTime.now().difference(startedAt)),
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

  Future<void> _stopVoiceMemoCreation({required bool save}) async {
    if (!_isRecordingSessionActive || _isCreatingVoiceMemo) {
      return;
    }

    _updateVoiceUi(
      (current) => current.copyWith(
        isListening: false,
        isVoiceTransitioning: true,
        isRecordingSessionActive: false,
        soundLevel: 0,
      ),
    );
    _stopVoiceBars();

    final duration = _recordingStartedAt == null
        ? _recordingElapsed
        : DateTime.now().difference(_recordingStartedAt!);
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
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      _resetVoiceOverlay();
      _showMessage('No recording file was created. Please try again.');
      return;
    }

    await _createVoiceMemoFromRecording(path, duration: duration);
  }

  Future<void> _openNewMemo() async {
    if (_isVoiceTransitioning ||
        _isCreatingVoiceMemo ||
        _isRecordingSessionActive) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const MemoDetailScreen(isCreating: true),
      ),
    );
  }

  Future<void> _createVoiceMemoFromRecording(
    String audioPath, {
    required Duration duration,
  }) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _resetVoiceOverlay();
      _showMessage('Please sign in to create a memo.');
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
      var uploadFailed = false;

      try {
        storagePath = 'voice_memos/${user.uid}/${docRef.id}.m4a';
        final storageRef = FirebaseStorage.instance.ref(storagePath);
        await storageRef.putFile(
          File(audioPath),
          SettableMetadata(contentType: 'audio/mp4'),
        );
        audioUrl = await storageRef.getDownloadURL();
      } catch (_) {
        uploadFailed = true;
        storagePath = '';
      }

      await docRef.set({
        'userId': user.uid,
        'memoType': 'voice',
        'title': title,
        'body': '',
        'audioUrl': audioUrl,
        'audioStoragePath': storagePath,
        'localAudioPath': audioPath,
        'audioDurationMillis': duration.inMilliseconds,
        'createdAtLocalMillis': createdAt.millisecondsSinceEpoch,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) {
        return;
      }

      _resetVoiceOverlay();

      if (uploadFailed) {
        _showMessage(
          'Voice memo saved locally. Audio upload will need to be retried later.',
        );
      }

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
      _showMessage('Failed to create recorded memo. Please try again.');
    }
  }

  static String _voiceMemoAutoTitle(DateTime createdAt) {
    return '${DateFormat('d MMMM yyyy').format(createdAt.toLocal())} recording';
  }

  static bool _isUnsetVoiceTitle(String title) {
    final normalized = title.trim();
    return normalized.isEmpty || normalized == 'Voice Memo';
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
    return DateFormat('d MMMM yyyy').format(localDate);
  }

  Future<void> _confirmAndDeleteMemo(_MemoItem item) async {
    if (_deletingMemoId != null) {
      return;
    }

    final confirmed = await _showDeleteMemoDialog(item);
    if (!mounted) {
      return;
    }

    if (!confirmed) {
      setState(() {
        _deleteActionMemoId = null;
      });
      return;
    }

    setState(() {
      _deletingMemoId = item.id;
    });

    try {
      if (item.audioStoragePath.isNotEmpty) {
        try {
          await FirebaseStorage.instance.ref(item.audioStoragePath).delete();
        } catch (_) {
          // The memo itself should still be removable if storage cleanup fails.
        }
      }

      await FirebaseFirestore.instance
          .collection('memos')
          .doc(item.id)
          .delete();

      if (!mounted) {
        return;
      }

      setState(() {
        _deleteActionMemoId = null;
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Memo deleted.'),
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
            content: Text('Failed to delete memo. Please try again.'),
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
                  'Delete this memo?',
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

  Future<void> _openMemoDetail(_MemoItem item) async {
    if (_deleteActionMemoId == item.id) {
      setState(() {
        _deleteActionMemoId = null;
      });
      return;
    }

    if (_deleteActionMemoId != null) {
      setState(() {
        _deleteActionMemoId = null;
      });
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

    if (!mounted || _deleteActionMemoId == null) {
      return;
    }

    setState(() {
      _deleteActionMemoId = null;
    });
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
    final actionBottomOffset = bottomInset + 102;
    final contentBottomSpacing = bottomInset + 122;
    final staticBody = _buildStaticBody(
      statusBarHeight: statusBarHeight,
      contentBottomSpacing: contentBottomSpacing,
    );

    return Scaffold(
      backgroundColor: bgColor,
      body: ValueListenableBuilder<_VoiceUiState>(
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
                          Positioned.fill(child: _buildVoiceComposerOverlay()),
                        Positioned(
                          left: 20,
                          right: 20,
                          bottom: actionBottomOffset,
                          child: _buildBottomActionRow(),
                        ),
                        if (_isOnboardingVisible)
                          Positioned.fill(child: _buildOnboardingOverlay()),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
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
                      navItemKeys: {2: _todayNavKey},
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
    return const AppHeader(title: 'Memos', useBlur: false);
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
                'Unable to load memos right now.',
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
                'Please sign in to view your memos.',
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
        if (sections.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'No memos yet. Use the center record button or the note button to create one.',
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

        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 128),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: sections
                  .map((section) => _buildSection(section))
                  .toList(growable: false),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSection(_MemoSection section) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            section.title.toUpperCase(),
            style: const TextStyle(
              color: accentColor,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 16),
        ...section.items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _MemoCard(
              item: item,
              showDeleteAction: _deleteActionMemoId == item.id,
              isDeleting: _deletingMemoId == item.id,
              onLongPress: () {
                setState(() {
                  _deleteActionMemoId = item.id;
                });
              },
              onTap: () {
                _openMemoDetail(item);
              },
              onDeleteTap: () => _confirmAndDeleteMemo(item),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActionRow() {
    return SizedBox(
      height: 84,
      child: _isVoiceOverlayVisible
          ? Align(alignment: Alignment.center, child: _buildRecordButton())
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildMemoActionButton(
                  icon: Icons.edit_note_rounded,
                  buttonKey: _textMemoButtonKey,
                  semanticLabel: 'Text memo',
                  onTap: _openNewMemo,
                  backgroundColor: Colors.white.withValues(alpha: 0.96),
                  iconColor: primaryColor,
                ),
                const SizedBox(width: 18),
                _buildMemoActionButton(
                  icon: Icons.mic_rounded,
                  buttonKey: _voiceMemoButtonKey,
                  semanticLabel: 'Voice memo',
                  onTap: _startVoiceMemoCreation,
                  backgroundColor: const Color(0xFFFFF4C7),
                  iconColor: const Color(0xFF9A6B00),
                ),
              ],
            ),
    );
  }

  Widget _buildRecordButton() {
    final isBusy = _isVoiceTransitioning || _isCreatingVoiceMemo;
    final isRecording = _isRecordingSessionActive;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isBusy
          ? null
          : isRecording
          ? () => _stopVoiceMemoCreation(save: true)
          : _startVoiceMemoCreation,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: isRecording ? 80 : 72,
        height: isRecording ? 80 : 72,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isRecording
                ? const [Color(0xFFF87171), Color(0xFFDC2626)]
                : const [accentColor, secondaryAccent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: isRecording ? 0.92 : 0.66),
            width: isRecording ? 4 : 3,
          ),
          boxShadow: [
            BoxShadow(
              color: (isRecording ? const Color(0xFFDC2626) : accentColor)
                  .withValues(alpha: 0.28),
              blurRadius: isRecording ? 30 : 24,
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
                  size: isRecording ? 34 : 32,
                  color: Colors.white,
                ),
        ),
      ),
    );
  }

  Widget _buildMemoActionButton({
    GlobalKey? buttonKey,
    required IconData icon,
    required String semanticLabel,
    required VoidCallback onTap,
    required Color backgroundColor,
    required Color iconColor,
  }) {
    return GestureDetector(
      key: buttonKey,
      onTap: onTap,
      child: Semantics(
        label: semanticLabel,
        button: true,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: backgroundColor,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.86)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(icon, color: iconColor, size: 24),
        ),
      ),
    );
  }

  Widget _buildOnboardingOverlay() {
    return FeatureTourOverlay(
      step: _memoTourSteps[_onboardingIndex],
      currentIndex: _onboardingIndex,
      totalSteps: _memoTourSteps.length,
      isBusy: _isOnboardingBusy,
      onPrevious: _onboardingIndex > 0 ? _previousOnboardingStep : null,
      onNext: _nextOnboardingStep,
      onSkip: _skipOnboarding,
      onComplete: _completeOnboarding,
    );
  }

  Widget _buildVoiceComposerOverlay() {
    final statusLabel = _isCreatingVoiceMemo
        ? 'Saving your voice memo'
        : _isVoiceTransitioning
        ? (_isRecordingSessionActive
              ? 'Preparing recording'
              : 'Finishing recording')
        : _isListening
        ? 'Recording in progress'
        : 'Ready to save';
    final helperLabel = _isCreatingVoiceMemo
        ? 'Your audio is being attached before the detail page opens.'
        : _isRecordingSessionActive
        ? 'Tap the center button again to finish and open the voice memo.'
        : 'Tap the microphone button to start a new recording.';

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
                if (_isRecordingSessionActive && !_isCreatingVoiceMemo)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _isVoiceTransitioning
                          ? null
                          : () => _stopVoiceMemoCreation(save: false),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Cancel'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF475569),
                        backgroundColor: Colors.white.withValues(alpha: 0.88),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                RepaintBoundary(child: _buildVoiceWaveBubble()),
                const SizedBox(height: 18),
                _buildRecordingDurationCard(),
                const SizedBox(height: 18),
                Text(
                  statusLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: primaryColor,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  helperLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                    height: 1.5,
                  ),
                ),
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
                ? _VoiceBars(
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
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
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
                  color: _isListening ? const Color(0xFFEF4444) : accentColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _isRecordingSessionActive ? 'Recording audio' : 'Voice memo',
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
          const SizedBox(height: 10),
          const Center(
            child: Text(
              'You can add typed notes on the detail page after saving.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
                height: 1.45,
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

class _VoiceUiState {
  const _VoiceUiState({
    this.isListening = false,
    this.isVoiceTransitioning = false,
    this.isRecordingSessionActive = false,
    this.isCreatingVoiceMemo = false,
    this.soundLevel = 0,
    this.elapsed = Duration.zero,
  });

  final bool isListening;
  final bool isVoiceTransitioning;
  final bool isRecordingSessionActive;
  final bool isCreatingVoiceMemo;
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
    double? soundLevel,
    Duration? elapsed,
  }) {
    return _VoiceUiState(
      isListening: isListening ?? this.isListening,
      isVoiceTransitioning: isVoiceTransitioning ?? this.isVoiceTransitioning,
      isRecordingSessionActive:
          isRecordingSessionActive ?? this.isRecordingSessionActive,
      isCreatingVoiceMemo: isCreatingVoiceMemo ?? this.isCreatingVoiceMemo,
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
        other.soundLevel == soundLevel &&
        other.elapsed == elapsed;
  }

  @override
  int get hashCode => Object.hash(
    isListening,
    isVoiceTransitioning,
    isRecordingSessionActive,
    isCreatingVoiceMemo,
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
      return isVoiceMemo ? 'Voice Memo' : 'Untitled Memo';
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

class _MemoCard extends StatelessWidget {
  final _MemoItem item;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDeleteTap;
  final bool showDeleteAction;
  final bool isDeleting;

  const _MemoCard({
    required this.item,
    this.onTap,
    this.onLongPress,
    this.onDeleteTap,
    this.showDeleteAction = false,
    this.isDeleting = false,
  });

  @override
  Widget build(BuildContext context) {
    final isVoice = item.isVoiceMemo;
    final cardColor = isVoice ? const Color(0xFFFFF8E3) : Colors.white;
    final borderColor = isVoice
        ? const Color(0x33E2B736)
        : _MemoScreenState.borderColor;
    final previewText = item.body.trim().isNotEmpty
        ? item.body
        : (isVoice ? _MemoScreenState._voiceMemoEmptyNotePreview : '');
    final icon = isVoice ? Icons.mic_rounded : Icons.edit_note_rounded;
    final iconColor = isVoice
        ? const Color(0xFF9A6B00)
        : _MemoScreenState.primaryColor;
    final iconBackground = isVoice
        ? Colors.white.withValues(alpha: 0.78)
        : AppTheme.lightBackground.withValues(alpha: 0.72);

    final card = Container(
      decoration: BoxDecoration(
        color: cardColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: (isVoice ? _MemoScreenState.accentColor : Colors.black)
                .withValues(alpha: isVoice ? 0.1 : 0.05),
            blurRadius: isVoice ? 18 : 2,
            offset: Offset(0, isVoice ? 8 : 1),
          ),
        ],
      ),
      padding: const EdgeInsets.all(21),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
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
          const SizedBox(height: 8),
          Text(
            previewText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: Color(0xFF64748B),
              height: 1.6,
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          card,
          Positioned(
            top: -10,
            right: -8,
            child: AnimatedScale(
              scale: showDeleteAction ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutBack,
              child: AnimatedOpacity(
                opacity: showDeleteAction ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: IgnorePointer(
                  ignoring: !showDeleteAction || isDeleting,
                  child: GestureDetector(
                    onTap: onDeleteTap,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: AppTheme.error.withValues(alpha: 0.12),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.error.withValues(alpha: 0.16),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Center(
                        child: isDeleting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.error,
                                ),
                              )
                            : const Icon(
                                Icons.delete_outline_rounded,
                                color: AppTheme.error,
                                size: 23,
                              ),
                      ),
                    ),
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
