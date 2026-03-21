import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class GradientText extends StatelessWidget {
  const GradientText(
    this.text, {
    super.key,
    this.style,
    this.gradient,
  });

  final String text;
  final TextStyle? style;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => (gradient ?? AppColors.accentGradient)
          .createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
      child: Text(text, style: style),
    );
  }
}
