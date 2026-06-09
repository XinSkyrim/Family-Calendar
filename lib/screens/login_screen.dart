import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/services.dart';

import '../constants/default_avatar.dart';
import '../services/session_manager.dart';
import '../services/user_profile_service.dart';
import 'register_screen.dart';
import 'memo_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const bgColor = Color(0xFFFEF8E8);
  static const primaryColor = Color(0xFF0F172A);
  static const accentColor = Color(0xFFFAC638);
  static const secondaryAccent = Color(0xFFF59E0B);
  static const labelColor = Color(0xFF334155);
  static const hintColor = Color(0xFF7E7664);
  static const borderColor = Color(0xFFE2E8F0);

  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool obscurePassword = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty) {
      _showMessage('Please enter your email.');
      return;
    }

    if (password.isEmpty) {
      _showMessage('Please enter your password.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final auth = FirebaseAuth.instance;
      final firestore = FirebaseFirestore.instance;

      final userCredential = await auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      await userCredential.user?.reload();

      final user = auth.currentUser;

      if (user == null) {
        throw FirebaseAuthException(
          code: 'user-null',
          message: 'Login failed. Please try again.',
        );
      }

      if (!user.emailVerified) {
        await user.sendEmailVerification();
        await auth.signOut();

        if (!mounted) return;

        _showMessage(
          'Please verify your email first. We have sent the verification email again.',
        );

        return;
      }

      final userDocRef = firestore.collection('users').doc(user.uid);
      final userDoc = await userDocRef.get();
      final now = Timestamp.now();

      if (!userDoc.exists) {
        final fallbackName = user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : email.split('@').first;

        await userDocRef.set({
          'uid': user.uid,
          'email': user.email ?? email,
          'username': fallbackName.replaceAll(' ', ''),
          'fullName': fallbackName,
          'photoURL': user.photoURL ?? DefaultAvatar.path,
          'bio': '',
          'role': 'owner',
          'status': 'active',
          'emailVerified': true,
          'loginProvider': 'email',
          'createdAt': now,
          'updatedAt': now,
          'lastLoginAt': now,
        });
      } else {
        await userDocRef.set({
          'status': 'active',
          'emailVerified': true,
          'loginProvider': 'email',
          'lastLoginAt': now,
          'updatedAt': now,
        }, SetOptions(merge: true));
      }

      await UserProfileService.update(
        fullName: user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : email.split('@').first,
        photoUrl: user.photoURL ?? DefaultAvatar.path,
      );

      if (!mounted) return;

      await SessionManager.markActiveNow();

      _showMessage('Login successful.');

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MemoScreen()),
      );
    } on FirebaseAuthException catch (e) {
      _showMessage(_getFirebaseAuthErrorMessage(e));
    } catch (e) {
      _showMessage('Login failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<UserCredential> _signInWithGoogle() async {
    if (kIsWeb) {
      final GoogleAuthProvider googleProvider = GoogleAuthProvider();
      return await FirebaseAuth.instance.signInWithPopup(googleProvider);
    }

    const String webClientId =
        '502418497658-fjkdh7slqsunccdm6hhh0gr9cjvqvfoo.apps.googleusercontent.com';

    final GoogleSignIn googleSignIn = GoogleSignIn(
      scopes: ['email'],
      serverClientId: webClientId,
    );

    // 清掉上一次残留状态，避免 reauth failed
    await googleSignIn.signOut();

    final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

    if (googleUser == null) {
      throw FirebaseAuthException(
        code: 'google-sign-in-cancelled',
        message: 'Google login was cancelled.',
      );
    }

    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;

    if (googleAuth.idToken == null) {
      throw FirebaseAuthException(
        code: 'missing-google-id-token',
        message: 'Google ID token is missing. Please check serverClientId.',
      );
    }

    final OAuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    return await FirebaseAuth.instance.signInWithCredential(credential);
  }

  Future<void> _handleGoogleSignIn() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod('TextInput.hide');
    await Future.delayed(const Duration(milliseconds: 150));

    if (_isLoading || _isGoogleLoading) return;

    setState(() {
      _isGoogleLoading = true;
    });

    try {
      final auth = FirebaseAuth.instance;
      final firestore = FirebaseFirestore.instance;

      final userCredential = await _signInWithGoogle();

      await userCredential.user?.reload();

      final user = auth.currentUser ?? userCredential.user;

      if (user == null) {
        throw FirebaseAuthException(
          code: 'google-user-null',
          message: 'Google login failed. Please try again.',
        );
      }

      final userDocRef = firestore.collection('users').doc(user.uid);
      final userDoc = await userDocRef.get();
      final now = Timestamp.now();

      final fallbackName = user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : (user.email ?? 'google_user').split('@').first;

      if (!userDoc.exists) {
        await userDocRef.set({
          'uid': user.uid,
          'email': user.email ?? '',
          'username': fallbackName.replaceAll(' ', ''),
          'fullName': fallbackName,
          'photoURL': user.photoURL ?? DefaultAvatar.path,
          'bio': '',
          'role': 'owner',
          'status': 'active',
          'emailVerified': user.emailVerified,
          'loginProvider': 'google',
          'createdAt': now,
          'updatedAt': now,
          'lastLoginAt': now,
        });
      } else {
        // await userDocRef.set({
        //   'email': user.email ?? '',
        //   'fullName': fallbackName,
        //   'photoURL': user.photoURL ?? '',
        //   'status': 'active',
        //   'emailVerified': user.emailVerified,
        //   'loginProvider': 'google',
        //   'lastLoginAt': now,
        //   'updatedAt': now,
        // }, SetOptions(merge: true));
        final data = userDoc.data() ?? {};

        final currentUsername = (data['username'] ?? '').toString().trim();
        final currentFullName = (data['fullName'] ?? '').toString().trim();
        final currentPhotoURL = (data['photoURL'] ?? '').toString().trim();

        final updateData = <String, dynamic>{
          'email': user.email ?? data['email'] ?? '',
          'status': 'active',
          'emailVerified': true,
          'loginProvider': 'google',
          'lastLoginAt': now,
          'updatedAt': now,
        };

        if (currentUsername.isEmpty) {
          updateData['username'] = fallbackName.replaceAll(' ', '');
        }

        if (currentFullName.isEmpty) {
          updateData['fullName'] = fallbackName;
        }

        if (currentPhotoURL.isEmpty) {
          updateData['photoURL'] = user.photoURL ?? DefaultAvatar.path;
        }

        await userDocRef.set(updateData, SetOptions(merge: true));
      }

      await UserProfileService.update(
        fullName: fallbackName,
        photoUrl: user.photoURL ?? DefaultAvatar.path,
      );

      if (!mounted) return;

      await SessionManager.markActiveNow();

      _showMessage('Google login successful.');

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MemoScreen()),
      );
    } on FirebaseAuthException catch (e) {
      _showMessage(_getFirebaseAuthErrorMessage(e));
    } catch (e) {
      _showMessage('Google login failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isGoogleLoading = false;
        });
      }
    }
  }

  void _showForgotPasswordDialog() {
    final resetEmailController = TextEditingController(
      text: emailController.text.trim(),
    );

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: bgColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text(
            'Reset Password',
            style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: resetEmailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email Address',
              hintText: 'Enter your email',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancel', style: TextStyle(color: hintColor)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              onPressed: () async {
                final email = resetEmailController.text.trim();

                if (email.isEmpty) {
                  _showMessage('Please enter your email.');
                  return;
                }

                Navigator.pop(dialogContext);
                await _sendPasswordResetEmail(email);
              },
              child: const Text(
                'Send',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _sendPasswordResetEmail(String email) async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (!mounted) return;

      _showMessage('Password reset email sent. Please check your inbox.');
    } on FirebaseAuthException catch (e) {
      _showMessage(_getFirebaseAuthErrorMessage(e));
    } catch (e) {
      _showMessage('Failed to send reset email: $e');
    }
  }

  String _getFirebaseAuthErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'The email address is invalid.';
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'user-not-found':
        return 'No account found for this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'network-request-failed':
        return 'Network error. Please check your connection.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'missing-email':
        return 'Please enter your email.';
      case 'account-exists-with-different-credential':
        return 'This email is already linked to another sign-in method.';
      default:
        return e.message ?? 'Operation failed. Please try again.';
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 24,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _buildLogoHeader(),
                          const SizedBox(height: 32),
                          _buildLoginCard(),
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

  Widget _buildLogoHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Image.asset(
          'assets/images/family_memo_logo.png',
          width: 220,
          height: 220,
          fit: BoxFit.contain,
        ),
      ],
    );
  }

  Widget _buildLoginCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color(0xFFF1F5F9), width: 1),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.08),
            blurRadius: 50,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(33),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildEmailField(),
            const SizedBox(height: 24),
            _buildPasswordField(),
            const SizedBox(height: 24),
            _buildSignInButton(),
            const SizedBox(height: 14),
            _buildGoogleSignInButton(),
            const SizedBox(height: 32),
            _buildFooterLinks(),
          ],
        ),
      ),
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
            color: const Color(0xFFFFFDF5).withOpacity(0.5),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 21, vertical: 4),
            child: TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              decoration: InputDecoration(
                hintText: 'hello@family.com',
                hintStyle: TextStyle(
                  color: hintColor.withOpacity(0.5),
                  fontSize: 16,
                ),
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
            color: const Color(0xFFFFFDF5).withOpacity(0.5),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 21, vertical: 4),
            child: TextField(
              controller: passwordController,
              obscureText: obscurePassword,
              textAlignVertical: TextAlignVertical.center,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _isLoading ? null : _signIn(),
              style: const TextStyle(
                fontSize: 16,
                color: primaryColor,
                fontFamily: 'Plus Jakarta Sans',
                height: 1.2,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                hintText: '••••••••',
                hintStyle: TextStyle(
                  color: hintColor.withOpacity(0.5),
                  fontSize: 16,
                ),
                border: InputBorder.none,
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() {
                      obscurePassword = !obscurePassword;
                    });
                  },
                  icon: Icon(
                    obscurePassword ? Icons.visibility_off : Icons.visibility,
                    color: hintColor,
                    size: 16,
                  ),
                  splashRadius: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSignInButton() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [accentColor, secondaryAccent],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading || _isGoogleLoading ? null : _signIn,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: _isLoading
                ? const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  )
                : const Text(
                    'Sign In',
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
    );
  }

  Widget _buildGoogleSignInButton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading || _isGoogleLoading ? null : _handleGoogleSignIn,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: _isGoogleLoading
                ? const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                      ),
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'G',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Continue with Google',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooterLinks() {
    return Column(
      children: [
        Center(
          child: GestureDetector(
            onTap: _showForgotPasswordDialog,
            child: Text(
              'Forgot Password?',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: hintColor,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Divider(color: Color(0xFFF1F5F9), height: 1, thickness: 1),
        const SizedBox(height: 25),
        Center(
          child: RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: hintColor,
              ),
              children: [
                const TextSpan(text: 'Don\'t have an account? '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => const RegisterScreen(),
                        ),
                      );
                    },
                    child: const Text(
                      'Create one',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: accentColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
