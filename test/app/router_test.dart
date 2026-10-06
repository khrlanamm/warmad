import 'package:flutter_test/flutter_test.dart';
import 'package:warmad/app/router.dart';
import 'package:warmad/features/profile/domain/user_profile.dart';

void main() {
  String? go(
    String location, {
    bool signedIn = true,
    bool loading = false,
    AppMode? mode,
    bool hasWarung = false,
  }) => resolveRedirect(
    location: location,
    signedIn: signedIn,
    loading: loading,
    mode: mode,
    hasWarung: hasWarung,
  );

  group('resolveRedirect', () {
    test('sends signed out users to sign in from anywhere', () {
      expect(go(Routes.warung, signedIn: false), Routes.signIn);
      expect(go(Routes.buyer, signedIn: false), Routes.signIn);
      expect(go(Routes.signIn, signedIn: false), isNull);
    });

    test('holds on the loading screen until the account is known', () {
      expect(go(Routes.signIn, loading: true), Routes.loading);
      expect(go(Routes.loading, loading: true), isNull);
    });

    test('asks a new user to pick a role', () {
      expect(go(Routes.loading), Routes.role);
      expect(go(Routes.warung), Routes.role);
      expect(go(Routes.role), isNull);
    });

    test('sends an owner without a warung to registration', () {
      expect(go(Routes.loading, mode: AppMode.warung), Routes.warungSetup);
      expect(go(Routes.warung, mode: AppMode.warung), Routes.warungSetup);
      expect(go(Routes.warungSetup, mode: AppMode.warung), isNull);
    });

    test('lets an owner without a warung go back to the role choice', () {
      expect(go(Routes.role, mode: AppMode.warung), isNull);
    });

    test('keeps a warung member inside the warung side', () {
      String? member(String location) =>
          go(location, mode: AppMode.warung, hasWarung: true);
      expect(member(Routes.loading), Routes.warung);
      expect(member(Routes.warungSetup), Routes.warung);
      expect(member(Routes.role), Routes.warung);
      expect(member(Routes.buyer), Routes.warung);
      expect(member(Routes.warung), isNull);
      expect(member(Routes.warungPos), isNull);
      expect(member(Routes.warungAccount), isNull);
    });

    test('keeps a buyer out of the warung side', () {
      String? buyer(String location) => go(location, mode: AppMode.pembeli);
      expect(buyer(Routes.warung), Routes.buyer);
      expect(buyer(Routes.warungPos), Routes.buyer);
      expect(buyer(Routes.warungSetup), Routes.buyer);
      expect(buyer(Routes.buyer), isNull);
      expect(buyer(Routes.buyerSearch), isNull);
    });

    test('a warung member in buyer mode stays on the buyer side', () {
      expect(
        go(Routes.warung, mode: AppMode.pembeli, hasWarung: true),
        Routes.buyer,
      );
    });
  });
}
