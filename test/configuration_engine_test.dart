import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aura_player/features/admin/engines/configuration_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('updateSettings persists passcodes locally for secure screens', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await ConfigurationEngine().updateSettings({
      'adminPasscode': 'new-admin-pass',
      'appLockPasscode': 'new-app-pass',
      'secretConsolePasscode': 'new-secret-pass',
      'chatExpiryHours': 48,
    });

    expect(prefs.getString('cached_adminPasscode'), 'new-admin-pass');
    expect(prefs.getString('cached_appLockPasscode'), 'new-app-pass');
    expect(prefs.getString('cached_secretConsolePasscode'), 'new-secret-pass');
    expect(prefs.getInt('cached_chatExpiryHours'), 48);
  });
}
