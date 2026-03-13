import 'package:flutter/material.dart';

import '../assets/figma_assets.dart';
import 'family_screen.dart';

class FamilyMember {
  final String name;
  final String role;
  final String imageUrl;
  bool selected;

  FamilyMember({
    required this.name,
    required this.role,
    required this.imageUrl,
    this.selected = false,
  });
}

class SelectMembersScreen extends StatefulWidget {
  const SelectMembersScreen({
    Key? key,
    required this.initialSelectedNames,
  }) : super(key: key);

  final List<String> initialSelectedNames;

  @override
  State<SelectMembersScreen> createState() => _SelectMembersScreenState();
}

class _SelectMembersScreenState extends State<SelectMembersScreen> {
  static const _background = Color(0xFFFDFBF7);
  static const _card = Color(0xFFFAF6EB);
  static const _primaryColor = Color(0xFF0F172A);
  static const _labelColor = Color(0xFFB08F4C);

  final TextEditingController _searchController = TextEditingController();

  late final List<FamilyMember> _members;

  @override
  void initState() {
    super.initState();
    _members = [
      FamilyMember(
        name: 'Mom',
        role: 'Family Lead',
        imageUrl: FigmaAssets.familyImgMom,
        selected: widget.initialSelectedNames.contains('Mom'),
      ),
      FamilyMember(
        name: 'Dad',
        role: 'Home Admin',
        imageUrl: FigmaAssets.familyImgDad,
        selected: widget.initialSelectedNames.contains('Dad'),
      ),
      FamilyMember(
        name: 'Sister',
        role: 'Helper',
        imageUrl: FigmaAssets.familyImgUncleArthur,
        selected: widget.initialSelectedNames.contains('Sister'),
      ),
      FamilyMember(
        name: 'Brother',
        role: 'Helper',
        imageUrl: FigmaAssets.familyImgCousinSarah,
        selected: widget.initialSelectedNames.contains('Brother'),
      ),
    ];
  }

  List<FamilyMember> get _filteredMembers {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _members;
    return _members.where((m) {
      return m.name.toLowerCase().contains(query) || m.role.toLowerCase().contains(query);
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFDFBF7), Color(0xFFFFF7E1)],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: Container(
                  width: 430,
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Column(
                    children: [
                      _buildHeader(context),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 12),
                              _buildSearchField(),
                              const SizedBox(height: 18),
                              const Text(
                                'FAMILY CIRCLE',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                  color: _labelColor,
                                ),
                              ),
                              const SizedBox(height: 12),
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
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  Icons.arrow_back_ios_new,
                  size: 18,
                  color: _primaryColor,
                ),
              ),
            ),
          ),
          const Text(
            'Select Members',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _primaryColor,
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
                hintText: 'Find a family member...',
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
                  backgroundColor: const Color(0xFFDCE1E8),
                  backgroundImage: NetworkImage(member.imageUrl),
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
                    color: member.selected ? const Color(0xFFFDBA3C) : Colors.white,
                    border: Border.all(
                      color: const Color(0xFFE5E7EB),
                      width: 1.5,
                    ),
                  ),
                  child: member.selected
                      ? const Icon(
                          Icons.check,
                          size: 16,
                          color: Colors.white,
                        )
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
          MaterialPageRoute(builder: (_) => const FamilyScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFFD1D5DB),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(
              Icons.person_add_alt_1,
              size: 20,
              color: Color(0xFFB08F4C),
            ),
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
                final selectedNames = _members
                    .where((m) => m.selected)
                    .map((m) => m.name)
                    .toList();
                Navigator.of(context).pop(selectedNames);
              },
              child: const Center(
                child: Text(
                  'Edit Members to Task',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
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
