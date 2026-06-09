import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../themes/app_theme.dart';
import '../widgets/avatar_image.dart';
import 'select_members_screen.dart';

// Remote avatars (expires after ~7 days from Figma export)
const _avatar1 =
    'https://www.figma.com/api/mcp/asset/a38506d9-8e64-45b1-93ab-b1e18f83e69e';
const _avatar2 =
    'https://www.figma.com/api/mcp/asset/51ff2ec7-813c-4944-a4c3-916cf4aaaddc';
const _avatar3 =
    'https://www.figma.com/api/mcp/asset/f8b63427-429a-4a69-bd63-b25f74fe06db';
const _avatar4 =
    'https://www.figma.com/api/mcp/asset/0382f5d1-6d7c-4319-8d9d-087939698fc4';
const _avatar5 =
    'https://www.figma.com/api/mcp/asset/3320c70a-e5bf-4888-bc8f-13c8b5ce741b';
const _avatar6 =
    'https://www.figma.com/api/mcp/asset/ab68295f-48c2-43d1-a4af-c12be1ae41a2';
const _avatar7 =
    'https://www.figma.com/api/mcp/asset/deaeb81f-2d2e-46ad-ac6c-361c966cd6b2';
const _avatar8 =
    'https://www.figma.com/api/mcp/asset/73f6d153-7dc0-4b39-875e-459bb8f3d981';
const _avatar9 =
    'https://www.figma.com/api/mcp/asset/d245a2c3-c270-40af-92fa-7c4ae5594204';

const _headline = Color(0xFF0F172A);
const _accent = Color(0xFFFAC638);

// Updated to match memo_screen-style cleaner card look
const _cardBackground = Color(0xFFFFFCF6);
const _cardBorder = Color(0xFFF1E8D8);
const _subText = Color(0xFF64748B);

class FamilySelectionResult {
  const FamilySelectionResult({
    required this.familyId,
    required this.familyName,
    required this.members,
  });

  final String familyId;
  final String familyName;
  final List<SelectedTaskMember> members;
}

class FamilySelectionScreen extends StatefulWidget {
  const FamilySelectionScreen({Key? key, this.initialSelectedIds = const []})
    : super(key: key);

  final List<String> initialSelectedIds;

  @override
  State<FamilySelectionScreen> createState() => _FamilySelectionScreenState();
}

class _FamilySelectionScreenState extends State<FamilySelectionScreen> {
  late Future<List<_FamilyGroup>> _groupsFuture;
  final Set<String> _selectedFamilyIds = {};

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

  Future<Map<String, dynamic>?> _findUserByUid(String userId) async {
    final firestore = FirebaseFirestore.instance;

    final directDoc = await firestore.collection('users').doc(userId).get();
    if (directDoc.exists) {
      return directDoc.data();
    }

    final query = await firestore
        .collection('users')
        .where('uid', isEqualTo: userId)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      return query.docs.first.data();
    }

