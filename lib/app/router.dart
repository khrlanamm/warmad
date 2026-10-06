import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/data/auth_service.dart';
import '../features/auth/ui/sign_in_screen.dart';
import '../features/home/ui/home_screen.dart';

abstract final class Routes {
  static const home = '/';
  static const signIn = '/masuk';
}

final routerProvider = Provider<GoRouter>((ref) {
  // Re-runs the redirect whenever the signed in user changes.
  final refresh = ValueNotifier<int>(0);
  ref.listen(authStateProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.home,
    refreshListenable: refresh,
    redirect: (context, state) {
      final signedIn = ref.read(authServiceProvider).currentUser != null;
      final atSignIn = state.matchedLocation == Routes.signIn;
      if (!signedIn) return atSignIn ? null : Routes.signIn;
      if (atSignIn) return Routes.home;
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.signIn,
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: Routes.home,
        builder: (context, state) => const HomeScreen(),
      ),
    ],
  );
});
