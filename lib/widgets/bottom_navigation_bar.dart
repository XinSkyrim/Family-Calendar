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
    Key? key,
    required this.currentIndex,
    required this.onItemTapped,
    this.navItemKeys,
  }) : super(key: key);

  static const List<_NavItem> _navItems = [
    _NavItem(icon: Icons.chat_bubble_outline, label: 'Memo'),
    _NavItem(icon: Icons.people, label: 'Family'),
    _NavItem(icon: Icons.calendar_today, label: 'Today'),
    _NavItem(icon: Icons.settings, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final topPadding = bottomInset > 0 ? 6.0 : 8.0;
    final bottomPadding = bottomInset > 0 ? bottomInset : 4.0;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: AppTheme.blurSigma,
          sigmaY: AppTheme.blurSigma,
        ),
        child: Container(
          padding: EdgeInsets.fromLTRB(25, topPadding, 25, bottomPadding),
          decoration: BoxDecoration(
            color: Colors.white,
            border: const Border(top: BorderSide(color: AppTheme.divider)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(
              _navItems.length,
              (index) => _buildNavItem(index),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index) {
    final item = _navItems[index];
    final isSelected = index == currentIndex;

    return Material(
      key: navItemKeys?[index],
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onItemTapped(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.accent.withOpacity(0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: isSelected ? 1.08 : 1,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: Icon(
                  item.icon,
                  size: 24,
                  color: isSelected ? AppTheme.accent : AppTheme.inactiveIcon,
                ),
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
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;

  const _NavItem({required this.icon, required this.label});
}
