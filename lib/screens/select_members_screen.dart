import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../themes/app_theme.dart';
import '../widgets/avatar_image.dart';
import 'family_screen.dart';

class FamilyMember {
  final String id;
  final String name;
  final String role;
  final String imageUrl;
  bool selected;

  FamilyMember({
    required this.id,
    required this.name,
    required this.role,
    required this.imageUrl,
    this.selected = false,
  });
}

class SelectedTaskMember {
  const SelectedTaskMember({
    required this.id,
    required this.name,
    required this.avatarUrl,
  });

  final String id;
  final String name;
  final String avatarUrl;
}

class SelectMembersScreen extends StatefulWidget {
  const SelectMembersScreen({
    Key? key,
    required this.initialSelectedIds,
    required this.familyId,
    required this.familyName,
  }) : super(key: key);

  final List<String> initialSelectedIds;
  final String familyId;
  final String familyName;

  @override
  State<SelectMembersScreen> createState() => _SelectMembersScreenState();
}

class _SelectMembersScreenState extends State<SelectMembersScreen> {
  static const _background = AppTheme.pageBackground;
  static const _card = Color(0xFFFFF9EC);
  static const _primaryColor = Color(0xFF0F172A);
  static const _labelColor = Color(0xFFB08F4C);

  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  List<FamilyMember> _members = [];

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  List<FamilyMember> get _filteredMembers {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _members;
    return _members.where((m) {
      return m.name.toLowerCase().contains(query) ||
          m.role.toLowerCase().contains(query);
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  Future<void> _loadMembers() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('families')
          .doc(widget.familyId)
          .collection('members')
          .get();

      final members = <FamilyMember>[];

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

        final role =
            (memberData['role'] ?? memberData['familyRole'] ?? 'member')
                .toString()
                .trim();

        final photoUrl =
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
          FamilyMember(
            id: userId,
            name: name.isEmpty ? 'Unknown Member' : name,
            role: role.isEmpty ? 'member' : role,
            imageUrl: photoUrl,
            selected: widget.initialSelectedIds.contains(userId),
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _members = members;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _members = [];
        _isLoading = false;
      });
    }
  }

  List<SelectedTaskMember> _buildSelectedMembersResult() {
    return _members
        .where((m) => m.selected)
        .map(
          (m) =>
              SelectedTaskMember(id: m.id, name: m.name, avatarUrl: m.imageUrl),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: _background,
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
            child: Stack(
              children: [
                Center(
                  child: Container(
                    width: 430,
                    constraints: const BoxConstraints(maxWidth: 430),
                    color: _background,
                    child: Column(
                      children: [
                        _buildHeader(context),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 12),
                                _buildSearchField(),
                                const SizedBox(height: 18),
                                const Text(
                                  'GROUP CIRCLE',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2,
                                    color: _labelColor,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (_isLoading)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 24),
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        color: Color(0xFFE2B736),
                                      ),
                                    ),
                                  )
                                else
                                  ..._buildMemberList(),
                                const SizedBox(height: 16),
                                _buildInviteNewMemberButton(),
                                const SizedBox(height: 90),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildSaveButton(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      decoration: BoxDecoration(
        color: AppTheme.headerBackground,
        boxShadow: const [AppTheme.headerShadow],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          AppTheme.backButton(context),
          const Text(
            'Select Members',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.headline,
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.search, color: Color(0xFFB08F4C)),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Find a group member...',
                hintStyle: TextStyle(
                  color: Color(0xFFB08F4C),
                  fontWeight: FontWeight.w600,
                ),
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildMemberList() {
    return _filteredMembers.map((member) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            setState(() {
              member.selected = !member.selected;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: const Color(0xFFF4DFC0),
                  backgroundImage: avatarImageProvider(member.imageUrl),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _primaryColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        member.role,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: member.selected
                        ? const Color(0xFFFDBA3C)
                        : Colors.white,
                    border: Border.all(
                      color: const Color(0xFFE5E7EB),
                      width: 1.5,
                    ),
                  ),
                  child: member.selected
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildInviteNewMemberButton() {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FamilyScreen(
              familyId: widget.familyId,
              familyName: widget.familyName,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFD1D5DB), width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.person_add_alt_1, size: 20, color: Color(0xFFB08F4C)),
            SizedBox(width: 8),
            Text(
              'Invite New Member',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFFB08F4C),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveButton(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.transparent],
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFDBA3C), Color(0xFFFFA800)],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFEA9E22).withOpacity(0.35),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () {
                Navigator.of(context).pop(_buildSelectedMembersResult());
              },
              child: const Center(
                child: Text(
                  'Add Members to Task',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
