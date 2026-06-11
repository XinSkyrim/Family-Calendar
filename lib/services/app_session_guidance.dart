class AppSessionGuidance {
  static final Set<String> _shownKeys = <String>{};

  static bool shouldShow(String key) {
    return _shownKeys.add(key);
  }
}
