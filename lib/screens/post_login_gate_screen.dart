import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/onboarding_repository.dart';
import 'memo_screen.dart';
import 'onboarding_flow_screen.dart';

class PostLoginGateScreen extends StatefulWidget {
  const PostLoginGateScreen({super.key});

  @override
  State<PostLoginGateScreen> createState() => _PostLoginGateScreenState();
}

class _PostLoginGateScreenState extends State<PostLoginGateScreen> {
  final OnboardingRepository _onboardingRepository = OnboardingRepository();
  late final Future<bool> _shouldShowOnboarding;

  @override
  void initState() {
    super.initState();
    _shouldShowOnboarding = _loadGateDecision();
  }

  Future<bool> _loadGateDecision() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return false;
    }

    return _onboardingRepository.shouldShowOnboarding(user.uid);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _shouldShowOnboarding,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.data == true) {
          return OnboardingFlowScreen(userId: user.uid);
        }

        return const MemoScreen();
      },
    );
  }
}
