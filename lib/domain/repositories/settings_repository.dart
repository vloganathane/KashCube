/// Abstract interface for app settings storage (key-value pairs).
abstract class SettingsRepository {
  /// Get a setting value by key, or null if not set.
  Future<String?> get(String key);

  /// Set a setting value.
  Future<void> set(String key, String value);

  /// Remove a setting by key.
  Future<void> remove(String key);

  /// Get all settings as a map.
  Future<Map<String, String>> getAll();
}
