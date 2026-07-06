import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/api_client.dart';
import 'core/nava360_splash_screen.dart';
import 'core/theme.dart';
import 'features/app_update/in_app_update_gate.dart';
import 'features/attendance/attendance_screen.dart';
import 'features/attendance/location_lifecycle.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/biometric/biometric_enroll_gate.dart';
import 'features/auth/biometric/registered_devices_screen.dart';
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
import 'features/home/module_screens.dart';
import 'features/leaves/leaves_screen.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/notifications/push_lifecycle.dart';
import 'features/notifications/push_service.dart';
import 'features/permissions/permission_gate.dart';
import 'features/profile/my_documents_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/team/team_screen.dart';
import 'features/chat/chat_list_screen.dart';
import 'features/chat/chat_thread_by_id_screen.dart';
import 'features/meetings/meetings_screen.dart';
import 'features/trainings/trainings_screen.dart';
import 'features/announcements/announcements_screen.dart';
import 'features/announcements/announcement_detail_screen.dart';
import 'features/policies/policies_screen.dart';
import 'features/policies/policy_detail_screen.dart';
import 'features/whistleblower/whistleblower_form_screen.dart';
import 'features/assets/my_assets_screen.dart';
import 'features/assets/asset_scan_screen.dart';
import 'features/payslips/payslips_screen.dart';
import 'features/performance/my_performance_screen.dart';
import 'features/performance/team_performance_screen.dart';
import 'features/audit/my_audits_screen.dart';
import 'features/helpdesk/helpdesk_tickets_screen.dart';
import 'features/helpdesk/helpdesk_raise_screen.dart';
import 'features/helpdesk/helpdesk_ticket_detail_screen.dart';
import 'features/helpdesk/helpdesk_kb_screen.dart';
import 'features/helpdesk/helpdesk_dashboard_screen.dart';
import 'features/resignation/resignation_screen.dart';
import 'features/travel/travel_models.dart';
import 'features/travel/travel_plans_screen.dart';
import 'features/travel/travel_plan_form_screen.dart';
import 'features/travel/travel_claims_screen.dart';
import 'features/travel/travel_claim_form_screen.dart';
import 'features/travel/travel_claim_detail_screen.dart';
import 'features/travel/travel_approvals_screen.dart';
import 'features/travel/travel_claim_review_screen.dart';

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
        path: '/profile/documents',
        builder: (_, __) => const MyDocumentsScreen(),
      ),
      GoRoute(
        path: '/change-password',
        builder: (_, __) => const ChangePasswordScreen(),
      ),
      GoRoute(
        path: '/security/devices',
        builder: (_, __) => const RegisteredDevicesScreen(),
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
        path: '/announcements',
        builder: (_, __) => const AnnouncementsScreen(),
      ),
      GoRoute(
        path: '/announcements/:id',
        builder: (_, state) => AnnouncementDetailScreen(
          announcementId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/policies',
        builder: (_, __) => const PoliciesScreen(),
      ),
      GoRoute(
        path: '/policies/:id',
        builder: (_, state) => PolicyDetailScreen(
          policyId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/whistleblower',
        builder: (_, __) => const WhistleblowerFormScreen(),
      ),
      GoRoute(
        path: '/assets',
        builder: (_, __) => const MyAssetsScreen(),
      ),
      GoRoute(
        path: '/assets/scan',
        builder: (_, __) => const AssetScanScreen(),
      ),
      GoRoute(
        path: '/my-payslips',
        builder: (_, __) => const PayslipsScreen(),
      ),
      GoRoute(
        path: '/my-resignation',
        builder: (_, __) => const ResignationScreen(),
      ),
      GoRoute(
        path: '/my-performance',
        builder: (_, __) => const MyPerformanceScreen(),
      ),
      GoRoute(
        path: '/audit',
        builder: (_, __) => const MyAuditsScreen(),
      ),
      // ── Helpdesk (Enterprise Service Desk) ──
      GoRoute(
        path: '/helpdesk',
        builder: (_, __) => const HelpdeskTicketsScreen(),
      ),
      GoRoute(
        path: '/helpdesk/raise',
        builder: (_, __) => const HelpdeskRaiseScreen(),
      ),
      GoRoute(
        path: '/helpdesk/tickets/:id',
        builder: (_, state) =>
            HelpdeskTicketDetailScreen(ticketId: int.parse(state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/helpdesk/kb',
        builder: (_, __) => const KnowledgeBaseScreen(),
      ),
      GoRoute(
        path: '/helpdesk/kb/:id',
        builder: (_, state) => KbArticleScreen(articleId: int.parse(state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/helpdesk/dashboard',
        builder: (_, __) => const HelpdeskDashboardScreen(),
      ),
      // ── Travel Management (employee self-service) ──
      GoRoute(
        path: '/travel/plans',
        builder: (_, __) => const TravelPlansScreen(),
      ),
      GoRoute(
        path: '/travel/plans/new',
        builder: (_, __) => const TravelPlanFormScreen(),
      ),
      GoRoute(
        path: '/travel/plans/edit',
        builder: (_, state) =>
            TravelPlanFormScreen(plan: state.extra as TravelPlan?),
      ),
      GoRoute(
        path: '/travel/claims',
        builder: (_, __) => const TravelClaimsScreen(),
      ),
      // Static sub-routes must precede '/travel/claims/:id' so they aren't
      // captured as an id.
      GoRoute(
        path: '/travel/claims/new',
        builder: (_, __) => const TravelClaimFormScreen(),
      ),
      GoRoute(
        path: '/travel/claims/edit',
        builder: (_, state) =>
            TravelClaimFormScreen(claim: state.extra as TravelClaim?),
      ),
      GoRoute(
        path: '/travel/claims/:id',
        builder: (_, state) => TravelClaimDetailScreen(
          claimId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/travel/approvals',
        builder: (_, __) => const TravelApprovalsScreen(),
      ),
      GoRoute(
        path: '/travel/review/:id',
        builder: (_, state) => TravelClaimReviewScreen(
          claimId: int.parse(state.pathParameters['id']!),
        ),
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
          GoRoute(path: '/performance', builder: (_, __) => const TeamPerformanceScreen()),
          GoRoute(path: '/hrms', builder: (_, __) => const HrmsScreen()),
          GoRoute(path: '/payroll', builder: (_, __) => const PayrollScreen()),
          GoRoute(path: '/more', builder: (_, __) => const MoreScreen()),
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

/// App-opening splash. Shown by the router while auth/welcome flags bootstrap;
/// the redirect then sends the user to Home (logged in) or Login/Welcome
/// (logged out). Navigation lives in the router — this only renders the
/// branded loader, replacing the old blank/gradient spinner.
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  // No onFinish — the router redirect moves off /splash once auth/welcome
  // finish bootstrapping, so navigation stays exactly as before.
  @override
  Widget build(BuildContext context) => const Nava360SplashScreen();
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
    // …and into an announcement.
    ref.read(pushServiceProvider).onOpenAnnouncement =
        (id) => router.push('/announcements/$id');
    // …and into a company policy.
    ref.read(pushServiceProvider).onOpenPolicy =
        (id) => router.push('/policies/$id');
    // …and into the employee's assets (asset assignment / warranty pushes).
    ref.read(pushServiceProvider).onOpenAssets = () => router.push('/assets');
    return MaterialApp.router(
      title: 'Nava360',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: router,
      // Gate the app behind, in order:
      //   1. PermissionGate — once signed in, a hard wall until location
      //      ("Allow all the time"), battery-optimisation exemption and
      //      notifications are all granted (pass-through while signed out).
      //   2. InAppUpdateGate — Google Play's native in-app update flow.
      //   3. BiometricEnrollGate — offers biometric enrollment once, right after
      //      a fresh password login (no-op otherwise).
      builder: (context, child) => PermissionGate(
        child: InAppUpdateGate(
          child: BiometricEnrollGate(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}
