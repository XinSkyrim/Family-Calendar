import 'package:flutter/material.dart';

class OnboardingOverlayData {
  const OnboardingOverlayData({
    required this.title,
    required this.description,
    required this.stepNumber,
    required this.totalSteps,
    required this.onNext,
    required this.onSkip,
    this.nextLabel = 'Next',
    this.targetId,
    this.requireTargetTap = false,
    this.targetKey,
  });

  final String title;
  final String description;
  final int stepNumber;
  final int totalSteps;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final String nextLabel;
  final String? targetId;
  final bool requireTargetTap;
  final GlobalKey? targetKey;

  OnboardingOverlayData copyWith({
    String? title,
    String? description,
    int? stepNumber,
    int? totalSteps,
    VoidCallback? onNext,
    VoidCallback? onSkip,
    String? nextLabel,
    String? targetId,
    bool? requireTargetTap,
    GlobalKey? targetKey,
  }) {
    return OnboardingOverlayData(
      title: title ?? this.title,
      description: description ?? this.description,
      stepNumber: stepNumber ?? this.stepNumber,
      totalSteps: totalSteps ?? this.totalSteps,
      onNext: onNext ?? this.onNext,
      onSkip: onSkip ?? this.onSkip,
      nextLabel: nextLabel ?? this.nextLabel,
      targetId: targetId ?? this.targetId,
      requireTargetTap: requireTargetTap ?? this.requireTargetTap,
      targetKey: targetKey ?? this.targetKey,
    );
  }
}

class OnboardingOverlay extends StatelessWidget {
  const OnboardingOverlay({super.key, required this.data});

  final OnboardingOverlayData data;

  @override
  Widget build(BuildContext context) {
    final targetRect = _resolveTargetRect(context);

    return Positioned.fill(
      child: Stack(
        children: [
          IgnorePointer(
            ignoring: true,
            child: CustomPaint(
              painter: _OnboardingMaskPainter(targetRect: targetRect),
              size: Size.infinite,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _buildCoachBubble(),
            ),
          ),
        ],
      ),
    );
  }

  Rect? _resolveTargetRect(BuildContext context) {
    final key = data.targetKey;
    final targetContext = key?.currentContext;
    if (targetContext == null) {
      return null;
    }

    final renderObject = targetContext.findRenderObject();
    final overlayRender = context.findRenderObject();
    if (renderObject is! RenderBox ||
        overlayRender is! RenderBox ||
        !renderObject.hasSize) {
      return null;
    }

    final topLeft = renderObject.localToGlobal(
      Offset.zero,
      ancestor: overlayRender,
    );
    return topLeft & renderObject.size;
  }

  Widget _buildCoachBubble() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Step ${data.stepNumber}/${data.totalSteps}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  TextButton(onPressed: data.onSkip, child: const Text('Skip')),
                ],
              ),
              Text(
                data.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                data.description,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF475569),
                  height: 1.4,
                ),
              ),
              if (data.requireTargetTap) ...[
                const SizedBox(height: 8),
                const Text(
                  'Please tap the highlighted control to continue.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF9A6B00),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: data.onNext,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE2B736),
                      foregroundColor: const Color(0xFF0F172A),
                    ),
                    child: Text(data.nextLabel),
                  ),
                ),
              ],
            ],
          ),
        ),
        Positioned(
          left: 36,
          bottom: -10,
          child: Transform.rotate(
            angle: 0.785398,
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OnboardingMaskPainter extends CustomPainter {
  const _OnboardingMaskPainter({required this.targetRect});

  final Rect? targetRect;

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Path()..addRect(Offset.zero & size);

    if (targetRect != null) {
      final holeRect = RRect.fromRectAndRadius(
        targetRect!.inflate(8),
        const Radius.circular(16),
      );
      overlay.addRRect(holeRect);
      overlay.fillType = PathFillType.evenOdd;
    }

    canvas.drawPath(
      overlay,
      Paint()..color = Colors.black.withOpacity(0.45),
    );

    if (targetRect != null) {
      final highlight = RRect.fromRectAndRadius(
        targetRect!.inflate(8),
        const Radius.circular(16),
      );
      canvas.drawRRect(
        highlight,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = const Color(0xFFE2B736),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OnboardingMaskPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect;
  }
}
