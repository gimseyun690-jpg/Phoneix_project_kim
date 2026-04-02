import 'dart:math' as math;

import 'package:flutter/material.dart';

class AnimatedHeadingIcon extends StatefulWidget {
  const AnimatedHeadingIcon({
    super.key,
    required this.headingDegrees,
    required this.icon,
    required this.iconColor,
    required this.iconSize,
  });

  final double? headingDegrees;
  final IconData icon;
  final Color iconColor;
  final double iconSize;

  @override
  State<AnimatedHeadingIcon> createState() => _AnimatedHeadingIconState();
}

class _AnimatedHeadingIconState extends State<AnimatedHeadingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _turnAnimation;
  double _currentDegrees = 0;

  @override
  void initState() {
    super.initState();
    _currentDegrees = _normalize(widget.headingDegrees ?? 0);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _turnAnimation = AlwaysStoppedAnimation(_currentDegrees);
  }

  @override
  void didUpdateWidget(covariant AnimatedHeadingIcon oldWidget) {
    super.didUpdateWidget(oldWidget);

    final nextHeading = widget.headingDegrees;
    if (nextHeading == null || !nextHeading.isFinite) {
      return;
    }

    final start = _turnAnimation.value;
    final target = _normalize(nextHeading);
    final delta = _shortestDelta(start, target);
    if (delta.abs() < 0.2) {
      _currentDegrees = start;
      return;
    }

    final end = start + delta;
    _controller.duration = _durationForDelta(delta.abs());
    _turnAnimation = Tween<double>(
      begin: start,
      end: end,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );
    _currentDegrees = end;
    _controller
      ..stop()
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _turnAnimation,
      builder: (context, child) {
        final radians = _turnAnimation.value * (math.pi / 180);
        return Transform.rotate(
          angle: radians,
          child: child,
        );
      },
      child: Icon(
        widget.icon,
        color: widget.iconColor,
        size: widget.iconSize,
      ),
    );
  }

  Duration _durationForDelta(double delta) {
    if (delta >= 120) {
      return const Duration(milliseconds: 460);
    }
    if (delta >= 60) {
      return const Duration(milliseconds: 360);
    }
    if (delta >= 24) {
      return const Duration(milliseconds: 260);
    }
    if (delta >= 10) {
      return const Duration(milliseconds: 220);
    }
    return const Duration(milliseconds: 180);
  }

  double _normalize(double value) {
    final normalized = value % 360;
    return normalized < 0 ? normalized + 360 : normalized;
  }

  double _shortestDelta(double from, double to) {
    return (to - from + 540) % 360 - 180;
  }
}
