import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'voice_memo_models.dart';

class VoiceMemoDetailScreen extends StatelessWidget {
  const VoiceMemoDetailScreen({super.key, required this.memo});

  final VoiceMemoRecord memo;

  static const bgColor = Color(0xFFFDFBF7);
  static const primaryColor = Color(0xFF0F172A);
  static const accentColor = Color(0xFFE2B736);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        surfaceTintColor: bgColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: primaryColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Note details',
          style: TextStyle(
            color: primaryColor,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MetaCard(memo: memo),
              const SizedBox(height: 20),
              _SectionCard(
                title: 'AI Summary',
                child: Text(
                  memo.summary.detailedSummary.isNotEmpty
                      ? memo.summary.detailedSummary
                      : memo.summary.summary,
                  style: const TextStyle(
                    color: Color(0xFF334155),
                    fontSize: 15,
                    height: 1.6,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (memo.summary.keyPoints.isNotEmpty)
                _SectionCard(
                  title: 'Key Points',
                  child: Column(
                    children: memo.summary.keyPoints
                        .map((item) => _BulletRow(text: item))
                        .toList(),
                  ),
                ),
              if (memo.summary.keyPoints.isNotEmpty) const SizedBox(height: 16),
              if (memo.summary.actionItems.isNotEmpty)
                _SectionCard(
                  title: 'Action Items',
                  child: Column(
                    children: memo.summary.actionItems
                        .map((item) => _BulletRow(text: item))
                        .toList(),
                  ),
                ),
              if (memo.summary.actionItems.isNotEmpty) const SizedBox(height: 16),
              _SectionCard(
                title: 'Original Input',
                child: Text(
                  memo.rawInput,
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaCard extends StatelessWidget {
  const _MetaCard({required this.memo});

  final VoiceMemoRecord memo;

  @override
  Widget build(BuildContext context) {
    final createdAtText = DateFormat('d/M/yyyy  HH:mm').format(memo.createdAt);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0x22E2B736),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              memo.summary.category.toUpperCase(),
              style: const TextStyle(
                color: VoiceMemoDetailScreen.accentColor,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            memo.summary.title,
            style: const TextStyle(
              color: VoiceMemoDetailScreen.primaryColor,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            memo.summary.summary,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 15,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetaPill(icon: Icons.schedule, label: createdAtText),
              _MetaPill(
                icon: memo.inputMode == 'voice' ? Icons.mic : Icons.keyboard,
                label: memo.inputMode == 'voice' ? 'Voice input' : 'Text input',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF64748B)),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: VoiceMemoDetailScreen.primaryColor,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _BulletRow extends StatelessWidget {
  const _BulletRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 7),
            decoration: const BoxDecoration(
              color: VoiceMemoDetailScreen.accentColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF334155),
                fontSize: 14,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
