import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/citizen/auth/application/session_controller.dart';
import '../../features/citizen/auth/presentation/name_screen.dart';
import '../../features/citizen/auth/presentation/otp_screen.dart';
import '../../features/citizen/auth/presentation/phone_screen.dart';
import '../../features/citizen/complaints/data/complaint_models.dart';
import '../../features/citizen/complaints/presentation/complaint_confirmation_screen.dart';
import '../../features/citizen/complaints/presentation/complaint_detail_screen.dart';
import '../../features/citizen/complaints/presentation/description_step_screen.dart';
import '../../features/citizen/complaints/presentation/location_step_screen.dart';
import '../../features/citizen/shell/citizen_shell.dart';
import '../../features/officer/application/officer_session_controller.dart';
import '../../features/officer/presentation/enroll/officer_enroll_screen.dart';
import '../../features/officer/presentation/officer_complaint_detail_screen.dart';
import '../../features/officer/presentation/officer_login_screen.dart';
import '../../features/officer/presentation/officer_otp_screen.dart';
import '../../features/officer/presentation/officer_shell.dart';
import '../../features/shared/role_select_screen.dart';
import '../../features/shared/theme_showcase_screen.dart';

/// Route paths. Kept as constants so call sites don't hardcode strings.
abstract final class AppRoutes {
  const AppRoutes._();

  /// Launch screen: pick Citizen or Officer.
  static const role = '/role';

  static const phone = '/auth/phone';
  static const otp = '/auth/otp';
  static const name = '/auth/name';
  static const home = '/home';

  // Officer side.
  static const officerLogin = '/officer/login';
  static const officerOtp = '/officer/otp';
  static const officerEnroll = '/officer/enroll';
  static const officerHome = '/officer/home';
  static const officerComplaintDetail = '/officer/complaint';

  /// Complaint registration stepper. Step 1 (photo) lives inside the Register
  /// tab of the shell; later steps are pushed full-screen on top.
  static const complaintDescription = '/complaint/new/description';
  static const complaintLocation = '/complaint/new/location';
  static const complaintConfirmation = '/complaint/new/confirmation';
  static const complaintDetail = '/complaint/detail';

  /// Design-system review screen from the scaffolding milestone. Left routable
  /// for reference; not part of the auth/home flow.
  static const showcase = '/showcase';
}

/// The application router, wired to session state.
///
/// Redirect rules:
///  - Logged-out users hitting [AppRoutes.home] are sent to the phone screen.
///  - Logged-in users hitting any `/auth/*` screen are sent to home.
///  - The OTP and name screens require a phone number passed via `extra`;
///    reached without one (e.g. a web refresh) they fall back to the phone
///    screen rather than crashing.
final goRouterProvider = Provider<GoRouter>((ref) {
  // Bridge both session providers to a Listenable so go_router re-evaluates
  // redirects when either role logs in / out.
  final refresh = ValueNotifier<int>(0);
  ref.onDispose(refresh.dispose);
  ref.listen<CitizenSession?>(
    sessionControllerProvider,
    (_, __) => refresh.value++,
  );
  ref.listen<OfficerSession?>(
    officerSessionProvider,
    (_, __) => refresh.value++,
  );

  return GoRouter(
    initialLocation: AppRoutes.role,
    refreshListenable: refresh,
    redirect: (context, state) {
      final citizen = ref.read(sessionControllerProvider);
      final officer = ref.read(officerSessionProvider);
      final loc = state.matchedLocation;
      final inCitizenAuth = loc.startsWith('/auth');
      final inOfficerArea = loc.startsWith('/officer');

      // --- Already authenticated: keep each role in its own app ---
      if (citizen != null) {
        if (loc == AppRoutes.role || inCitizenAuth || inOfficerArea) {
          return AppRoutes.home;
        }
      } else if (officer != null) {
        final officerAuthRoute = loc == AppRoutes.officerLogin ||
            loc == AppRoutes.officerOtp ||
            loc == AppRoutes.officerEnroll;
        if (loc == AppRoutes.role || inCitizenAuth || officerAuthRoute) {
          return AppRoutes.officerHome;
        }
      } else {
        // --- Not authenticated ---
        // Public/unauthenticated-allowed locations:
        final allowed = loc == AppRoutes.role ||
            loc == AppRoutes.showcase ||
            inCitizenAuth ||
            loc == AppRoutes.officerLogin ||
            loc == AppRoutes.officerOtp ||
            loc == AppRoutes.officerEnroll;
        if (!allowed) return AppRoutes.role;
      }

      // Steps that need a phone number carried via extra can't be entered cold.
      final needsPhone = loc == AppRoutes.otp ||
          loc == AppRoutes.name ||
          loc == AppRoutes.officerOtp;
      if (needsPhone && state.extra is! String) {
        return inOfficerArea ? AppRoutes.officerLogin : AppRoutes.phone;
      }

      // The confirmation screen needs its args; reached cold, go home.
      if (loc == AppRoutes.complaintConfirmation &&
          state.extra is! ComplaintConfirmationArgs) {
        return AppRoutes.home;
      }

      // The detail screen needs the complaint object passed via extra.
      if (loc == AppRoutes.complaintDetail &&
          state.extra is! ComplaintSummary) {
        return AppRoutes.home;
      }

      // The officer complaint detail needs its args.
      if (loc == AppRoutes.officerComplaintDetail &&
          state.extra is! OfficerComplaintArgs) {
        return AppRoutes.officerHome;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.role,
        builder: (context, state) => const RoleSelectScreen(),
      ),
      GoRoute(
        path: AppRoutes.phone,
        builder: (context, state) => const PhoneScreen(),
      ),
      GoRoute(
        path: AppRoutes.otp,
        builder: (context, state) =>
            OtpScreen(phoneNumber: state.extra! as String),
      ),
      GoRoute(
        path: AppRoutes.name,
        builder: (context, state) =>
            NameScreen(phoneNumber: state.extra! as String),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const CitizenShell(),
      ),
      GoRoute(
        path: AppRoutes.complaintDescription,
        builder: (context, state) => const DescriptionStepScreen(),
      ),
      GoRoute(
        path: AppRoutes.complaintLocation,
        builder: (context, state) => const LocationStepScreen(),
      ),
      GoRoute(
        path: AppRoutes.complaintConfirmation,
        builder: (context, state) => ComplaintConfirmationScreen(
          args: state.extra! as ComplaintConfirmationArgs,
        ),
      ),
      GoRoute(
        path: AppRoutes.complaintDetail,
        builder: (context, state) =>
            ComplaintDetailScreen(complaint: state.extra! as ComplaintSummary),
      ),
      // --- Officer side ---
      GoRoute(
        path: AppRoutes.officerLogin,
        builder: (context, state) => const OfficerLoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.officerOtp,
        builder: (context, state) =>
            OfficerOtpScreen(phoneNumber: state.extra! as String),
      ),
      GoRoute(
        path: AppRoutes.officerEnroll,
        builder: (context, state) => const OfficerEnrollScreen(),
      ),
      GoRoute(
        path: AppRoutes.officerHome,
        builder: (context, state) => const OfficerShell(),
      ),
      GoRoute(
        path: AppRoutes.officerComplaintDetail,
        builder: (context, state) => OfficerComplaintDetailScreen(
          args: state.extra! as OfficerComplaintArgs,
        ),
      ),
      GoRoute(
        path: AppRoutes.showcase,
        builder: (context, state) => const ThemeShowcaseScreen(),
      ),
    ],
  );
});
