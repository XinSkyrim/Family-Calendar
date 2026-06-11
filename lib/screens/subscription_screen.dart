import 'package:flutter/material.dart';
import '../themes/app_theme.dart';

class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.pageBackground,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppTheme.horizontalPadding),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 390),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(height: 36),
                          _buildHeroCard(),
                          const SizedBox(height: 24),
                          _buildTitle(),
                          const SizedBox(height: 18),
                          const Text(
                            'The ultimate space for shared memories,\nsmart planning, and safe keeping.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w400,
                              height: 1.55,
                              color: Color(0xFF65645E),
                            ),
                          ),
                          const SizedBox(height: 24),
                          _buildPriceCard(),
                          const SizedBox(height: 24),
                          _buildFeatureItem(
                            background: const Color(0xFFDFD5F4),
                            icon: Icons.people,
                            iconColor: const Color(0xFF8F6AE8),
                            title: 'Unlimited Group Members',
                            subtitle: 'Invite everyone from kids to grandparents.',
                          ),
                          const SizedBox(height: 16),
                          _buildFeatureItem(
                            background: const Color(0xFFF3C745),
                            icon: Icons.auto_awesome,
                            iconColor: const Color(0xFFB99312),
                            title: 'AI Smart Memo Summaries',
                            subtitle: 'Stay updated with weekly family highlights.',
                          ),
                          const SizedBox(height: 16),
                          _buildFeatureItem(
                            background: const Color(0xFFEBE8DE),
                            icon: Icons.shield,
                            iconColor: const Color(0xFF79716B),
                            title: 'Ad-free Experience',
                            subtitle: 'Pure family focus without distractions.',
                          ),
                          const SizedBox(height: 32),
                          _buildActionButton(),
                          const SizedBox(height: 24),
                          InkWell(
                            onTap: () {},
                            child: Container(
                              padding: const EdgeInsets.only(bottom: 6),
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: Color(0xFFDFD5F4),
                                    width: 4,
                                  ),
                                ),
                              ),
                              child: const Text(
                                'Restore Purchase',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF68607B),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'TERMS OF SERVICE • PRIVACY POLICY',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                              color: Color.fromRGBO(101, 100, 94, 0.6),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      decoration: BoxDecoration(
        color: AppTheme.headerBackground,
        boxShadow: [AppTheme.headerShadow],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          AppTheme.backButton(context),
          const Text(
            'Subscription',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildHeroCard() {
    return SizedBox(
      width: 240,
      height: 240,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned(
            right: -20,
            top: -20,
            child: Container(
              width: 62,
              height: 62,
              decoration: const BoxDecoration(
                color: Color(0xFFDBC790),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(
                  Icons.wb_sunny,
                  size: 34,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          Positioned(
            left: -28,
            bottom: -20,
            child: Transform.rotate(
              angle: 12 * 3.14159 / 180,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFBBB9B2)),
                  borderRadius: BorderRadius.circular(36),
                  boxShadow: const [
                    BoxShadow(
                      color: Color.fromRGBO(56, 56, 51, 0.04),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                    BoxShadow(
                      color: Color.fromRGBO(124, 97, 0, 0.06),
                      blurRadius: 24,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.favorite,
                  size: 34,
                  color: Color(0xFFBE2D06),
                ),
              ),
            ),
          ),
          Transform.rotate(
            angle: -3 * 3.14159 / 180,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(56),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(56),
                child: Image.asset(
                  'assets/images/family_memo_logo.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitle() {
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w800,
          height: 1.25,
          letterSpacing: -0.9,
          color: AppTheme.headline,
        ),
        children: [
          const TextSpan(text: 'Unlock Your '),
          TextSpan(
            text: 'Family',
            style: const TextStyle(color: AppTheme.accent),
          ),
          const TextSpan(text: '\n'),
          TextSpan(
            text: 'Notes',
            style: const TextStyle(color: AppTheme.accent),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceCard() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(34),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Color(0xFFFCF9F1)],
            ),
            border: Border.all(
              color: const Color.fromRGBO(124, 97, 0, 0.2),
              width: 2,
            ),
            borderRadius: BorderRadius.circular(48),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(56, 56, 51, 0.04),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
              BoxShadow(
                color: Color.fromRGBO(124, 97, 0, 0.06),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Annual Plan',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF383833),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Billed annually',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF65645E),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  RichText(
                    text: const TextSpan(
                      children: [
                        TextSpan(
                          text: '\$0.99',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF383833),
                          ),
                        ),
                        TextSpan(
                          text: '/year',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: Color(0xFF65645E),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '\$0.09/month',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF7C6100),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Positioned(
          right: 24,
          top: -12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF7C6100),
              borderRadius: BorderRadius.circular(9999),
              boxShadow: const [
                BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, 0.1),
                  blurRadius: 15,
                  offset: Offset(0, 10),
                ),
                BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, 0.1),
                  blurRadius: 6,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: const Text(
              'SAVE 30%',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureItem({
    required Color background,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: const Color(0xFFBBB9B2)),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(56, 56, 51, 0.04),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
              BoxShadow(
                color: Color.fromRGBO(124, 97, 0, 0.06),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Center(
            child: Icon(
              icon,
              color: iconColor,
              size: 20,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF383833),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    height: 1.45,
                    color: Color(0xFF65645E),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton() {
    return SizedBox(
      width: double.infinity,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFF3C745),
          borderRadius: BorderRadius.circular(48),
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(124, 97, 0, 0.15),
              blurRadius: 6,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: const Center(
          child: Text(
            'Start 7-Day Free Trial',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF3D2E00),
            ),
          ),
        ),
      ),
    );
  }
}
