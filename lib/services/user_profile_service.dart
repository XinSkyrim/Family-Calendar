import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  static final ValueNotifier<UserProfile> profile =
      ValueNotifier(const UserProfile());

  static Future<void> init() async {
    await _loadFromPreferences();
    await _loadFromAuthIfEmpty();
    await _loadFromFirestoreIfNeeded();
  }

  static Future<void> _loadFromPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final fullName = prefs.getString(_prefsFullName) ?? 'User';
    final photoUrl = prefs.getString(_prefsPhotoUrl) ?? '';

    profile.value = UserProfile(fullName: fullName, photoUrl: photoUrl);
  }

  static Future<void> _loadFromAuthIfEmpty() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return;
    }

    final currentValue = profile.value;
    var updated = currentValue;

    final authFullName = currentUser.displayName?.trim() ?? '';
    final authPhotoUrl = currentUser.photoURL?.trim() ?? '';

    if (currentValue.fullName == 'User' && authFullName.isNotEmpty) {
      updated = updated.copyWith(fullName: authFullName);
    }

    if (currentValue.photoUrl.isEmpty && authPhotoUrl.isNotEmpty) {
      updated = updated.copyWith(photoUrl: authPhotoUrl);
    }

    if (updated != currentValue) {
      profile.value = updated;
      await _saveToPreferences(updated);
    }
  }

  static Future<void> _loadFromFirestoreIfNeeded() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return;
    }

    final currentValue = profile.value;
    if (currentValue.photoUrl.isNotEmpty && currentValue.fullName != 'User') {
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
      final photoUrl = (data['photoURL'] ?? '').toString().trim();

      final updated = currentValue.copyWith(
        fullName: fullName.isNotEmpty ? fullName : currentValue.fullName,
        photoUrl: photoUrl.isNotEmpty ? photoUrl : currentValue.photoUrl,
      );

      if (updated != currentValue) {
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
      photoUrl: photoUrl,
    );
    profile.value = updated;
    await _saveToPreferences(updated);
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
