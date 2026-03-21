import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Shimmer skeleton loader para la carga inicial.
/// Reemplaza el spinner con un placeholder visual de la lista de archivos.
class SkeletonLoader extends StatefulWidget {
  const SkeletonLoader({super.key});

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
    _animation = Tween<double>(begin: -1, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.md),
              // Search bar skeleton
              _SkeletonBox(
                width: double.infinity,
                height: 44,
                borderRadius: AppRadius.borderMd,
                shimmerValue: _animation.value,
              ),
              const SizedBox(height: AppSpacing.md),
              // File items skeleton
              for (int i = 0; i < 6; i++) ...[
                _SkeletonFileRow(shimmerValue: _animation.value),
                const SizedBox(height: AppSpacing.sm),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SkeletonFileRow extends StatelessWidget {
  const _SkeletonFileRow({required this.shimmerValue});

  final double shimmerValue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          // Emoji placeholder
          _SkeletonBox(
            width: 32,
            height: 32,
            borderRadius: AppRadius.borderSm,
            shimmerValue: shimmerValue,
          ),
          const SizedBox(width: AppSpacing.sm),
          // Text placeholders
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBox(
                  width: 140,
                  height: 14,
                  borderRadius: AppRadius.borderSm,
                  shimmerValue: shimmerValue,
                ),
                const SizedBox(height: 6),
                _SkeletonBox(
                  width: 60,
                  height: 10,
                  borderRadius: AppRadius.borderSm,
                  shimmerValue: shimmerValue,
                ),
              ],
            ),
          ),
          // Action buttons placeholder
          _SkeletonBox(
            width: 28,
            height: 28,
            borderRadius: AppRadius.borderSm,
            shimmerValue: shimmerValue,
          ),
          const SizedBox(width: AppSpacing.sm),
          _SkeletonBox(
            width: 28,
            height: 28,
            borderRadius: AppRadius.borderSm,
            shimmerValue: shimmerValue,
          ),
        ],
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    required this.width,
    required this.height,
    required this.borderRadius,
    required this.shimmerValue,
  });

  final double width;
  final double height;
  final BorderRadius borderRadius;
  final double shimmerValue;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: const [
            AppColors.bgSecondary,
            AppColors.bgCardHover,
            AppColors.bgSecondary,
          ],
          stops: [
            (shimmerValue - 0.3).clamp(0.0, 1.0),
            shimmerValue.clamp(0.0, 1.0),
            (shimmerValue + 0.3).clamp(0.0, 1.0),
          ],
        ),
      ),
    );
  }
}
