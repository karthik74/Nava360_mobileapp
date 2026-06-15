import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/api_client.dart';
import 'core/theme.dart';
import 'features/app_version/app_version_gate.dart';
import 'features/attendance/attendance_screen.dart';
import 'features/attendance/location_lifecycle.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/welcome_seen_controller.dart';
import 'features/auth/change_password_screen.dart';
import 'features/auth/first_login_screen.dart';
import 'features/auth/forgot_password_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/reset_password_screen.dart';
import 'features/auth/welcome_screen.dart';
import 'features/interviews/interviews_screen.dart';
import 'features/requisitions/create_requisition_screen.dart';
import 'features/requisitions/requisitions_screen.dart';
import 'features/support/help_support_screen.dart';
import 'features/customers/customers_screen.dart';
import 'features/home/dashboard_screen.dart';
import 'features/home/home_shell.dart';
import 'features/leaves/leaves_screen.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/notifications/push_lifecycle.dart';
import 'features/notifications/push_service.dart';
import 'features/profile/profile_screen.dart';
import 'features/team/team_screen.dart';
import 'features/chat/chat_list_screen.dart';
import 'features/chat/chat_thread_by_id_screen.dart';
import 'features/meetings/meetings_screen.dart';
import 'features/trainings/trainings_screen.dart';
import 'features/payslips/payslips_screen.dart';
import 'features/resignation/resignation_screen.dart';

final goRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/home',
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final welcome = ref.read(welcomeSeenProvider);

      // Still bootstrapping either flag — sit on the splash.
      if (auth.isLoading || welcome.isLoading) return '/splash';

      final loggedIn = auth.asData?.value != null;
      final welcomeSeen = welcome.asData?.value ?? false;
      final loc = state.matchedLocation;

      // Signed-in users never see welcome/login/splash.
      if (loggedIn) {
        if (loc == '/welcome' || loc == '/login' || loc == '/splash') {
          return '/home';
        }
        return null;
      }

      const authRoutes = {
        '/welcome',
        '/login',
        '/forgot-password',
        '/reset-password',
        '/first-login',
      };

      // Signed-out users.
      if (!welcomeSeen) {
        // First-launch flow: pin to /welcome until they tap Get Started.
        if (!authRoutes.contains(loc)) return '/welcome';
        return null;
      }

      // Returning user — skip welcome.
      if (loc == '/splash' || loc == '/welcome') return '/login';
      if (authRoutes.contains(loc)) return null;
      return '/login';
    },
    refreshListenable: _GoRouterRefresh(ref),
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const _SplashScreen()),
      GoRoute(path: '/welcome', builder: (_, __) => const WelcomeScreen()),
      GoRoute(
        path: '/login',
        builder: (_, state) {
          final flash = state.extra is String ? state.extra as String : null;
          return LoginScreen(flash: flash);
        },
      ),
      GoRoute(
        path: '/first-login',
        builder: (_, __) => const FirstLoginScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (_, state) {
          final user = state.extra is String ? state.extra as String : null;
          return ForgotPasswordScreen(initialUsername: user);
        },
      ),
      GoRoute(
        path: '/reset-password',
        builder: (_, state) {
          final user = state.extra is String ? state.extra as String : null;
          return ResetPasswordScreen(username: user);
        },
      ),
      GoRoute(
        path: '/profile',
        builder: (_, __) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/change-password',
        builder: (_, __) => const ChangePasswordScreen(),
      ),
      GoRoute(
        path: '/help-support',
        builder: (_, __) => const HelpSupportScreen(),
      ),
      GoRoute(
        path: '/interviews',
        builder: (_, __) => const InterviewsScreen(),
      ),
      GoRoute(
        path: '/requisitions',
        builder: (_, __) => const RequisitionsScreen(),
      ),
      GoRoute(
        path: '/requisitions/new',
        builder: (_, __) => const CreateRequisitionScreen(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (_, __) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/chats',
        builder: (_, __) => const ChatListScreen(),
      ),
      GoRoute(
        path: '/chats/:id',
        builder: (_, state) => ChatThreadByIdScreen(
          conversationId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/my-meetings',
        builder: (_, __) => const MeetingsScreen(),
      ),
      GoRoute(
        path: '/my-trainings',
        builder: (_, __) => const TrainingsScreen(),
      ),
      GoRoute(
        path: '/my-payslips',
        builder: (_, __) => const PayslipsScreen(),
      ),
      GoRoute(
        path: '/my-resignation',
        builder: (_, __) => const ResignationScreen(),
      ),
      ShellRoute(
        builder: (_, __, child) => HomeShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const DashboardScreen()),
          GoRoute(
            path: '/attendance',
            builder: (_, __) => const AttendanceScreen(),
          ),
          GoRoute(path: '/leaves', builder: (_, __) => const LeavesScreen()),
          GoRoute(path: '/tasks', builder: (_, __) => const CustomerTasksHub()),
          GoRoute(path: '/team', builder: (_, __) => const TeamScreen()),
        ],
      ),
    ],
  );
});

class _GoRouterRefresh extends ChangeNotifier {
  _GoRouterRefresh(Ref ref) {
    ref.listen(authControllerProvider, (_, __) => notifyListeners());
    ref.listen(welcomeSeenProvider, (_, __) => notifyListeners());
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.heroGradient),
        child: const Center(
          child: SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(Colors.white),
              strokeWidth: 3,
            ),
          ),
        ),
      ),
    );
  }
}

class HrmsApp extends ConsumerWidget {
  const HrmsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    // Activate the auth → side-effect bindings once at the app root.
    ref.watch(locationLifecycleProvider);
    ref.watch(pushLifecycleProvider);
    // On any 401, clear credentials and bounce to /login. Set once (??=) so
    // rebuilds don't re-wire it. Read the notifier lazily inside the callback so
    // we always hit the live controller.
    final api = ref.read(apiClientProvider);
    api.onUnauthorized ??= () {
      ref.read(authControllerProvider.notifier).sessionExpired();
    };
    // Let push-notification taps deep-link into a chat thread.
    ref.read(pushServiceProvider).onOpenChat = (id) => router.push('/chats/$id');
    return MaterialApp.router(
      title: 'Nava360',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: router,
      // Gate the whole app behind the backend version check: a dismissible
      // banner when an update is available, a blocking screen when it's forced.
      builder: (context, child) =>
          AppUpdateGate(child: child ?? const SizedBox.shrink()),
    );
  }
}
