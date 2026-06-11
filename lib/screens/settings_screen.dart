import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../navigation/app_bottom_nav.dart';
import '../services/session_manager.dart';
import '../services/user_profile_service.dart';
import '../themes/app_theme.dart';
import '../widgets/avatar_image.dart';
import '../widgets/bottom_navigation_bar.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();

  static const bgColor = AppTheme.pageBackground;
  static const primaryColor = Color(0xFF0F172A);
  static const accentColor = Color(0xFFE2B736);
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = true;
  bool _isUploadingPhoto = false;

  String _fullName = 'User';
  String _photoURL = '';

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    try {
      final profile = UserProfileService.profile.value;
      if (!mounted) return;
      setState(() {
        _fullName = profile.fullName;
        _photoURL = profile.photoUrl;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load user info: $e')));
    }
  }

  Future<void> _showAvatarOptionsSheet() async {
    if (_isUploadingPhoto) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Choose Avatar',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: SettingsScreen.primaryColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Upload your own photo',
                    style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 20),

                  GestureDetector(
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      await _pickAndUploadAvatar();
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E7),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: SettingsScreen.accentColor.withValues(
                            alpha: 0.25,
                          ),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.photo_library_outlined,
                            color: SettingsScreen.accentColor,
                            size: 20,
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Upload photo from gallery',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: SettingsScreen.primaryColor,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 14,
                            color: Color(0xFF64748B),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickAndUploadAvatar() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('User not logged in')));
        return;
      }

      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      if (!mounted) return;
      setState(() {
        _isUploadingPhoto = true;
      });

      final String fileName =
          'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final FirebaseStorage avatarStorage = FirebaseStorage.instanceFor(
        bucket: 'gs://family-calendar-65220-au',
      );

      final Reference storageRef = avatarStorage
          .ref()
          .child('users')
          .child(currentUser.uid)
          .child('avatars')
          .child(fileName);

      UploadTask uploadTask;

      if (kIsWeb) {
        final bytes = await pickedFile.readAsBytes();
        uploadTask = storageRef.putData(
          bytes,
          SettableMetadata(contentType: 'image/jpeg'),
        );
      } else {
        final file = File(pickedFile.path);
        uploadTask = storageRef.putFile(
          file,
          SettableMetadata(contentType: 'image/jpeg'),
        );
      }

      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .set({
            'photoURL': downloadUrl,
            'avatarType': 'upload',
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _photoURL = downloadUrl;
        _isUploadingPhoto = false;
      });

      await UserProfileService.update(photoUrl: downloadUrl);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Avatar updated successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploadingPhoto = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to upload avatar: $e')));
    }
  }

  Future<void> _showContactUsDialog() async {
    final controller = TextEditingController();

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        var isSubmitting = false;

        Future<void> submitFeedback(StateSetter setDialogState) async {
          final message = controller.text.trim();
          if (message.isEmpty || isSubmitting) return;

          setDialogState(() {
            isSubmitting = true;
          });

          try {
            final currentUser = FirebaseAuth.instance.currentUser;
            await FirebaseFirestore.instance
                .collection('feedbackMessages')
                .add({
                  'message': message,
                  'source': 'settings_contact_us',
                  'status': 'new',
                  'userId': currentUser?.uid,
                  'userEmail': currentUser?.email,
                  'userName': _fullName,
                  'createdAt': FieldValue.serverTimestamp(),
                });

            if (!mounted || !dialogContext.mounted) return;
            Navigator.of(dialogContext).pop();
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                const SnackBar(
                  content: Text('Thanks for your feedback.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
          } catch (_) {
            if (!mounted || !dialogContext.mounted) return;
            setDialogState(() {
              isSubmitting = false;
            });
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                const SnackBar(
                  content: Text('Failed to send feedback. Please try again.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
          }
        }

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final canSubmit =
                controller.text.trim().isNotEmpty && !isSubmitting;

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
                  border: Border.all(color: const Color(0xFFF1F5F9)),
                  boxShadow: [
                    BoxShadow(
                      color: SettingsScreen.accentColor.withValues(alpha: 0.08),
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
                          color: SettingsScreen.accentColor.withValues(
                            alpha: 0.1,
                          ),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const Icon(
                          Icons.contact_support_rounded,
                          color: SettingsScreen.accentColor,
                          size: 30,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Contact us',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: SettingsScreen.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Leave us a message to help improve Cottage.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.mutedText,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: controller,
                      enabled: !isSubmitting,
                      minLines: 4,
                      maxLines: 6,
                      maxLength: 800,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Write your feedback here...',
                        hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                        filled: true,
                        fillColor: const Color(0xFFFFFCF5),
                        counterStyle: const TextStyle(
                          color: AppTheme.mutedText,
                          fontSize: 11,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(
                            color: Color(0xFFF1E8D8),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(
                            color: Color(0xFFF1E8D8),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(
                            color: SettingsScreen.accentColor,
                            width: 1.4,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: canSubmit
                          ? () => submitFeedback(setDialogState)
                          : null,
                      child: Container(
                        width: double.infinity,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: canSubmit
                                ? const [AppTheme.accent, AppTheme.accentDark]
                                : const [Color(0xFFE2E8F0), Color(0xFFE2E8F0)],
                          ),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: canSubmit
                              ? [
                                  BoxShadow(
                                    color: AppTheme.accent.withValues(
                                      alpha: 0.2,
                                    ),
                                    blurRadius: 15,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : null,
                        ),
                        child: Center(
                          child: isSubmitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.black87,
                                    ),
                                  ),
                                )
                              : const Text(
                                  'Send',
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
                          side: const BorderSide(
                            color: AppTheme.lightBackground,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          backgroundColor: AppTheme.lightBackground,
                          foregroundColor: SettingsScreen.primaryColor,
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () => Navigator.of(dialogContext).pop(),
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
      },
    );

    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SettingsScreen.bgColor,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildProfileSection(),
                        _buildSettingsList(),
                        _buildLogOutButton(context),
                        const SizedBox(height: 96),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: AppBottomNavigationBar(
                currentIndex: 3,
                onItemTapped: (index) {
                  navigateFromBottomNav(
                    context,
                    targetIndex: index,
                    currentIndex: 3,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              GestureDetector(
                onTap: _isUploadingPhoto ? null : _showAvatarOptionsSheet,
                child: Container(
                  width: 128,
                  height: 128,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: SettingsScreen.accentColor,
                      width: 4,
                    ),
                    color: const Color(0xFFE8B4A8),
                  ),
                  child: ClipOval(
                    child: _isLoading
                        ? const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Stack(
                            fit: StackFit.expand,
                            children: [
                              AvatarImage(
                                imageUrl: _photoURL,
                                placeholderColor: const Color(0xFFE8B4A8),
                              ),
                              if (_isUploadingPhoto)
                                Container(
                                  color: Colors.black26,
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: _isUploadingPhoto ? null : _showAvatarOptionsSheet,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: SettingsScreen.accentColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: SettingsScreen.bgColor, width: 4),
                  ),
                  child: const Center(
                    child: Icon(Icons.edit, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _isLoading ? 'Loading...' : _fullName,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: SettingsScreen.primaryColor,
              letterSpacing: -0.6,
            ),
          ),
          // const SizedBox(height: 4),
          // Text(
          //   _isLoading ? '' : _familyName,
          //   style: const TextStyle(
          //     fontSize: 16,
          //     fontWeight: FontWeight.w500,
          //     color: SettingsScreen.accentColor,
          //   ),
          // ),
        ],
      ),
    );
  }

  Widget _buildSettingsList() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFF1F5F9), width: 1),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildSettingItem(
                  'Account Details',
                  Icons.person,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AccountDetailsScreen(),
                      ),
                    );
                  },
                ),
                const Divider(
                  color: Color(0xFFF1F5F9),
                  height: 1,
                  indent: 56,
                  endIndent: 20,
                ),
                _buildSettingItem('Notifications', Icons.notifications),
                const Divider(
                  color: Color(0xFFF1F5F9),
                  height: 1,
                  indent: 56,
                  endIndent: 20,
                ),
                // Subscription is hidden for now.
                _buildSettingItem(
                  'Contact us',
                  Icons.contact_support_rounded,
                  onTap: _showContactUsDialog,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogOutButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: GestureDetector(
        onTap: () async {
          await SessionManager.signOutCompletely();

          if (!context.mounted) return;

          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.logout, size: 18, color: Color(0xFF475569)),
              SizedBox(width: 8),
              Text(
                'Log Out',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF475569),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingItem(String title, IconData icon, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: SettingsScreen.accentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(48),
              ),
              child: Center(
                child: Icon(icon, size: 16, color: SettingsScreen.accentColor),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: SettingsScreen.primaryColor,
                ),
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              size: 12,
              color: Color(0xFF64748B),
            ),
          ],
        ),
      ),
    );
  }
}

class AccountDetailsScreen extends StatefulWidget {
  const AccountDetailsScreen({super.key});

  @override
  State<AccountDetailsScreen> createState() => _AccountDetailsScreenState();
}

class _AccountDetailsScreenState extends State<AccountDetailsScreen> {
  late Future<_AccountDetails> _detailsFuture;

  @override
  void initState() {
    super.initState();
    _detailsFuture = _loadAccountDetails();
  }

  Future<_AccountDetails> _loadAccountDetails() async {
    final user = FirebaseAuth.instance.currentUser;
    final cachedProfile = UserProfileService.profile.value;

    if (user == null) {
      return _AccountDetails(
        fullName: cachedProfile.fullName,
        email: '',
        loginProvider: 'unknown',
        emailVerified: false,
      );
    }

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final data = userDoc.data() ?? <String, dynamic>{};

    return _AccountDetails(
      fullName: _stringValue(data['fullName'] ?? data['username']).isNotEmpty
          ? _stringValue(data['fullName'] ?? data['username'])
          : cachedProfile.fullName,
      email: _stringValue(data['email']).isNotEmpty
          ? _stringValue(data['email'])
          : user.email ?? '',
      loginProvider: _stringValue(data['loginProvider']).isNotEmpty
          ? _stringValue(data['loginProvider'])
          : _providerLabelFromAuth(user),
      emailVerified: data['emailVerified'] is bool
          ? data['emailVerified'] as bool
          : user.emailVerified,
      createdAt: _dateTimeValue(data['createdAt']),
    );
  }

  static String _stringValue(Object? value) {
    return (value ?? '').toString().trim();
  }

  static DateTime? _dateTimeValue(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }

  static String _providerLabelFromAuth(User user) {
    final providerIds = user.providerData
        .map((provider) => provider.providerId)
        .toSet();
    if (providerIds.contains('google.com')) {
      return 'google';
    }
    if (providerIds.contains('password')) {
      return 'email';
    }
    return providerIds.isEmpty ? 'unknown' : providerIds.first;
  }

  Future<void> _showPasswordUpdateDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _PasswordUpdateDialog(),
    );
  }

  Future<void> _showNameUpdateDialog(String currentName) async {
    final updatedName = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _NameUpdateDialog(initialName: currentName),
    );

    if (updatedName == null || !mounted) {
      return;
    }

    setState(() {
      _detailsFuture = _loadAccountDetails();
    });
    _showMessage('Name updated successfully.');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SettingsScreen.bgColor,
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<_AccountDetails>(
          future: _detailsFuture,
          builder: (context, snapshot) {
            final details = snapshot.data;
            final isLoading =
                snapshot.connectionState == ConnectionState.waiting &&
                details == null;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AppTheme.backButton(context),
                  ),
                  const SizedBox(height: 18),
                  if (isLoading)
                    const Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (snapshot.hasError)
                    _buildErrorState()
                  else ...[
                    Builder(
                      builder: (context) {
                        final accountDetails = details!;
                        return Column(
                          children: [
                            _AccountDetailsCard(
                              icon: Icons.badge_outlined,
                              title: 'Personal Info',
                              children: [
                                _DetailRow(
                                  label: 'Name',
                                  value: accountDetails.fullName,
                                  onTap: () => _showNameUpdateDialog(
                                    accountDetails.fullName,
                                  ),
                                ),
                                _DetailRow(
                                  label: 'Email',
                                  value: accountDetails.email,
                                  showDivider: false,
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            _AccountDetailsCard(
                              icon: Icons.manage_accounts_outlined,
                              title: 'Account',
                              children: [
                                _DetailRow(
                                  label: 'Sign-in',
                                  value: accountDetails.loginProviderLabel,
                                ),
                                _DetailRow(
                                  label: 'Email verified',
                                  value: accountDetails.emailVerified
                                      ? 'Yes'
                                      : 'No',
                                ),
                                _DetailRow(
                                  label: 'Member since',
                                  value: _formatDate(accountDetails.createdAt),
                                  showDivider: false,
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            _AccountDetailsCard(
                              icon: Icons.shield_outlined,
                              title: 'Security & Settings',
                              children: [
                                _ActionRow(
                                  icon: Icons.lock_reset_rounded,
                                  label: 'Password Update',
                                  onTap: _showPasswordUpdateDialog,
                                ),
                                _ActionRow(
                                  icon: Icons.notifications_none_rounded,
                                  label: 'Notification Preferences',
                                  onTap: () => _showMessage(
                                    'Notification preferences are coming soon.',
                                  ),
                                ),
                                _ActionRow(
                                  icon: Icons.privacy_tip_outlined,
                                  label: 'Privacy Settings',
                                  onTap: () => _showMessage(
                                    'Privacy settings are coming soon.',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      margin: const EdgeInsets.only(top: 80),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF1E8D8)),
      ),
      child: const Text(
        'Unable to load account details.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppTheme.mutedText,
        ),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) {
      return 'Not available';
    }
    return DateFormat('MMM d, yyyy').format(date.toLocal());
  }
}

class _AccountDetailsCard extends StatelessWidget {
  const _AccountDetailsCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFF4EDE2).withValues(alpha: 0.7),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4A463F).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: SettingsScreen.accentColor, size: 21),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: SettingsScreen.primaryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.showDivider = true,
    this.onTap,
  });

  final String label;
  final String value;
  final bool showDivider;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 120, child: _DetailLabel(label)),
          Expanded(child: _DetailValue(value, textAlign: TextAlign.right)),
          if (onTap != null) ...[
            const SizedBox(width: 8),
            const Icon(Icons.edit_outlined, color: Color(0xFF7E7664), size: 16),
          ],
        ],
      ),
    );

    return Column(
      children: [
        if (onTap == null)
          row
        else
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: row,
          ),
        if (showDivider) const Divider(height: 1, color: Color(0xFFF4EDE2)),
      ],
    );
  }
}

