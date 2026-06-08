import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../navigation/app_bottom_nav.dart';
import '../themes/app_theme.dart';
import '../widgets/app_today_top_bar.dart';
import '../widgets/bottom_navigation_bar.dart';
import 'create_family_dialog.dart';
import 'family_screen.dart';

// Remote avatars (expires after ~7 days from Figma export)
const _avatar1 =
    'https://www.figma.com/api/mcp/asset/5dc71948-299e-4b3b-8f45-10afbf1a750a';
const _avatar2 =
    'https://www.figma.com/api/mcp/asset/06ff95bd-fcec-4d-b260-778a17cbf7ae';
const _avatar3 =
    'https://www.figma.com/api/mcp/asset/d1a3cb03-516d-4788-a974-afeeb6c81cc1';
const _avatar4 =
    'https://www.figma.com/api/mcp/asset/03802e4e-f495-4b7e-902a-f25d65096656';
const _avatar5 =
    'https://www.figma.com/api/mcp/asset/99a00811-045c-47fa-8c19-8bb31fe139a4';
const _avatar6 =
    'https://www.figma.com/api/mcp/asset/436113e7-c2dd-46a7-85f6-0bbfb0be1806';
const _avatar7 =
    'https://www.figma.com/api/mcp/asset/c4ac9b5a-eb93-4cfe-bde6-ac024476efbd';
const _avatar8 =
    'https://www.figma.com/api/mcp/asset/86824d61-0625-4c86-8c95-a942c59dab7b';
const _avatar9 =
    'https://www.figma.com/api/mcp/asset/63ffd1a8-2bd8-4239-a051-a79bafc20a76';

const List<String> _fallbackAvatars = [
  _avatar1,
  _avatar2,
  _avatar3,
  _avatar4,
  _avatar5,
  _avatar6,
  _avatar7,
  _avatar8,
  _avatar9,
];

const _cardBorder = Color.fromRGBO(236, 91, 19, 0.05);

class SelectFamilyScreen extends StatefulWidget {
  const SelectFamilyScreen({Key? key}) : super(key: key);

  @override
  State<SelectFamilyScreen> createState() => _SelectFamilyScreenState();
}

class _SelectFamilyScreenState extends State<SelectFamilyScreen> {
  int _selectedNavIndex = 2;
  late Future<List<_FamilyGroup>> _groupsFuture;

  @override
  void initState() {
    super.initState();
    _groupsFuture = _loadFamilies();
  }

  Future<void> _refreshFamilies() async {
    final future = _loadFamilies();
    setState(() {
      _groupsFuture = future;
    });
    await future;
  }

  Future<String?> _loadMemberAvatar(String memberId) async {
    final firestore = FirebaseFirestore.instance;

    final userDoc = await firestore.collection('users').doc(memberId).get();
    if (userDoc.exists) {
      final userData = userDoc.data() ?? {};
      final photoURL = (userData['photoURL'] ?? userData['avatar'] ?? '')
          .toString()
          .trim();
      if (photoURL.isNotEmpty) {
        return photoURL;
      }
    }

    final familyMemberDoc = await firestore
        .collection('users')
        .doc(memberId)
        .collection('families')
        .doc(memberId)
        .get();

    if (familyMemberDoc.exists) {
      final String photoURL = (familyMemberDoc.data()?['photoURL'] ?? '')
          .toString()
          .trim();
      if (photoURL.isNotEmpty) {
        return photoURL;
      }
    }

    return null;
  }

  Future<List<_FamilyGroup>> _loadFamilies() async {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      throw Exception('Current user is null. Please login first.');
    }

    final String uid = currentUser.uid;
    final FirebaseFirestore firestore = FirebaseFirestore.instance;

    final membershipSnapshot = await firestore
        .collection('users')
        .doc(uid)
        .collection('families')
        .get();

    if (membershipSnapshot.docs.isEmpty) {
      return [];
    }

    final List<_FamilyGroup> result = [];

