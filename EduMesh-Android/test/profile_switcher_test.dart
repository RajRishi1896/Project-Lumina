import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:edumesh_android/features/auth/data/auth_service.dart';

/// Unit tests for the offline account-switcher logic in [AuthService]:
/// known-profile listing, password-free switching, metadata mirroring, and
/// logout that removes only the active profile.
void main() {
  const usersKey = 'lumina_users_list_secure';

  void seedTwoProfiles() {
    FlutterSecureStorage.setMockInitialValues({
      usersKey:
          '[{"username":"priya","userId":"u1","displayName":"Priya","grade":"9",'
              '"token":"tok1","refreshToken":"rt1","persistentKey":"pk1"},'
              '{"username":"arjun","userId":"u2","displayName":"Arjun","grade":"10",'
              '"token":"tok2","refreshToken":"rt2","persistentKey":"pk2"}]',
      'lumina_unique_user_id': 'u1',
      'lumina_username': 'priya',
      'lumina_display_name': 'Priya',
      'lumina_grade': '9',
      'lumina_session_token': 'tok1',
      'lumina_refresh_token': 'rt1',
      'lumina_persistent_key': 'pk1',
    });
  }

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('getKnownProfiles returns identity only, never tokens', () async {
    seedTwoProfiles();
    final profiles = await AuthService().getKnownProfiles();

    expect(profiles, hasLength(2));
    expect(profiles[0]['username'], 'priya');
    expect(profiles[0]['displayName'], 'Priya');
    expect(profiles[0].containsKey('token'), isFalse);
    expect(profiles[0].containsKey('refreshToken'), isFalse);
    expect(profiles[0].containsKey('persistentKey'), isFalse);
  });

  test('switchToProfile restores identity, credentials, and metadata offline', () async {
    seedTwoProfiles();
    final auth = AuthService();

    final ok = await auth.switchToProfile('u2');
    expect(ok, isTrue);

    expect(await auth.getUniqueUserId(), 'u2');
    expect(await auth.getLoggedUsername(), 'arjun');
    expect(await auth.getDisplayName(), 'Arjun');
    expect(await auth.getGradeOrDefault(), '10');
    expect(await auth.getSessionToken(), 'tok2');
  });

  test('switchToProfile refuses an unknown user id', () async {
    seedTwoProfiles();
    final ok = await AuthService().switchToProfile('nobody');
    expect(ok, isFalse);
    expect(await AuthService().getUniqueUserId(), 'u1');
  });

  test('logout removes only the active profile; others stay switchable', () async {
    seedTwoProfiles();
    final auth = AuthService();

    await auth.switchToProfile('u2');
    await auth.logout();

    expect(await auth.getUniqueUserId(), isNull);
    expect(await auth.getSessionToken(), isNull);

    final remaining = await auth.getKnownProfiles();
    expect(remaining, hasLength(1));
    expect(remaining[0]['username'], 'priya');

    final switchedBack = await auth.switchToProfile('u1');
    expect(switchedBack, isTrue);
    expect(await auth.getDisplayName(), 'Priya');
    expect(await auth.getSessionToken(), 'tok1');
  });

  test('logout on a lone profile leaves the device with no profiles', () async {
    FlutterSecureStorage.setMockInitialValues({
      usersKey: '[{"username":"priya","userId":"u1"}]',
      'lumina_unique_user_id': 'u1',
      'lumina_username': 'priya',
      'lumina_session_token': 'tok1',
    });

    await AuthService().logout();

    expect(await AuthService().getKnownProfiles(), isEmpty);
  });

  test('profile metadata edits survive a switch away and back', () async {
    seedTwoProfiles();
    final auth = AuthService();

    await auth.saveGrade('12');
    await auth.switchToProfile('u2');
    await auth.switchToProfile('u1');

    expect(await auth.getGradeOrDefault(), '12');
  });
}