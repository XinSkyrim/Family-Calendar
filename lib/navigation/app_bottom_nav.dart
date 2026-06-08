import 'package:flutter/material.dart';

import '../screens/calendar_screen.dart';
import '../screens/memo_screen.dart';
import '../screens/select_family_screen.dart';
import '../screens/settings_screen.dart';

Route<void> buildBottomNavRoute(Widget page) {
  return PageRouteBuilder<void>(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: const Duration(milliseconds: 180),
    reverseTransitionDuration: const Duration(milliseconds: 140),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final fadeAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );

      return FadeTransition(opacity: fadeAnimation, child: child);
    },
  );
}

void navigateFromBottomNav(
  BuildContext context, {
  required int targetIndex,
  required int currentIndex,
}) {
  if (targetIndex == currentIndex) {
    return;
  }

  final Widget destination;
  switch (targetIndex) {
    case 0:
      destination = const MemoScreen();
      break;
    case 1:
      destination = const CalendarScreen();
      break;
    case 2:
      destination = const SelectFamilyScreen();
      break;
    case 3:
      destination = const SettingsScreen();
      break;
    default:
      return;
  }

  Navigator.of(context).pushReplacement(buildBottomNavRoute(destination));
}
