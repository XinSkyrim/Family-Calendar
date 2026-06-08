import 'package:cloud_firestore/cloud_firestore.dart';

class VoiceMemoSummary {
  const VoiceMemoSummary({
    required this.title,
    required this.summary,
    required this.detailedSummary,
    required this.keyPoints,
    required this.actionItems,
    required this.category,
  });

  final String title;
  final String summary;
  final String detailedSummary;
  final List<String> keyPoints;
  final List<String> actionItems;
  final String category;

  factory VoiceMemoSummary.fromMap(Map<String, dynamic> map) {
    return VoiceMemoSummary(
      title: (map['title'] as String?)?.trim().isNotEmpty == true
          ? (map['title'] as String).trim()
          : 'Untitled note',
      summary: (map['summary'] as String?)?.trim() ?? '',
      detailedSummary: (map['detailedSummary'] as String?)?.trim() ?? '',
      keyPoints: (map['keyPoints'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(),
      actionItems: (map['actionItems'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(),
      category: (map['category'] as String?)?.trim().isNotEmpty == true
          ? (map['category'] as String).trim()
          : 'Note',
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'title': title,
      'summary': summary,
      'detailedSummary': detailedSummary,
      'keyPoints': keyPoints,
      'actionItems': actionItems,
      'category': category,
    };
  }
}

class VoiceMemoRecord {
  const VoiceMemoRecord({
    required this.id,
    required this.userId,
    required this.rawInput,
    required this.inputMode,
    required this.summary,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String rawInput;
  final String inputMode;
  final VoiceMemoSummary summary;
  final DateTime createdAt;

  factory VoiceMemoRecord.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final createdAtValue = data['createdAt'];
    final createdAt = createdAtValue is Timestamp
        ? createdAtValue.toDate()
        : DateTime.now();

    return VoiceMemoRecord(
      id: doc.id,
      userId: (data['userId'] as String?) ?? '',
      rawInput: (data['rawInput'] as String?) ?? '',
      inputMode: (data['inputMode'] as String?) ?? 'text',
      summary: VoiceMemoSummary.fromMap(
        Map<String, dynamic>.from(data['summary'] as Map? ?? const {}),
      ),
      createdAt: createdAt,
    );
  }
}
