import 'package:flutter/material.dart';

class FeatureTourStep {
  const FeatureTourStep({
    required this.id,
    required this.targetKey,
    required this.title,
    required this.description,
    this.preferredPlacement = TourBubblePlacement.auto,
    this.highlightPadding = 10,
    this.highlightRadius = 20,
  });

  final String id;
  final GlobalKey targetKey;
  final String title;
  final String description;
  final TourBubblePlacement preferredPlacement;
  final double highlightPadding;
  final double highlightRadius;
}

enum TourBubblePlacement { auto, above, below }

class FeatureTourOverlay extends StatelessWidget {
  const FeatureTourOverlay({
    super.key,
    required this.step,
    required this.currentIndex,
    required this.totalSteps,
    required this.onPrevious,
    required this.onNext,
    required this.onSkip,
    required this.onComplete,
    this.isBusy = false,
  });

  final FeatureTourStep step;
  final int currentIndex;
  final int totalSteps;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onSkip;
  final VoidCallback? onComplete;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final targetRect = _resolveTargetRect(step.targetKey);
    if (targetRect == null) {
      return const SizedBox.shrink();
    }

    final screenSize = MediaQuery.of(context).size;
    final bubbleWidth = (screenSize.width - 40).clamp(260.0, 420.0).toDouble();
    const bubbleHeightEstimate = 180.0;

    final placement = _resolvePlacement(
      step.preferredPlacement,
      targetRect,
      screenSize,
      bubbleHeightEstimate,
    );

    final bubbleTop = _bubbleTop(
      placement: placement,
      targetRect: targetRect,
      screenHeight: screenSize.height,
      bubbleHeightEstimate: bubbleHeightEstimate,
    );

    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _TourMaskPainter(
              targetRect: targetRect,
              highlightPadding: step.highlightPadding,
              highlightRadius: step.highlightRadius,
            ),
          ),
        ),
        Positioned.fromRect(
          rect: targetRect.inflate(step.highlightPadding),
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(step.highlightRadius),
                border: Border.all(color: const Color(0xFFFDE047), width: 2.6),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66FDE047),
                    blurRadius: 18,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: (screenSize.width - bubbleWidth) / 2,
          width: bubbleWidth,
          top: bubbleTop,
          child: _TourBubble(
            title: step.title,
            description: step.description,
            currentIndex: currentIndex,
            totalSteps: totalSteps,
            isBusy: isBusy,
            onPrevious: onPrevious,
            onNext: onNext,
            onSkip: onSkip,
            onComplete: onComplete,
          ),
        ),
      ],
    );
  }

  Rect? _resolveTargetRect(GlobalKey targetKey) {
    final targetContext = targetKey.currentContext;
    if (targetContext == null) {
      return null;
    }

    final renderObject = targetContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) {
      return null;
    }

    final topLeft = renderObject.localToGlobal(Offset.zero);
    return Rect.fromLTWH(
      topLeft.dx,
      topLeft.dy,
      renderObject.size.width,
      renderObject.size.height,
    );
  }

  TourBubblePlacement _resolvePlacement(
    TourBubblePlacement preferred,
    Rect targetRect,
    Size screenSize,
    double bubbleHeightEstimate,
  ) {
    if (preferred == TourBubblePlacement.above ||
        preferred == TourBubblePlacement.below) {
      return preferred;
    }

    final canPlaceBelow =
        targetRect.bottom + 16 + bubbleHeightEstimate <= screenSize.height - 24;

    return canPlaceBelow ? TourBubblePlacement.below : TourBubblePlacement.above;
  }

  double _bubbleTop({
    required TourBubblePlacement placement,
    required Rect targetRect,
    required double screenHeight,
    required double bubbleHeightEstimate,
  }) {
    if (placement == TourBubblePlacement.above) {
      return (targetRect.top - bubbleHeightEstimate - 16)
          .clamp(24.0, screenHeight - bubbleHeightEstimate - 24)
          .toDouble();
    }

    return (targetRect.bottom + 16)
        .clamp(24.0, screenHeight - bubbleHeightEstimate - 24)
        .toDouble();
  }
}

class _TourBubble extends StatelessWidget {
  const _TourBubble({
    required this.title,
    required this.description,
    required this.currentIndex,
    required this.totalSteps,
    required this.isBusy,
    required this.onPrevious,
    required this.onNext,
    required this.onSkip,
    required this.onComplete,
  });

  final String title;
  final String description;
  final int currentIndex;
  final int totalSteps;
  final bool isBusy;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onSkip;
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Step ${currentIndex + 1} of $totalSteps',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: isBusy ? null : onPrevious,
                  child: const Text('Previous'),
                ),
                OutlinedButton(
                  onPressed: isBusy ? null : onNext,
                  child: const Text('Next'),
                ),
                TextButton(
                  onPressed: isBusy ? null : onSkip,
                  child: const Text('Skip'),
                ),
                ElevatedButton(
                  onPressed: isBusy ? null : onComplete,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE2B736),
                    foregroundColor: const Color(0xFF0F172A),
                  ),
                  child: const Text('Complete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TourMaskPainter extends CustomPainter {
  const _TourMaskPainter({
    required this.targetRect,
    required this.highlightPadding,
    required this.highlightRadius,
  });

  final Rect targetRect;
  final double highlightPadding;
  final double highlightRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPath = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(
        RRect.fromRectAndRadius(
          targetRect.inflate(highlightPadding),
          Radius.circular(highlightRadius),
        ),
      );

    canvas.drawPath(
      overlayPath,
      Paint()..color = const Color(0xB3000000),
    );
  }

  @override
  bool shouldRepaint(covariant _TourMaskPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect ||
        oldDelegate.highlightPadding != highlightPadding ||
        oldDelegate.highlightRadius != highlightRadius;
  }
}
