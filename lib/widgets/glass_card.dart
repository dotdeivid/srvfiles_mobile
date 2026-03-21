import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
    this.borderColor,
    this.backgroundColor,
    this.blurSigma = 20,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final Color? borderColor;
  final Color? backgroundColor;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? AppRadius.borderLg;

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          decoration: BoxDecoration(
            color: backgroundColor ?? AppColors.bgCard,
            borderRadius: radius,
            border: Border.all(
              color: borderColor ?? AppColors.borderSubtle,
            ),
          ),
          padding: padding ?? const EdgeInsets.all(AppSpacing.md),
          child: child,
        ),
      ),
    );
  }
}
