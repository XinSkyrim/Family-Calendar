import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class OnboardingService {
  const OnboardingService._();

  static const int appOnboardingVersion = 1;

  static const String stepMemoTextButton = 'memo_text_button';
  static const String stepMemoVoiceButton = 'memo_voice_button';
  static const String stepNavToday = 'nav_today';
  static const String stepCalendarAddFab = 'calendar_add_fab';
  static const String stepCompleted = 'completed';

  static CollectionReference<Map<String, dynamic>> get _users =>
      FirebaseFirestore.instance.collection('users');

  static Future<OnboardingState?> getCurrentState() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return null;
    }

    final doc = await _users.doc(user.uid).get();
    final data = doc.data() ?? <String, dynamic>{};

    final completed = data['onboardingCompleted'] == true;
    final version = (data['onboardingVersion'] is int)
        ? data['onboardingVersion'] as int
        : 0;
    final step = (data['onboardingStep'] as String?)?.trim();

    return OnboardingState(
      uid: user.uid,
      completed: completed,
      version: version,
      step: _sanitizeStep(step),
    );
  }

  static String _sanitizeStep(String? step) {
    if (step == null || step.isEmpty) {
      return stepMemoTextButton;
    }

    switch (step) {
      case stepMemoTextButton:
      case stepMemoVoiceButton:
      case stepNavToday:
      case stepCalendarAddFab:
      case stepCompleted:
        return step;
      default:
        return stepMemoTextButton;
    }
  }

  static bool shouldStart(OnboardingState state) {
    if (state.version < appOnboardingVersion) {
      return true;
    }
    return !state.completed;
  }

  static Future<void> markStep(String step) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    await _users.doc(user.uid).set({
      'onboardingCompleted': false,
      'onboardingVersion': appOnboardingVersion,
      'onboardingStep': _sanitizeStep(step),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> complete() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    await _users.doc(user.uid).set({
      'onboardingCompleted': true,
      'onboardingVersion': appOnboardingVersion,
      'onboardingStep': stepCompleted,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

class OnboardingState {
  const OnboardingState({
    required this.uid,
    required this.completed,
    required this.version,
    required this.step,
  });

  final String uid;
  final bool completed;
  final int version;
  final String step;
}
