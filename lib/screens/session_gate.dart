import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/session_manager.dart';
import 'login_screen.dart';
import 'memo_screen.dart';

class SessionGate extends StatefulWidget {
  const SessionGate({super.key});

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate>
    with WidgetsBindingObserver {
  Widget? _startScreen;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkSession();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkSession();
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      SessionManager.markActiveNow();
    }
  }

  Future<void> _checkSession() async {
    await SessionManager.signOutIfExpired();

    final user = FirebaseAuth.instance.currentUser;

    if (!mounted) return;

    if (user != null && user.emailVerified) {
      await SessionManager.markActiveNow();

      setState(() {
        _startScreen = const MemoScreen();
      });
    } else {
      setState(() {
        _startScreen = const LoginScreen();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_startScreen == null) {
      return const Scaffold(
        backgroundColor: Color(0xFFFEF8E8),
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return _startScreen!;
  }
}