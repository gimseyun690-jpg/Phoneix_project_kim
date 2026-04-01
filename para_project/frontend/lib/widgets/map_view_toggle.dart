import 'package:flutter/material.dart';

import '../core/map_view_type.dart';

class MapViewToggle extends StatelessWidget {
  const MapViewToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  final ParaglidingMapViewType value;
  final ValueChanged<ParaglidingMapViewType> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.all(compact ? 3 : 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(compact ? 14 : 18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: ParaglidingMapViewType.values.map((type) {
          final selected = type == value;
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 1 : 2),
            child: InkWell(
              borderRadius: BorderRadius.circular(compact ? 11 : 14),
              onTap: selected ? null : () => onChanged(type),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 10 : 14,
                  vertical: compact ? 7 : 10,
                ),
                decoration: BoxDecoration(
                  color:
                      selected ? theme.colorScheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(compact ? 11 : 14),
                ),
                child: Text(
                  type.label,
                  style: (compact
                          ? theme.textTheme.labelMedium
                          : theme.textTheme.labelLarge)
                      ?.copyWith(
                    color: selected ? Colors.white : const Color(0xFF304654),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}
