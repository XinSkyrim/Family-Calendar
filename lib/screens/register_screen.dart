import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../constants/default_avatar.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static const bgColor = Color(0xFFFEF8E8);
  static const primaryColor = Color(0xFF0F172A);
  static const accentColor = Color(0xFFFAC638);
  static const secondaryAccent = Color(0xFFF59E0B);
  static const labelColor = Color(0xFF1E293B);
  static const hintColor = Color(0xFF64748B);
  static const placeholderColor = Color(0xFF94A3B8);
  static const fieldBackgroundColor = Color(0xFFFFFDF5);
  static const fieldBorderColor = Color(0xFFDDE2E7);
  static const String defaultAvatarUrl = DefaultAvatar.path;

  final fullNameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    fullNameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  String? _validateInputs() {
    final fullName = fullNameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (fullName.isEmpty) {
      return 'Please enter your full name.';
    }

    if (email.isEmpty) {
      return 'Please enter your email address.';
    }

    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
    if (!emailRegex.hasMatch(email)) {
      return 'Please enter a valid email address.';
    }

    if (password.isEmpty) {
      return 'Please enter your password.';
    }

    if (password.length < 8) {
      return 'Password must be at least 8 characters.';
    }

    if (password.length > 15) {
      return 'Password must be no more than 15 characters.';
    }

    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return 'Password must contain at least one uppercase letter.';
    }

    if (!RegExp(r'[a-z]').hasMatch(password)) {
      return 'Password must contain at least one lowercase letter.';
    }

    if (!RegExp(r'[0-9]').hasMatch(password)) {
      return 'Password must contain at least one number.';
    }

    return null;
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _register() async {
    final validationMessage = _validateInputs();
    if (validationMessage != null) {
      _showMessage(validationMessage);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final fullName = fullNameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    try {
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      final user = credential.user;

      if (user == null) {
        _showMessage('Registration failed. Please try again.');
        return;
      }

      await user.updateDisplayName(fullName);

      await user.sendEmailVerification();

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'fullName': fullName,
        'email': email,
        'emailVerified': false,
        'bio': '',
        'photoURL': defaultAvatarUrl,
        'status': 'pending_email_verification',
        'username': fullName,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'onboardingCompleted': false,
        'onboardingStep': '',
        'onboardingVersion': 0,
        'lastLoginAt': null,
      });

      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      _showMessage(
        'Account created successfully. Please check your email to verify your account before signing in.',
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    } on FirebaseAuthException catch (e) {
      String message = 'Registration failed. Please try again.';

      if (e.code == 'email-already-in-use') {
        message = 'This email is already in use.';
      } else if (e.code == 'invalid-email') {
        message = 'The email address is invalid.';
      } else if (e.code == 'weak-password') {
        message = 'The password is too weak.';
      } else if (e.code == 'operation-not-allowed') {
        message = 'Email/password sign-in is not enabled in Firebase Console.';
      } else if (e.code == 'too-many-requests') {
        message = 'Too many requests. Please try again later.';
      }

      _showMessage(message);
    } catch (e) {
      _showMessage('Something went wrong: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _goToLogin() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: bgColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

            final isSmallHeight = constraints.maxHeight < 760;
            final isVerySmallHeight = constraints.maxHeight < 700;

            final logoSize = isKeyboardOpen
                ? 120.0
                : isVerySmallHeight
                ? 135.0
                : isSmallHeight
                ? 160.0
                : 220.0;

            final topPadding = isKeyboardOpen
                ? 6.0
                : isVerySmallHeight
                ? 8.0
                : isSmallHeight
                ? 12.0
                : 24.0;

            final sidePadding = isVerySmallHeight ? 18.0 : 24.0;

            final gapAfterLogo = isKeyboardOpen
                ? 6.0
                : isVerySmallHeight
                ? 10.0
                : isSmallHeight
                ? 14.0
                : 24.0;

            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      sidePadding,
                      topPadding,
                      sidePadding,
                      12,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _buildLogoHeader(size: logoSize),
                          SizedBox(height: gapAfterLogo),
                          _buildRegisterCard(
                            compact: isSmallHeight || isKeyboardOpen,
                            veryCompact: isVerySmallHeight || isKeyboardOpen,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLogoHeader({double size = 220}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Image.asset(
          'assets/images/family_memo_logo.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
        ),
      ],
    );
  }

  Widget _buildRegisterCard({bool compact = false, bool veryCompact = false}) {
    final horizontalPadding = veryCompact
        ? 20.0
        : compact
        ? 24.0
        : 28.0;

    final verticalPadding = veryCompact
        ? 18.0
        : compact
        ? 22.0
        : 30.0;

    final fieldGap = veryCompact
        ? 12.0
        : compact
        ? 14.0
        : 18.0;

    final buttonGap = veryCompact
        ? 16.0
        : compact
        ? 20.0
        : 28.0;

    final footerGap = veryCompact
        ? 12.0
        : compact
        ? 16.0
        : 24.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: verticalPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildFullNameField(),
            SizedBox(height: fieldGap),
            _buildEmailField(),
            SizedBox(height: fieldGap),
            _buildPasswordField(),
            SizedBox(height: buttonGap),
            _buildCreateAccountButton(),
            SizedBox(height: footerGap),
            _buildBottomNavigation(),
          ],
        ),
      ),
    );
  }

  Widget _buildFullNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Full Name',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: fieldBackgroundColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: fieldBorderColor, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: TextField(
              controller: fullNameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                hintText: 'Enter your full name',
                hintStyle: TextStyle(color: placeholderColor, fontSize: 16),
                border: InputBorder.none,
              ),
              style: const TextStyle(fontSize: 16, color: primaryColor),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmailField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Email Address',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: fieldBackgroundColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: fieldBorderColor, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              decoration: const InputDecoration(
                hintText: 'name@example.com',
                hintStyle: TextStyle(color: placeholderColor, fontSize: 16),
                border: InputBorder.none,
              ),
              style: const TextStyle(fontSize: 16, color: primaryColor),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Password',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: fieldBackgroundColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: fieldBorderColor, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: TextField(
              controller: passwordController,
              obscureText: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _isLoading ? null : _register(),
              decoration: const InputDecoration(
                hintText: '8-15 chars, upper, lower, number',
                hintStyle: TextStyle(color: placeholderColor, fontSize: 16),
                border: InputBorder.none,
              ),
              style: const TextStyle(fontSize: 16, color: primaryColor),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCreateAccountButton() {
    return Opacity(
      opacity: _isLoading ? 0.85 : 1,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [accentColor, secondaryAccent],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: accentColor.withOpacity(0.2),
              blurRadius: 15,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _isLoading ? null : _register,
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: _isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Text(
                        'Create Account',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return Center(
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: hintColor,
          ),
          children: [
            const TextSpan(text: 'Already have an account? '),
            TextSpan(
              text: 'Sign In',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: secondaryAccent,
              ),
              recognizer: TapGestureRecognizer()..onTap = _goToLogin,
            ),
          ],
        ),
      ),
    );
  }
}
