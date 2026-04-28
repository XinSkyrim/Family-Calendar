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
}

class OnboardingOverlay extends StatelessWidget {
  const OnboardingOverlay({super.key, required this.data});

  final OnboardingOverlayData data;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          IgnorePointer(
            ignoring: true,
            child: Container(color: Colors.black.withOpacity(0.18)),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
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
                        TextButton(
                          onPressed: data.onSkip,
                          child: const Text('Skip'),
                        ),
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
            ),
          ),
        ],
      ),
    );
  }
}
