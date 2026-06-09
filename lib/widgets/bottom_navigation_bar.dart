import 'dart:ui';

import 'package:flutter/material.dart';

import '../themes/app_theme.dart';

/// 底部导航栏组件
/// 统一的4个导航项：Memo, Family, Today, Settings
class AppBottomNavigationBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onItemTapped;
  final Map<int, GlobalKey>? navItemKeys;

  const AppBottomNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onItemTapped,
    this.navItemKeys,
  });

  static const List<_NavItem> _navItems = [
    _NavItem(icon: Icons.chat_bubble_outline, label: 'Notes'),
    _NavItem(icon: Icons.calendar_today, label: 'Calendar'),
    _NavItem(icon: Icons.people, label: 'Group'),
    _NavItem(icon: Icons.settings, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: AppTheme.blurSigma,
          sigmaY: AppTheme.blurSigma,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.8),
            border: const Border(
              top: BorderSide(color: AppTheme.divider),
            ),
          ),
          child: SafeArea(
            top: false,
            minimum: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(25, 4, 25, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(
                  _navItems.length,
                  (index) => _buildNavItem(index),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index) {
    final item = _navItems[index];
    final isSelected = index == currentIndex;

    return GestureDetector(
      key: navItemKeys?[index],
      behavior: HitTestBehavior.translucent,
      onTap: () => onItemTapped(index),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 6,
          horizontal: 8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              item.icon,
              size: 20,
              color: isSelected ? AppTheme.accent : AppTheme.inactiveIcon,
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              style: isSelected
                  ? AppTheme.navLabelSelectedStyle
                  : AppTheme.navLabelStyle,
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;

  const _NavItem({
    required this.icon,
    required this.label,
  });
}
