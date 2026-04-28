import 'package:flutter/material.dart';

import '../services/onboarding_repository.dart';
import '../widgets/onboarding_overlay.dart';
import 'calendar_screen.dart';
import 'memo_screen.dart';

class OnboardingFlowScreen extends StatefulWidget {
  const OnboardingFlowScreen({super.key, required this.userId, this.isReplay = false});

  final String userId;
  final bool isReplay;

  @override
  State<OnboardingFlowScreen> createState() => _OnboardingFlowScreenState();
}

class _OnboardingFlowScreenState extends State<OnboardingFlowScreen> {
  final OnboardingRepository _onboardingRepository = OnboardingRepository();
  int _stepIndex = 0;
  bool _isCompleting = false;

  static const List<_StepCopy> _steps = [
    _StepCopy(
      key: 'memo_intro',
      title: 'Welcome to Memos',
      description:
          'This is your family memo area. You can quickly write things down and keep them organized.',
      nextLabel: 'Start guide',
      page: _OnboardingPage.memo,
      targetId: 'memo_text_button',
    ),
    _StepCopy(
      key: 'memo_text',
      title: 'Create a text memo',
      description: 'Tap the highlighted note button at the bottom.',
      page: _OnboardingPage.memo,
      targetId: 'memo_text_button',
      requireTargetTap: true,
    ),
    _StepCopy(
      key: 'memo_voice',
      title: 'Create a voice memo',
      description: 'Now tap the highlighted microphone button.',
      page: _OnboardingPage.memo,
      targetId: 'memo_voice_button',
      requireTargetTap: true,
    ),
    _StepCopy(
      key: 'calendar_intro',
      title: 'Now the Calendar',
      description:
          'Great. Next we will see how to browse dates and add tasks in calendar.',
      nextLabel: 'Go to calendar',
      page: _OnboardingPage.calendar,
      targetId: 'calendar_date_selector',
    ),
    _StepCopy(
      key: 'calendar_date',
      title: 'Switch the date',
      description: 'Tap any highlighted date card in the date selector.',
      page: _OnboardingPage.calendar,
      targetId: 'calendar_date_selector',
      requireTargetTap: true,
    ),
    _StepCopy(
      key: 'calendar_add',
      title: 'Add a new task',
      description: 'Tap the highlighted + button to finish the guided overview.',
      page: _OnboardingPage.calendar,
      targetId: 'calendar_add_fab',
      requireTargetTap: true,
    ),
  ];

  _StepCopy get _currentStep => _steps[_stepIndex];

  Future<void> _nextStep() async {
    if (_isCompleting) {
      return;
    }

    await _onboardingRepository.setCurrentStep(widget.userId, _currentStep.key);

    if (_stepIndex >= _steps.length - 1) {
      await _finishTour();
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _stepIndex += 1;
    });
  }

  Future<void> _skipTour() async {
    if (_isCompleting) {
      return;
    }
    await _finishTour();
  }

  Future<void> _finishTour() async {
    if (_isCompleting) {
      return;
    }

    setState(() {
      _isCompleting = true;
    });

    await _onboardingRepository.completeOnboarding(widget.userId);

    if (!mounted) {
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MemoScreen()),
    );
  }

  OnboardingOverlayData _buildOverlayData() {
    return OnboardingOverlayData(
      title: _currentStep.title,
      description: _currentStep.description,
      stepNumber: _stepIndex + 1,
      totalSteps: _steps.length,
      nextLabel: _currentStep.nextLabel,
      targetId: _currentStep.targetId,
      requireTargetTap: _currentStep.requireTargetTap,
      onNext: _nextStep,
      onSkip: _skipTour,
    );
  }

  @override
  Widget build(BuildContext context) {
    final overlay = _buildOverlayData();

    if (_currentStep.page == _OnboardingPage.memo) {
      return MemoScreen(onboardingOverlay: overlay);
    }

    return CalendarScreen(onboardingOverlay: overlay);
  }
}

enum _OnboardingPage { memo, calendar }

class _StepCopy {
  const _StepCopy({
    required this.key,
    required this.title,
    required this.description,
    required this.page,
    this.nextLabel = 'Next',
    this.targetId,
    this.requireTargetTap = false,
  });

  final String key;
  final String title;
  final String description;
  final String nextLabel;
  final _OnboardingPage page;
  final String? targetId;
  final bool requireTargetTap;
}
