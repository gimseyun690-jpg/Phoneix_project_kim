import 'package:flutter/material.dart';

import '../models/app_models.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final FlightStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      FlightStatus.good => const Color(0xFF2A9D8F),
      FlightStatus.caution => const Color(0xFFE9C46A),
      FlightStatus.bad => const Color(0xFFE76F51),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
