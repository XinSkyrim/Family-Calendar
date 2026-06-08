import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'login_screen.dart';
import 'voice_memo_detail_screen.dart';
import 'voice_memo_models.dart';

class VoiceMemoScreen extends StatefulWidget {
  const VoiceMemoScreen({super.key});

  @override
  State<VoiceMemoScreen> createState() => _VoiceMemoScreenState();
}

class _VoiceMemoScreenState extends State<VoiceMemoScreen>
    with SingleTickerProviderStateMixin {
  static const bgColor = Color(0xFFFDFBF7);
  static const primaryColor = Color(0xFF0F172A);
  static const accentColor = Color(0xFFE2B736);

  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final stt.SpeechToText _speech = stt.SpeechToText();
  late final AnimationController _voiceBarsController;

  bool _isCheckingAuth = true;
  bool _speechReady = false;
  bool _isListening = false;
  bool _isVoiceTransitioning = false;
  bool _isSubmitting = false;
  String _activeInputMode = 'text';
  User? _currentUser;
  double _soundLevel = 0;
  int _voiceSessionId = 0;

  @override
  void initState() {
    super.initState();
    _voiceBarsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _ensureAuthenticated();
    await _initSpeech();
  }

  Future<void> _ensureAuthenticated() async {
    final user = FirebaseAuth.instance.currentUser;
    if (!mounted) return;

    if (user == null) {
      setState(() {
        _isCheckingAuth = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to use voice notes.')),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      });
      return;
    }

    setState(() {
      _currentUser = user;
      _isCheckingAuth = false;
    });
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

  bool get _isSpeechActive => _isListening || _speech.isListening;

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

  Stream<List<VoiceMemoRecord>> _memoStream() {
    final user = _currentUser;
    if (user == null) {
      return const Stream<List<VoiceMemoRecord>>.empty();
    }

    return FirebaseFirestore.instance
        .collection('voice_memos')
        .where('userId', isEqualTo: user.uid)
        .snapshots()
        .map((snapshot) {
          final memos = snapshot.docs
              .map(VoiceMemoRecord.fromFirestore)
              .toList();
          memos.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return memos;
        });
  }

  Future<void> _toggleListening() async {
    if (_isSubmitting || _isVoiceTransitioning) {
      return;
    }

    if (_isSpeechActive) {
      await _stopListening();
      return;
    }

    final ready = await _ensureSpeechReady();
    if (!ready) {
      _showMessage('Voice input is not available on this device.');
      return;
    }

    if (!mounted) return;

    _inputFocusNode.unfocus();
    FocusScope.of(context).unfocus();

    setState(() {
      _isVoiceTransitioning = true;
      _soundLevel = 0;
    });
    _startVoiceBars();

    final sessionId = ++_voiceSessionId;

    try {
      await _speech.listen(
        listenFor: const Duration(minutes: 5),
        pauseFor: const Duration(minutes: 5),
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
        ),
        onSoundLevelChange: (level) {
          if (!mounted || sessionId != _voiceSessionId) return;
          setState(() {
            _soundLevel = level;
          });
        },
        onResult: (result) {
          if (!mounted || sessionId != _voiceSessionId) return;
          setState(() {
            _activeInputMode = 'voice';
            _inputController.text = result.recognizedWords;
            _inputController.selection = TextSelection.collapsed(
              offset: _inputController.text.length,
            );
          });
        },
      );

      if (!mounted || sessionId != _voiceSessionId) return;

      setState(() {
        _isListening = true;
        _activeInputMode = 'voice';
      });
    } catch (_) {
      _voiceSessionId++;
      _resetVoiceUiState();
      _showMessage('Unable to start voice input. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isVoiceTransitioning = false;
        });
      }
    }
  }

  Future<void> _stopListening() async {
    if (_isVoiceTransitioning) {
      return;
    }

    setState(() {
      _isVoiceTransitioning = true;
    });

    try {
      if (_speech.isListening || _isListening) {
        await _speech.stop();
      }
    } catch (_) {
      // Keep the UI recoverable even if the platform stop request fails.
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

  Future<void> _submitMemo() async {
    final user = _currentUser;
    final rawInput = _inputController.text.trim();

    if (user == null) {
      _showMessage('Please sign in again.');
      return;
    }

    if (rawInput.isEmpty) {
      _showMessage('Please enter or record something first.');
      return;
    }

    if (_isSpeechActive) {
      await _stopListening();
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'australia-southeast1',
      ).httpsCallable('summarizeVoiceMemo');

      final result = await callable.call(<String, dynamic>{
        'input': rawInput,
        'inputMode': _activeInputMode,
        'timezone': DateTime.now().timeZoneName,
        'currentDateISO': _currentDateISO(),
      });

      final summary = VoiceMemoSummary.fromMap(
        Map<String, dynamic>.from(result.data as Map),
      );

      await FirebaseFirestore.instance.collection('voice_memos').add({
        'userId': user.uid,
        'rawInput': rawInput,
        'inputMode': _activeInputMode,
        'summary': summary.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      setState(() {
        _inputController.clear();
        _activeInputMode = 'text';
      });
      _showMessage('Voice note summarized and saved.');
    } on FirebaseFunctionsException catch (error) {
      _showMessage(_mapFunctionError(error));
    } catch (_) {
      _showMessage('Failed to save note. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  String _mapFunctionError(FirebaseFunctionsException error) {
    switch (error.code) {
      case 'unauthenticated':
        return 'Please sign in to continue.';
      case 'invalid-argument':
        return 'Please provide valid note content.';
      case 'resource-exhausted':
        return 'Too many requests. Please wait a few seconds.';
      default:
        return error.message ?? 'AI summary failed. Please try again.';
    }
  }

  String _currentDateISO() {
    final now = DateTime.now();
    return DateFormat('yyyy-MM-dd').format(now);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: primaryColor,
        ),
      );
  }

  void _handleSpeechStatus(String status) {
    if (!mounted) return;

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
    if (!mounted) return;

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
    _voiceBarsController.dispose();
    _speech.cancel();
    _inputFocusNode.dispose();
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        surfaceTintColor: bgColor,
        titleSpacing: 20,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AI Voice Note',
              style: TextStyle(
                color: primaryColor,
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Speak or type, then let AI organize your note',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: _isCheckingAuth
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    child: Column(
                      children: [
                        _buildComposer(),
                        const SizedBox(height: 16),
                        if (_isListening || _isVoiceTransitioning) ...[
                          _ListeningBanner(
                            animation: _voiceBarsController,
                            level: _soundLevel,
                          ),
                          const SizedBox(height: 16),
                        ],
                        _buildInputActions(),
                      ],
                    ),
                  ),
                  Expanded(child: _buildMemoList()),
                ],
              ),
            ),
    );
  }

  Widget _buildComposer() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                _isListening ? 'Listening...' : 'Ready for your voice note',
                style: TextStyle(
                  color: _isListening ? accentColor : const Color(0xFF64748B),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _inputController,
              focusNode: _inputFocusNode,
              maxLines: 6,
              minLines: 4,
              onChanged: (_) {
                if (_activeInputMode != 'voice') {
                  setState(() {
                    _activeInputMode = 'text';
                  });
                }
              },
              decoration: const InputDecoration(
                hintText:
                    'Type notes or tap the microphone to record your thoughts...',
                hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 15),
                border: InputBorder.none,
              ),
              style: const TextStyle(
                color: primaryColor,
                fontSize: 15,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputActions() {
    final isVoiceButtonDisabled = _isSubmitting || _isVoiceTransitioning;
    final voiceLabel = _isVoiceTransitioning
        ? (_isSpeechActive ? 'Stopping...' : 'Preparing...')
        : (_isListening ? 'Stop voice' : 'Voice input');

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: isVoiceButtonDisabled ? null : _toggleListening,
            icon: _isVoiceTransitioning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: primaryColor,
                    ),
                  )
                : Icon(_isListening ? Icons.stop : Icons.mic_none),
            label: Text(voiceLabel),
            style: OutlinedButton.styleFrom(
              foregroundColor: primaryColor,
              side: BorderSide(
                color: _isListening ? accentColor : const Color(0xFFE2E8F0),
              ),
              backgroundColor: _isListening
                  ? const Color(0x22E2B736)
                  : Colors.white,
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: (_isSubmitting || _isVoiceTransitioning)
                ? null
                : _submitMemo,
            icon: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: primaryColor,
                    ),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(_isSubmitting ? 'Summarizing...' : 'AI summarize'),
            style: ElevatedButton.styleFrom(
              elevation: 0,
              foregroundColor: primaryColor,
              backgroundColor: accentColor,
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMemoList() {
    return StreamBuilder<List<VoiceMemoRecord>>(
      stream: _memoStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Unable to load memos right now.\nPlease create one first or check Firestore rules.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.6,
                ),
              ),
            ),
          );
        }

        final memos = snapshot.data ?? const <VoiceMemoRecord>[];
        if (memos.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Your summarized memos will appear here after AI finishes organizing them.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 15,
                  height: 1.6,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          itemCount: memos.length,
          separatorBuilder: (context, index) => const SizedBox(height: 14),
          itemBuilder: (context, index) => _MemoCard(memo: memos[index]),
        );
      },
    );
  }
}

