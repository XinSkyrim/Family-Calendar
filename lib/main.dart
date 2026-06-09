import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'firebase_options.dart';
import 'screens/memo_screen.dart';
import 'screens/login_screen.dart';
import 'services/user_profile_service.dart';
import 'themes/app_theme.dart';
import 'services/session_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  SystemChrome.setSystemUIOverlayStyle(AppTheme.systemUiOverlayStyle);

  runApp(const MyApp());

  unawaited(UserProfileService.init().catchError((_) {}));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Family Notes',
      debugShowCheckedModeBanner: false,
      //-----------------------------------------------
      builder: (context, child) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            final currentFocus = FocusManager.instance.primaryFocus;
            if (currentFocus != null && currentFocus.hasFocus) {
              currentFocus.unfocus();
            }
          },
          child: child ?? const SizedBox.shrink(),
        );
      },
      //-------------------------------Keyboard defocus global logic
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppTheme.accent),
        scaffoldBackgroundColor: AppTheme.pageBackground,
        textTheme: GoogleFonts.plusJakartaSansTextTheme(),
        primaryTextTheme: GoogleFonts.plusJakartaSansTextTheme(),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppTheme.headerBackground,
          surfaceTintColor: Colors.transparent,
          systemOverlayStyle: AppTheme.systemUiOverlayStyle,
        ),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  Future<void>? _sessionCheckFuture;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _sessionCheckFuture = SessionManager.signOutIfExpired();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkSessionWhenAppResumed();
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      SessionManager.markActiveNow();
    }
  }

  Future<void> _checkSessionWhenAppResumed() async {
    setState(() {
      _sessionCheckFuture = SessionManager.signOutIfExpired();
    });

    await _sessionCheckFuture;

    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      await SessionManager.markActiveNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData) {
          return const LoginScreen();
        }

        return FutureBuilder<void>(
          future: _sessionCheckFuture,
          builder: (context, sessionSnapshot) {
            if (sessionSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final user = FirebaseAuth.instance.currentUser;

            if (user == null) {
              return const LoginScreen();
            }

            return const MemoScreen();
          },
        );
      },
    );
  }
}
