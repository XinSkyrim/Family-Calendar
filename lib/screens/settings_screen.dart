import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

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
                _buildSettingItem('Account Details', Icons.person),
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
