import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';
import '../utils/format.dart';

class NavigationScreen extends StatelessWidget {
  final String routeId;
  final double? distanceMeters;
  final double? durationSeconds;

  const NavigationScreen({
    super.key,
    required this.routeId,
    this.distanceMeters,
    this.durationSeconds,
  });

  @override
  Widget build(BuildContext context) {
    final durationText =
        durationSeconds != null ? formatDuration(durationSeconds!) : '15 мин';
    final distanceText =
        distanceMeters != null ? formatDistance(distanceMeters!) : '4.2 км';

    return Scaffold(
      backgroundColor: AppColors.navBackground,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.pink.withValues(alpha: 0.3),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.turn_left,
                        size: 80, color: AppColors.primaryDark),
                  ),
                  const SizedBox(height: 20),
                  const Text('Через 200 м',
                      style: TextStyle(fontSize: 24, color: Colors.black54)),
                  const Text('Поверните налево',
                      style:
                          TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                  const Text('на ул. Пионовую',
                      style: TextStyle(fontSize: 20, color: Colors.black87)),
                ],
              ),
            ),
            Positioned(
              bottom: 30,
              left: 20,
              right: 20,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black12,
                        blurRadius: 10,
                        offset: Offset(0, 5)),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Text(
                            '60',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 20),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('км/ч',
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(durationText,
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                        Text(distanceText,
                            style: const TextStyle(color: Colors.grey)),
                      ],
                    ),
                    IconButton(
                      onPressed: () => context.go('/'),
                      icon: const Icon(Icons.close, color: Colors.redAccent),
                      style: IconButton.styleFrom(
                          backgroundColor: Colors.red.shade50),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
