import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../navigation/app_bottom_nav.dart';
import '../themes/app_theme.dart';
import '../widgets/app_header.dart';
import '../widgets/bottom_navigation_bar.dart';
import 'login_screen.dart';
import 'onboarding_flow_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

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
  String _familyName = 'No Family';
  String _photoURL = '';

  final ImagePicker _picker = ImagePicker();

  /// 把这里换成你自己的系统头像链接
  /// 建议直接放 Firebase Storage 的公开下载地址
  final List<String> _defaultAvatarUrls = [
    'https://firebasestorage.googleapis.com/v0/b/family-calendar-65220.firebasestorage.app/o/default_avatars%2FGrandfather.png?alt=media&token=1c9c2184-a688-4767-a017-0dd7fd4a8bef',
    'https://firebasestorage.googleapis.com/v0/b/family-calendar-65220.firebasestorage.app/o/default_avatars%2FGrandmother.png?alt=media&token=69a1ba36-bbe4-4f22-8e06-2594b9c9cff5',
    'https://firebasestorage.googleapis.com/v0/b/family-calendar-65220.firebasestorage.app/o/default_avatars%2FDad.png?alt=media&token=1231ae66-d746-4ab0-8399-a03cea1559c3',
    'https://firebasestorage.googleapis.com/v0/b/family-calendar-65220.firebasestorage.app/o/default_avatars%2FMom.png?alt=media&token=d75267c6-0db8-414a-9ae5-acd0ed596283',
    'https://firebasestorage.googleapis.com/v0/b/family-calendar-65220.firebasestorage.app/o/default_avatars%2FSon.png?alt=media&token=ff37db2c-b550-4ee6-8002-0a24040afed5',
    'https://firebasestorage.googleapis.com/v0/b/family-calendar-65220.firebasestorage.app/o/default_avatars%2FDaughter.png?alt=media&token=57a326d0-fe1c-489d-9bc4-ec4e722743c8',
  ];

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser == null) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      String fullName = 'User';
      String photoURL = '';
      String familyName = 'No Family';

      if (userDoc.exists) {
        final data = userDoc.data();

        if (data != null) {
          fullName = (data['fullName'] ?? 'User').toString();
          photoURL = (data['photoURL'] ?? '').toString();
        }
      }

      final familySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('families')
          .limit(1)
          .get();

      if (familySnapshot.docs.isNotEmpty) {
        final familyData = familySnapshot.docs.first.data();
        familyName =
            (familyData['familyName'] ?? familyData['name'] ?? 'My Family')
                .toString();
      }

      if (!mounted) return;
      setState(() {
        _fullName = fullName;
        _photoURL = photoURL;
        _familyName = familyName;
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
                    'Select a system avatar or upload your own photo',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 20),

                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _defaultAvatarUrls.length,
                    gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: 1,
                    ),
                    itemBuilder: (context, index) {
                      final avatarUrl = _defaultAvatarUrls[index];
                      return _buildSystemAvatarItem(
                        avatarUrl: avatarUrl,
                        onTap: () async {
                          Navigator.of(sheetContext).pop();
                          await _selectSystemAvatar(avatarUrl);
                        },
                      );
                    },
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
                          color: SettingsScreen.accentColor.withOpacity(0.25),
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

  Future<void> _selectSystemAvatar(String avatarUrl) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('User not logged in')));
        return;
      }

      if (!mounted) return;
      setState(() {
        _isUploadingPhoto = true;
      });

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .set({
        'photoURL': avatarUrl,
        'avatarType': 'system',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _photoURL = avatarUrl;
        _isUploadingPhoto = false;
      });

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
      ).showSnackBar(SnackBar(content: Text('Failed to update avatar: $e')));
    }
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
      final Reference storageRef = FirebaseStorage.instance
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

  @override
  Widget build(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: SettingsScreen.bgColor,
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: statusBarHeight,
            child: const ColoredBox(color: AppTheme.headerBackground),
          ),
          SafeArea(
            bottom: false,
            child: Stack(
              children: [
                Column(
                  children: [
                    const AppHeader(title: 'Settings', useBlur: false),
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
        ],
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
                        _photoURL.isNotEmpty
                            ? Image.network(
                          _photoURL,
                          fit: BoxFit.cover,
                          errorBuilder:
                              (context, error, stackTrace) {
                            return const Center(
                              child: Icon(
                                Icons.person,
                                size: 60,
                                color: Colors.white,
                              ),
                            );
                          },
                        )
                            : const Center(
                          child: Icon(
                            Icons.person,
                            size: 60,
                            color: Colors.white,
                          ),
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

  Widget _buildSystemAvatarItem({
    required String avatarUrl,
    required VoidCallback onTap,
  }) {
    final bool isSelected = _photoURL == avatarUrl;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected
                ? SettingsScreen.accentColor
                : const Color(0xFFE2E8F0),
            width: isSelected ? 3 : 1.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: ClipOval(
            child: Image.network(
              avatarUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: const Color(0xFFF8FAFC),
                  child: const Center(
                    child: Icon(
                      Icons.person,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }


  Future<void> _startOnboardingReplay() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please sign in first.')));
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OnboardingFlowScreen(userId: currentUser.uid, isReplay: true),
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
                  color: Colors.black.withOpacity(0.05),
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
                _buildSettingItem('Family Members', Icons.people),
                const Divider(
                  color: Color(0xFFF1F5F9),
                  height: 1,
                  indent: 56,
                  endIndent: 20,
                ),
                _buildSettingItem(
                  'App Tour',
                  Icons.assistant_navigation,
                  onTap: _startOnboardingReplay,
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
          await FirebaseAuth.instance.signOut();
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: SettingsScreen.accentColor.withOpacity(0.1),
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
