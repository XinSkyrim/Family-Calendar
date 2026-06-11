import 'package:flutter/material.dart';
import '../assets/figma_assets.dart';

class InvitationScreen extends StatefulWidget {
  const InvitationScreen({super.key});

  @override
  State<InvitationScreen> createState() => _InvitationScreenState();
}

class _InvitationScreenState extends State<InvitationScreen> {
  static const bgColor = Color(0xFFFDFAF3);
  static const primaryColor = Color(0xFF4A4023);
  static const accentColor = Color(0xFFE2B736);

  final TextEditingController _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFEFC), Color(0xFFFBF7E8)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildTopAppBar(context),
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        const SizedBox(height: 24),
                        _buildDecorativeIcon(),
                        const SizedBox(height: 32),
                        _buildHeaderText(),
                        const SizedBox(height: 40),
                        _buildEmailInput(),
                        const SizedBox(height: 40),
                        _buildMembersSection(),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ),
              _buildBottomActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              child: const Icon(Icons.close, size: 14, color: Colors.black54),
            ),
          ),
          const Expanded(
            child: Center(
              child: Text(
                'Join Our Cottage',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: primaryColor,
                  letterSpacing: -0.45,
                ),
              ),
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildDecorativeIcon() {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      child: const Center(
        child: Icon(Icons.home, size: 32, color: primaryColor),
      ),
    );
  }

  Widget _buildHeaderText() {
    return Column(
      children: [
        const Text(
          'Grow the Family',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: primaryColor,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Shared moments, shared schedules, all in one warm place.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: primaryColor.withValues(alpha: 0.7),
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildEmailInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Family Member',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: primaryColor,
            ),
          ),
        ),
        Container(
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFFF3F0E8),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Icon(Icons.mail_outline, size: 20, color: Colors.black54),
              ),
              Expanded(
                child: TextField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    hintText: "Enter family member's email",
                    hintStyle: TextStyle(
                      color: primaryColor.withValues(alpha: 0.4),
                      fontSize: 16,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: TextStyle(
                    color: primaryColor,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMembersSection() {
    return Column(
      children: [
        Text(
          'ALREADY IN THE COTTAGE',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: primaryColor.withValues(alpha: 0.6),
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 16),
        _buildAvatarStack(),
      ],
    );
  }

  Widget _buildAvatarStack() {
    return SizedBox(
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Avatar 1
          Positioned(
            left: 0,
            child: _buildAvatar('', 0),
          ),
          // Avatar 2
          Positioned(
            left: 36,
            child: _buildAvatar('', 1),
          ),
          // Avatar 3
          Positioned(
            left: 72,
            child: _buildAvatar('', 2),
          ),
          // +2 Badge
          Positioned(
            left: 108,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accentColor,
                shape: BoxShape.circle,
                border: Border.all(color: bgColor, width: 4),
              ),
              child: Center(
                child: Text(
                  '+2',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: primaryColor,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(String imageUrl, int index) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: bgColor, width: 4),
        color: accentColor.withValues(alpha: 0.2),
      ),
      child: const Center(
        child: Icon(Icons.person, size: 24, color: Colors.grey),
      ),
    );
  }

  Widget _buildBottomActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invitation sent!')),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                elevation: 0,
              ),
              child: Text(
                'Send Invitation',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: primaryColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.copy, size: 14, color: Colors.black54),
                const SizedBox(width: 8),
                Text(
                  'Copy Invite Link',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: primaryColor.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
