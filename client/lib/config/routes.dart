import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../screens/agent_preset_management_screen.dart';
import '../screens/login/login_screen.dart';
import '../screens/login/totp_verify_screen.dart';
import '../screens/main/main_screen.dart';
import '../screens/model_management_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/splash_screen.dart';
import '../screens/token_management_screen.dart';

class AppRoutes {
  static const splash = '/splash';
  static const login = '/login';
  static const loginTotp = '/login/totp';
  static const home = '/';
  static const settings = '/settings';
  static const agentPresets = '/agent-presets';
  static const tokenManagement = '/token-management';
  static const modelManagement = '/settings/models';

  static GoRouter createRouter(AuthProvider authProvider) {
    return GoRouter(
      initialLocation: splash,
      refreshListenable: authProvider,
      redirect: (context, state) {
        final location = state.matchedLocation;
        final isAuthRoute = location == login || location == loginTotp;

        if (authProvider.status == AuthStatus.checking) {
          return location == splash ? null : splash;
        }

        if (!authProvider.isAuthenticated && !isAuthRoute) {
          return login;
        }

        if (authProvider.isAuthenticated &&
            (isAuthRoute || location == splash)) {
          return home;
        }

        return null;
      },
      routes: [
        GoRoute(
          path: splash,
          builder: (context, state) => const SplashScreen(),
        ),
        GoRoute(
          path: login,
          builder: (context, state) => const LoginScreen(),
          routes: [
            GoRoute(
              path: 'totp',
              builder: (context, state) {
                final tempToken = state.extra as String? ?? '';
                return TotpVerifyScreen(tempToken: tempToken);
              },
            ),
          ],
        ),
        GoRoute(
          path: home,
          builder: (context, state) => const MainScreen(),
        ),
        GoRoute(
          path: settings,
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: agentPresets,
          builder: (context, state) => const AgentPresetManagementScreen(),
        ),
        GoRoute(
          path: tokenManagement,
          builder: (context, state) => const TokenManagementScreen(),
        ),
        GoRoute(
          path: modelManagement,
          builder: (context, state) => const ModelManagementScreen(),
        ),
      ],
    );
  }
}
