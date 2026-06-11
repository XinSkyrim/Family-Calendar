import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/default_avatar.dart';

class UserProfile {
  final String fullName;
  final String photoUrl;

  const UserProfile({this.fullName = 'User', this.photoUrl = ''});

  UserProfile copyWith({String? fullName, String? photoUrl}) {
    return UserProfile(
      fullName: fullName ?? this.fullName,
      photoUrl: photoUrl ?? this.photoUrl,
    );
  }
}

class UserProfileService {
  static const String _prefsFullName = 'cached_user_full_name';
  static const String _prefsPhotoUrl = 'cached_user_photo_url';

  static final ValueNotifier<UserProfile> profile = ValueNotifier(
    const UserProfile(),
  );

  static Future<void> init() async {
    await _loadFromPreferences();
    await refreshFromFirestore();
  }

  static Future<void> _loadFromPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final fullName = prefs.getString(_prefsFullName) ?? 'User';
    final photoUrl = _normalizedPhotoUrl(prefs.getString(_prefsPhotoUrl));

    profile.value = UserProfile(fullName: fullName, photoUrl: photoUrl);
  }

  static Future<void> refreshFromFirestore() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return;
    }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (!userDoc.exists) {
        return;
      }

      final data = userDoc.data();
      if (data == null) {
        return;
      }

      final fullName = (data['fullName'] ?? data['username'] ?? 'User')
          .toString()
          .trim();
      final photoUrl = _normalizedPhotoUrl(data['photoURL']);

      final updated = UserProfile(
        fullName: fullName.isNotEmpty ? fullName : 'User',
        photoUrl: photoUrl,
      );

      if (updated.fullName != profile.value.fullName ||
          updated.photoUrl != profile.value.photoUrl) {
        profile.value = updated;
        await _saveToPreferences(updated);
      }
    } catch (_) {
      return;
    }
  }

  static Future<void> update({String? fullName, String? photoUrl}) async {
    final updated = profile.value.copyWith(
      fullName: fullName,
      photoUrl: photoUrl == null ? null : _normalizedPhotoUrl(photoUrl),
    );
    profile.value = updated;
    await _saveToPreferences(updated);
  }

  static String _normalizedPhotoUrl(Object? rawPhotoUrl) {
    final photoUrl = (rawPhotoUrl ?? '').toString().trim();
    if (photoUrl.isEmpty) {
      return DefaultAvatar.path;
    }
    return photoUrl;
  }

  static Future<void> _saveToPreferences(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsFullName, profile.fullName);
    await prefs.setString(_prefsPhotoUrl, profile.photoUrl);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsFullName);
    await prefs.remove(_prefsPhotoUrl);
    profile.value = const UserProfile();
  }
}