    return null;
  }

  Future<List<SelectedTaskMember>> _loadAllFamilyMembers(
    String familyId,
  ) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('families')
        .doc(familyId)
        .collection('members')
        .get();

    final List<SelectedTaskMember> members = [];

    for (final doc in snapshot.docs) {
      final memberData = doc.data();
      final userId = (memberData['uid'] ?? memberData['userId'] ?? doc.id)
          .toString()
          .trim();

      if (userId.isEmpty) continue;

      final userData = await _findUserByUid(userId);
      final name =
          (userData?['fullName'] ??
                  userData?['name'] ??
                  userData?['displayName'] ??
                  memberData['nickname'] ??
                  memberData['fullName'] ??
                  memberData['name'] ??
                  'Unknown Member')
              .toString()
              .trim();

      final avatarUrl =
          (userData?['photoURL'] ??
                  userData?['photoUrl'] ??
                  userData?['avatar'] ??
                  memberData['photoURL'] ??
                  memberData['photoUrl'] ??
                  memberData['avatar'] ??
                  '')
              .toString()
              .trim();

      members.add(
        SelectedTaskMember(
          id: userId,
          name: name.isEmpty ? 'Unknown Member' : name,
          avatarUrl: avatarUrl,
        ),
      );
    }

    final unique = <String, SelectedTaskMember>{};
    for (final member in members) {
      unique[member.id] = member;
    }
    return unique.values.toList();
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
          avatars.add(_fallbackAvatarByIndex(j));
        }

        if (avatars.length == 3) {
          break;
        }
      }

      if (avatars.isEmpty) {
        avatars.add(_avatar1);
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

  String _fallbackAvatarByIndex(int index) {
    const avatars = [
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
    return avatars[index % avatars.length];
  }

  Future<void> _handleSelectAll(_FamilyGroup group) async {
    try {
      final members = await _loadAllFamilyMembers(group.id);

      if (!mounted) return;

      setState(() {
        _selectedFamilyIds
          ..clear()
          ..add(group.id);
      });

      Navigator.of(context).pop(
        FamilySelectionResult(
          familyId: group.id,
          familyName: group.name,
          members: members,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to select all members: $e')),
      );
    }
  }

  Future<void> _handleOpenFamily(_FamilyGroup group) async {
    final result = await Navigator.of(context).push<List<SelectedTaskMember>>(
      MaterialPageRoute(
        builder: (_) => SelectMembersScreen(
          initialSelectedIds: widget.initialSelectedIds,
          familyId: group.id,
          familyName: group.name,
        ),
      ),
    );

    if (result == null || !mounted) return;

    setState(() {
      _selectedFamilyIds
        ..clear()
        ..add(group.id);
    });

    Navigator.of(context).pop(
      FamilySelectionResult(
        familyId: group.id,
        familyName: group.name,
        members: result,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).padding.top;

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
                        ],
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _buildTopBar(),
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

  Widget _buildTopBar() {
    return Container(
      height: 77,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      decoration: const BoxDecoration(
        color: AppTheme.headerBackground,
        boxShadow: [AppTheme.headerShadow],
      ),
      child: Row(
        children: [
          AppTheme.backButton(context),
          const Expanded(
            child: Center(
              child: Text(
                'Select Group',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _headline,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildList() {
    return FutureBuilder<List<_FamilyGroup>>(
      future: _groupsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _accent));
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
                    color: _headline,
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
                      color: _accent,
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
                Icon(Icons.groups_outlined, size: 44, color: Colors.grey),
                SizedBox(height: 12),
                Text(
                  'No group found',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _headline,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Create a new group or join one via invitation link',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _refreshFamilies,
          color: _accent,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: groups
                  .map(
                    (group) => Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: _FamilyGroupCard(
                        group: group,
                        selected: _selectedFamilyIds.contains(group.id),
                        onSelectAll: () => _handleSelectAll(group),
                        onTap: () => _handleOpenFamily(group),
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
  final bool selected;
  final VoidCallback? onSelectAll;
  final VoidCallback? onTap;

  const _FamilyGroupCard({
    Key? key,
    required this.group,
    this.selected = false,
    this.onSelectAll,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          color: _cardBackground,
          border: Border.all(
            color: selected ? _accent.withOpacity(0.45) : _cardBorder,
            width: 1.2,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _headline,
                    ),
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _accent.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Selected',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _headline,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${group.memberCount} group members',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _accent,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                ...List.generate(group.avatars.length, (index) {
                  return Align(
                    widthFactor: 0.75,
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.white,
                      child: CircleAvatar(
                        radius: 16,
                        backgroundImage: avatarImageProvider(
                          group.avatars[index],
                        ),
                      ),
                    ),
                  );
                }),
                if (group.extraCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      '+${group.extraCount}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _headline,
                      ),
                    ),
                  ),
                const Spacer(),
                GestureDetector(
                  onTap: onSelectAll,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Select all',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