    for (int i = 0; i < membershipSnapshot.docs.length; i++) {
      final membershipData = membershipSnapshot.docs[i].data();

      final String familyId = (membershipData['familyId'] ?? '')
          .toString()
          .trim();

      if (familyId.isEmpty) {
        continue;
      }

      final familyDoc = await firestore
          .collection('families')
          .doc(familyId)
          .get();

      if (!familyDoc.exists) {
        continue;
      }

      final familyData = familyDoc.data() ?? {};

      final membersSnapshot = await firestore
          .collection('families')
          .doc(familyId)
          .collection('members')
          .get();

      final List<String> avatars = [];

      for (int j = 0; j < membersSnapshot.docs.length; j++) {
        final memberDoc = membersSnapshot.docs[j];

        String? photoUrl = (memberDoc.data()['photoURL'] ?? '')
            .toString()
            .trim();

        if (photoUrl.isEmpty) {
          final loadedAvatar = await _loadMemberAvatar(memberDoc.id);
          photoUrl = loadedAvatar ?? '';
        }

        if (photoUrl.isNotEmpty) {
          avatars.add(photoUrl);
        } else {
          avatars.add(_fallbackAvatars[(i + j) % _fallbackAvatars.length]);
        }

        if (avatars.length == 3) {
          break;
        }
      }

      if (avatars.isEmpty) {
        avatars.add(_fallbackAvatars[i % _fallbackAvatars.length]);
      }

      final int memberCount = membersSnapshot.docs.length;
      final int extraCount = memberCount > 3 ? memberCount - 3 : 0;

      result.add(
        _FamilyGroup(
          id: familyId,
          name:
              (familyData['familyName'] ??
                      membershipData['familyName'] ??
                      'Unnamed Family')
                  .toString(),
          memberCount: memberCount,
          avatars: avatars,
          extraCount: extraCount,
        ),
      );
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final mediaPadding = MediaQuery.of(context).padding;
    final statusBarHeight = mediaPadding.top;
    final bottomInset = mediaPadding.bottom;
    final actionBottomOffset = bottomInset + 102;
    final listBottomSpacing = bottomInset + 164;

    return Scaffold(
      backgroundColor: AppTheme.pageBackground,
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
            child: Center(
              child: Container(
                width: 430,
                constraints: const BoxConstraints(maxWidth: 430),
                height: double.infinity,
                color: AppTheme.pageBackground,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Column(
                        children: [
                          const SizedBox(height: 77),
                          Expanded(child: _buildList()),
                          SizedBox(height: listBottomSpacing),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: AppTodayTopBar(
                        title: DateFormat('d MMMM').format(DateTime.now()),
                      ),
                    ),
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: actionBottomOffset,
                      child: _buildCreateFamilyButton(),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: AppBottomNavigationBar(
                        currentIndex: _selectedNavIndex,
                        onItemTapped: _onNavItemTapped,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return FutureBuilder<List<_FamilyGroup>>(
      future: _groupsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.accent),
          );
        }

        if (snapshot.hasError) {
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              children: [
                const SizedBox(height: 80),
                const Icon(
                  Icons.error_outline,
                  size: 40,
                  color: Colors.redAccent,
                ),
                const SizedBox(height: 12),
                Text(
                  'Failed to load groups\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.headline,
                  ),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: _refreshFamilies,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.accent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      'Retry',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final groups = snapshot.data ?? [];

        if (groups.isEmpty) {
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: const Column(
              children: [
                SizedBox(height: 80),
                Icon(
                  Icons.groups_outlined,
                  size: 44,
                  color: AppTheme.inactiveIcon,
                ),
                SizedBox(height: 12),
                Text(
                  'No group found',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.headline,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Create a new group or join one via invitation link',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.mutedText,
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _refreshFamilies,
          color: AppTheme.accent,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: groups
                  .map(
                    (group) => Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: _FamilyGroupCard(
                        group: group,
                        onTap: () {
                          Navigator.of(context)
                              .push(
                                MaterialPageRoute(
                                  builder: (_) => FamilyScreen(
                                    familyId: group.id,
                                    familyName: group.name,
                                  ),
                                ),
                              )
                              .then((result) {
                                if (result == true) {
                                  _refreshFamilies();
                                }
                              });
                        },
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCreateFamilyButton() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _showCreateFamilyDialog,
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [AppTheme.accent, AppTheme.accentDark],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.accent.withOpacity(0.2),
                  blurRadius: 15,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.add, color: Colors.black87, size: 18),
                SizedBox(width: 8),
                Text(
                  'Create New Group',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'You can join another group via invitation link',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppTheme.mutedText,
          ),
        ),
      ],
    );
  }

  void _showCreateFamilyDialog() async {
    await showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.3),
      useSafeArea: false,
      builder: (context) {
        return const CreateFamilyDialog();
      },
    );

    _refreshFamilies();
  }

  void _onNavItemTapped(int index) {
    navigateFromBottomNav(
      context,
      targetIndex: index,
      currentIndex: _selectedNavIndex,
    );
  }
}

class _FamilyGroup {
  final String id;
  final String name;
  final int memberCount;
  final List<String> avatars;
  final int extraCount;

  const _FamilyGroup({
    required this.id,
    required this.name,
    required this.memberCount,
    required this.avatars,
    required this.extraCount,
  });
}

class _FamilyGroupCard extends StatelessWidget {
  final _FamilyGroup group;
  final VoidCallback? onTap;

  const _FamilyGroupCard({Key? key, required this.group, this.onTap})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _cardBorder),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF000000).withOpacity(0.05),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(group.name, style: AppTheme.familyNameStyle),
            const SizedBox(height: 4),
            Text(
              '${group.memberCount} group members',
              style: AppTheme.familyMemberCountStyle,
            ),
            const SizedBox(height: 16),
            _buildAvatars(),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatars() {
    final avatars = group.avatars;
    final children = <Widget>[];

    for (var i = 0; i < avatars.length; i++) {
      children.add(
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: ClipOval(
            child: Image.network(
              avatars[i],
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Container(color: Colors.grey.shade300),
            ),
          ),
        ),
      );
    }

    if (group.extraCount > 0) {
      children.add(
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppTheme.accent.withOpacity(0.2),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Center(
            child: Text(
              '+${group.extraCount}',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: AppTheme.accent,
              ),
            ),
          ),
        ),
      );
    }

    return Row(children: children);
  }
}