class _DetailLabel extends StatelessWidget {
  const _DetailLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      maxLines: 1,
      softWrap: false,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: Color(0xFF4E4537),
      ),
    );
  }
}

class _DetailValue extends StatelessWidget {
  const _DetailValue(this.value, {required this.textAlign});

  final String value;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final displayValue = value.isEmpty ? 'Not available' : value;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Text(
              displayValue,
              maxLines: 1,
              softWrap: false,
              textAlign: textAlign,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: SettingsScreen.primaryColor,
                height: 1.35,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 13),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF4E4537), size: 21),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: SettingsScreen.primaryColor,
                ),
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              color: Color(0xFF7E7664),
              size: 13,
            ),
          ],
        ),
      ),
    );
  }
}

class _NameUpdateDialog extends StatefulWidget {
  const _NameUpdateDialog({required this.initialName});

  final String initialName;

  @override
  State<_NameUpdateDialog> createState() => _NameUpdateDialogState();
}

class _NameUpdateDialogState extends State<_NameUpdateDialog> {
  late final TextEditingController _nameController;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _updateName() async {
    final name = _nameController.text.trim();
    final validationMessage = _validateName(name);
    if (validationMessage != null) {
      _showMessage(validationMessage);
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showMessage('User not logged in.');
      return;
    }

    setState(() {
      _isUpdating = true;
    });

    try {
      await user.updateDisplayName(name);
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fullName': name,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await UserProfileService.update(fullName: name);

      if (!mounted) return;
      Navigator.of(context).pop(name);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isUpdating = false;
      });
      _showMessage(e.message ?? 'Failed to update name.');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isUpdating = false;
      });
      _showMessage('Failed to update name.');
    }
  }

  String? _validateName(String name) {
    if (name.isEmpty) {
      return 'Please enter your name.';
    }
    if (name.length > 50) {
      return 'Name must be no more than 50 characters.';
    }
    return null;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isUpdating,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Update Name',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: SettingsScreen.primaryColor,
                ),
              ),
              const SizedBox(height: 18),
              _ProfileTextField(
                controller: _nameController,
                label: 'Name',
                enabled: !_isUpdating,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (!_isUpdating) {
                    _updateName();
                  }
                },
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SettingsScreen.accentColor,
                    foregroundColor: SettingsScreen.primaryColor,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: _isUpdating ? null : _updateName,
                  child: _isUpdating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              SettingsScreen.primaryColor,
                            ),
                          ),
                        )
                      : const Text(
                          'Update',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 52,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.lightBackground),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    backgroundColor: AppTheme.lightBackground,
                    foregroundColor: SettingsScreen.primaryColor,
                  ),
                  onPressed: _isUpdating ? null : () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PasswordUpdateDialog extends StatefulWidget {
  const _PasswordUpdateDialog();

  @override
  State<_PasswordUpdateDialog> createState() => _PasswordUpdateDialogState();
}

