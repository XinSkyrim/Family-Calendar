import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'user_profile_service.dart';

class SessionManager {
  static const String _lastActiveKey = 'last_active_at';
  static const Duration _sessionTimeout = Duration(hours: 72);

  static Future<void> markActiveNow() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt(
      _lastActiveKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  static Future<bool> isSessionExpired() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    final lastActiveMillis = prefs.getInt(_lastActiveKey);

    if (lastActiveMillis == null) {
      await markActiveNow();
      return false;
    }

    final lastActiveTime = DateTime.fromMillisecondsSinceEpoch(
      lastActiveMillis,
    );

    final now = DateTime.now();
    final inactiveDuration = now.difference(lastActiveTime);

    return inactiveDuration > _sessionTimeout;
  }

  static Future<void> signOutIfExpired() async {
    final expired = await isSessionExpired();

    if (expired) {
      await signOutCompletely();
    }
  }

  static Future<void> signOutCompletely() async {
    await clearSession();
    await UserProfileService.clear();

    try {
      await GoogleSignIn().signOut();
    } catch (_) {
    }

    await FirebaseAuth.instance.signOut();
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastActiveKey);
  }
}