class _MemoCard extends StatelessWidget {
  const _MemoCard({required this.memo});

  final VoiceMemoRecord memo;

  @override
  Widget build(BuildContext context) {
    final dateText = DateFormat('d/M/yyyy').format(memo.createdAt);

    return InkWell(
      borderRadius: BorderRadius.circular(30),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => VoiceMemoDetailScreen(memo: memo)),
        );
      },
      child: Ink(
        decoration: BoxDecoration(
          color: const Color(0xFF1F1F22),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                memo.summary.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$dateText  ${memo.summary.category}',
                style: const TextStyle(
                  color: Color(0xFFA1A1AA),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                memo.summary.summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFE4E4E7),
                  fontSize: 15,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              const Divider(color: Color(0xFF34343A), height: 1),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    memo.inputMode == 'voice' ? Icons.mic : Icons.notes,
                    size: 15,
                    color: const Color(0xFFA1A1AA),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    memo.inputMode == 'voice' ? 'Voice note' : 'Text note',
                    style: const TextStyle(
                      color: Color(0xFFA1A1AA),
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.arrow_forward_ios,
                    size: 12,
                    color: Color(0xFFE2B736),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListeningBanner extends StatelessWidget {
  const _ListeningBanner({required this.animation, required this.level});

  final Animation<double> animation;
  final double level;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x22E2B736)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _VoiceBars(
              animation: animation,
              level: level,
              color: _VoiceMemoScreenState.accentColor,
            ),
          ),
          const SizedBox(width: 14),
          const Text(
            'Listening...',
            style: TextStyle(
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