class _PasswordUpdateDialogState extends State<_PasswordUpdateDialog> {
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  bool _isUpdating = false;

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _updatePassword() async {
    final newPassword = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();
    final validationMessage = _validateNewPassword(
      newPassword,
      confirmPassword,
    );

    if (validationMessage != null) {
      _showMessage(validationMessage);
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showMessage('User not logged in.');
      return;
    }

    setState(() {
      _isUpdating = true;
    });

    try {
      await user.updatePassword(newPassword);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Password updated successfully.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isUpdating = false;
      });
      _showMessage(_passwordUpdateErrorMessage(e));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isUpdating = false;
      });
      _showMessage('Failed to update password.');
    }
  }

  String? _validateNewPassword(String password, String confirmPassword) {
    if (password.isEmpty) {
      return 'Please enter your new password.';
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
    if (confirmPassword.isEmpty) {
      return 'Please confirm your new password.';
    }
    if (password != confirmPassword) {
      return 'Passwords do not match.';
    }
    return null;
  }

  String _passwordUpdateErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'requires-recent-login':
        return 'Please log in again before updating your password.';
      case 'weak-password':
        return 'The password is too weak.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'network-request-failed':
        return 'Network error. Please check your connection.';
      default:
        return e.message ?? 'Failed to update password.';
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isUpdating,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Update Password',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: SettingsScreen.primaryColor,
                ),
              ),
              const SizedBox(height: 18),
              _PasswordField(
                controller: _newPasswordController,
                label: 'New password',
                obscureText: _obscureNewPassword,
                enabled: !_isUpdating,
                onToggleVisibility: () {
                  setState(() {
                    _obscureNewPassword = !_obscureNewPassword;
                  });
                },
              ),
              const SizedBox(height: 14),
              _PasswordField(
                controller: _confirmPasswordController,
                label: 'Confirm password',
                obscureText: _obscureConfirmPassword,
                enabled: !_isUpdating,
                onToggleVisibility: () {
                  setState(() {
                    _obscureConfirmPassword = !_obscureConfirmPassword;
                  });
                },
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SettingsScreen.accentColor,
                    foregroundColor: SettingsScreen.primaryColor,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: _isUpdating ? null : _updatePassword,
                  child: _isUpdating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              SettingsScreen.primaryColor,
                            ),
                          ),
                        )
                      : const Text(
                          'Update',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 52,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.lightBackground),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    backgroundColor: AppTheme.lightBackground,
                    foregroundColor: SettingsScreen.primaryColor,
                  ),
                  onPressed: _isUpdating ? null : () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.obscureText,
    required this.enabled,
    required this.onToggleVisibility,
  });

  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final bool enabled;
  final VoidCallback onToggleVisibility;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: obscureText,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: AppTheme.mutedText,
          fontWeight: FontWeight.w600,
        ),
        filled: true,
        fillColor: const Color(0xFFFFFCF5),
        suffixIcon: IconButton(
          onPressed: enabled ? onToggleVisibility : null,
          icon: Icon(
            obscureText ? Icons.visibility_off : Icons.visibility,
            color: AppTheme.mutedText,
            size: 18,
          ),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFF1E8D8)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFF1E8D8)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(
            color: SettingsScreen.accentColor,
            width: 1.4,
          ),
        ),
      ),
    );
  }
}

class _ProfileTextField extends StatelessWidget {
  const _ProfileTextField({
    required this.controller,
    required this.label,
    required this.enabled,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: AppTheme.mutedText,
          fontWeight: FontWeight.w600,
        ),
        filled: true,
        fillColor: const Color(0xFFFFFCF5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFF1E8D8)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFF1E8D8)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(
            color: SettingsScreen.accentColor,
            width: 1.4,
          ),
        ),
      ),
    );
  }
}

class _AccountDetails {
  const _AccountDetails({
    required this.fullName,
    required this.email,
    required this.loginProvider,
    required this.emailVerified,
    this.createdAt,
  });

  final String fullName;
  final String email;
  final String loginProvider;
  final bool emailVerified;
  final DateTime? createdAt;

  String get loginProviderLabel {
    switch (loginProvider.toLowerCase()) {
      case 'google':
      case 'google.com':
        return 'Google';
      case 'email':
      case 'password':
        return 'Email';
      default:
        return loginProvider.isEmpty ? 'Unknown' : loginProvider;
    }
  }
}
