import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/widgets/coming_soon.dart';
import '../features/auth/data/auth_service.dart';
import '../features/auth/ui/sign_in_screen.dart';
import '../features/buyer/ui/buyer_shell.dart';
import '../features/home/ui/home_screen.dart';
import '../features/onboarding/ui/loading_screen.dart';
import '../features/onboarding/ui/role_selection_screen.dart';
import '../features/onboarding/ui/warung_setup_screen.dart';
import '../features/profile/data/profile_repository.dart';
import '../features/profile/domain/user_profile.dart';
import '../features/warung_shell/ui/warung_account_screen.dart';
import '../features/warung_shell/ui/warung_shell.dart';

abstract final class Routes {
  static const signIn = '/masuk';
  static const loading = '/memuat';
  static const role = '/peran';
  static const warungSetup = '/daftar-warung';

  static const warung = '/warung';
  static const warungPos = '/warung/kasir';
  static const warungStock = '/warung/stok';
  static const warungReports = '/warung/laporan';
  static const warungAccount = '/warung/akun';

  static const buyer = '/pembeli';
  static const buyerSearch = '/pembeli/cari';
  static const buyerAccount = '/pembeli/akun';
}

/// Decides where a user belongs from who they are. Returns null to stay.
///
/// Kept free of Firebase types so the access rules of the app can be unit
/// tested.
String? resolveRedirect({
  required String location,
  required bool signedIn,
  required bool loading,
  required AppMode? mode,
  required bool hasWarung,
}) {
  bool within(String root) => location == root || location.startsWith('$root/');

  if (!signedIn) return location == Routes.signIn ? null : Routes.signIn;
  if (loading) return location == Routes.loading ? null : Routes.loading;

  final String home;
  if (mode == null) {
    home = Routes.role;
  } else if (mode == AppMode.pembeli) {
    home = Routes.buyer;
  } else if (hasWarung) {
    home = Routes.warung;
  } else {
    // An owner without a warung may still go back and change role.
    if (location == Routes.role) return null;
    home = Routes.warungSetup;
  }
  return within(home) ? null : home;
}

final routerProvider = Provider<GoRouter>((ref) {
  // Re-runs the redirect whenever the user, profile, or membership changes.
  final refresh = ValueNotifier<int>(0);
  void bump(Object? _, Object? _) => refresh.value++;
  ref.listen(authStateProvider, bump);
  ref.listen(userProfileProvider, bump);
  ref.listen(membershipProvider, bump);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.loading,
    refreshListenable: refresh,
    redirect: (context, state) {
      final profile = ref.read(userProfileProvider);
      final membership = ref.read(membershipProvider);
      return resolveRedirect(
        location: state.matchedLocation,
        signedIn: ref.read(authServiceProvider).currentUser != null,
        loading: !profile.hasValue || !membership.hasValue,
        mode: profile.value?.mode,
        hasWarung: membership.value != null,
      );
    },
    routes: [
      GoRoute(path: Routes.signIn, builder: (_, _) => const SignInScreen()),
      GoRoute(path: Routes.loading, builder: (_, _) => const LoadingScreen()),
      GoRoute(
        path: Routes.role,
        builder: (_, _) => const RoleSelectionScreen(),
      ),
      GoRoute(
        path: Routes.warungSetup,
        builder: (_, _) => const WarungSetupScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => WarungShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.warung,
                builder: (_, _) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.warungPos,
                builder: (_, _) => const ComingSoon(
                  title: 'Kasir',
                  icon: LucideIcons.shoppingCart,
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.warungStock,
                builder: (_, _) => const ComingSoon(
                  title: 'Stok barang',
                  icon: LucideIcons.package,
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.warungReports,
                builder: (_, _) => const ComingSoon(
                  title: 'Laporan',
                  icon: LucideIcons.chartColumn,
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.warungAccount,
                builder: (_, _) => const WarungAccountScreen(),
              ),
            ],
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => BuyerShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.buyer,
                builder: (_, _) =>
                    const ComingSoon(title: 'Peta', icon: LucideIcons.map),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.buyerSearch,
                builder: (_, _) => const ComingSoon(
                  title: 'Cari barang',
                  icon: LucideIcons.search,
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.buyerAccount,
                builder: (_, _) => const BuyerAccountScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
