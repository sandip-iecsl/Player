// ─────────────────────────────────────────────────────────────────────────────
// App-wide constants
// ─────────────────────────────────────────────────────────────────────────────

class AppConstants {
  AppConstants._();

  static const String appName = 'Smart Home';
  static const String appVersion = '1.0.0';

  // Firestore collections
  static const String usersCollection = 'users';
  static const String devicesCollection = 'devices';
  static const String roomsCollection = 'rooms';
  static const String adminsCollection = 'admins';
  static const String logsCollection = 'audit_logs';
  static const String automationsCollection = 'automations';
  static const String notificationsCollection = 'notifications';

  // Firebase Realtime Database paths
  static const String relaysPath = 'relays';
  static const String espStatusPath = 'esp_status';
  static const String heartbeatPath = 'heartbeat';

  // Relay count
  static const int relayCount = 10;

  // Default relay names
  static const List<String> defaultRelayNames = [
    'Living Room Light',
    'Bedroom Light',
    'Kitchen Light',
    'Bathroom Light',
    'Garden Light',
    'Fan',
    'AC',
    'Plug 1',
    'Plug 2',
    'Relay 10',
  ];

  // Hive boxes
  static const String devicesBox = 'devices_box';
  static const String roomsBox = 'rooms_box';
  static const String settingsBox = 'settings_box';
  static const String themeBox = 'theme_box';

  // SharedPreferences keys
  static const String kRememberMe = 'remember_me';
  static const String kUserEmail = 'user_email';
  static const String kThemeMode = 'theme_mode';
  static const String kLanguage = 'language';
  static const String kOnboarded = 'onboarded';

  // Session
  static const int sessionTimeoutMinutes = 60;

  // Roles
  static const String roleUser = 'user';
  static const String roleAdmin = 'admin';

  // Status
  static const String statusActive = 'active';
  static const String statusDisabled = 'disabled';
  static const String statusPending = 'pending';
}
