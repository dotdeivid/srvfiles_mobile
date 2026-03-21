import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Punto verde con animación de pulse (glow pulsante).
/// Replica el efecto CSS del frontend web.
class PulsingDot extends StatefulWidget {
  const PulsingDot({super.key, this.size = 8, this.color});

  final double size;
  final Color? color;

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? AppColors.success;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: _animation.value),
                blurRadius: 5,
                spreadRadius: 1,
              ),
            ],
          ),
        );
      },
    );
  }
}
