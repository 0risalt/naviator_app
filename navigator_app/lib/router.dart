import 'package:go_router/go_router.dart';

import 'screens/home_screen.dart';
import 'screens/navigation_screen.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
      routes: [
        GoRoute(
          path: 'navigate/:id',
          builder: (context, state) {
            final extra = state.extra;
            double? distance;
            double? duration;
            if (extra is Map) {
              distance = (extra['distance'] as num?)?.toDouble();
              duration = (extra['duration'] as num?)?.toDouble();
            }
            return NavigationScreen(
              routeId: state.pathParameters['id'] ?? '1',
              distanceMeters: distance,
              durationSeconds: duration,
            );
          },
        ),
      ],
    ),
  ],
);
