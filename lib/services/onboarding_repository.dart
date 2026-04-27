import 'package:cloud_firestore/cloud_firestore.dart';

class OnboardingRepository {
  OnboardingRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const int currentVersion = 1;

  Future<bool> shouldShowOnboarding(String userId) async {
    final doc = await _firestore.collection('users').doc(userId).get();
    if (!doc.exists) {
      return true;
    }

    final data = doc.data() ?? <String, dynamic>{};
    final completed = data['onboardingCompleted'] == true;
    final version = (data['onboardingVersion'] as num?)?.toInt() ?? 0;

    return !completed || version < currentVersion;
  }

  Future<void> setCurrentStep(String userId, String step) async {
    await _firestore.collection('users').doc(userId).set({
      'onboardingStep': step,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> completeOnboarding(String userId) async {
    await _firestore.collection('users').doc(userId).set({
      'onboardingCompleted': true,
      'onboardingVersion': currentVersion,
      'onboardingStep': 'done',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> resetOnboarding(String userId) async {
    await _firestore.collection('users').doc(userId).set({
      'onboardingCompleted': false,
      'onboardingStep': 'start',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
