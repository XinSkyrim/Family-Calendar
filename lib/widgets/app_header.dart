import 'dart:ui';

import 'package:flutter/material.dart';
import '../themes/app_theme.dart';

class AppHeader extends StatelessWidget {
  final String? title;
  final Widget? leading;
  final Widget? trailing;
  final double height;
  final bool useBlur;

  const AppHeader({
    super.key,
    this.title,
    this.leading,
    this.trailing,
    this.height = AppTheme.headerHeight,
    this.useBlur = false,
  });

  @override
  Widget build(BuildContext context) {
    final child = Container(
      height: height,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.horizontalPadding,
        vertical: AppTheme.verticalPadding,
      ),
      decoration: BoxDecoration(
        color: useBlur
            ? Colors.white.withValues(alpha: 0.8)
            : AppTheme.headerBackground,
        border: useBlur ? Border.all(color: AppTheme.divider) : null,
        boxShadow: useBlur
            ? null
            : const [
          AppTheme.headerShadow,
        ],
      ),
      child: Row(
        children: [
          ?leading,
          if (title != null)
            Expanded(
              child: Center(
                child: Text(
                  title!,
                  style: AppTheme.headlineStyle,
                ),
              ),
            ),
          ?trailing,
        ],
      ),
    );

    if (!useBlur) {
      return child;
    }

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: AppTheme.blurSigma,
          sigmaY: AppTheme.blurSigma,
        ),
        child: child,
      ),
    );
  }
}