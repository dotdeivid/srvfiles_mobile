import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../models/disk_stats.dart';
import '../utils/format.dart';

/// Barra de uso de disco. Replica DiskStats.tsx del frontend web.
/// Normal → warning (>80%) → critical (>95%).
///
/// [fullWidth]: si es true, renderiza horizontal ocupando todo el ancho
/// (para usar en AppBar.bottom). Si es false, usa el diseño compacto vertical.
class DiskStatsBar extends StatelessWidget {
  const DiskStatsBar({super.key, required this.stats, this.fullWidth = false});

  final DiskStats? stats;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    if (stats == null) return const SizedBox.shrink();

    final s = stats!;
    final percent = s.usedPercent / 100;

    Color fillColor;
    Gradient? fillGradient;
    if (s.isCritical) {
      fillColor = AppColors.danger;
    } else if (s.isWarning) {
      fillColor = AppColors.warning;
    } else {
      fillColor = Colors.transparent;
      fillGradient = AppColors.accentGradient;
    }

    Widget bar = ClipRRect(
      borderRadius: AppRadius.borderSm,
      child: SizedBox(
        width: fullWidth ? double.infinity : 120,
        height: fullWidth ? 3 : 6,
        child: Stack(
          children: [
            Container(color: AppColors.bgGlass),
            AnimatedFractionallySizedBox(
              duration: const Duration(milliseconds: 400),
              curve: Curves.ease,
              widthFactor: percent.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: fillGradient == null ? fillColor : null,
                  gradient: fillGradient,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final label = Text(
      '${formatBytes(s.used)} / ${formatBytes(s.total)}',
      style: const TextStyle(
        fontSize: 10,
        color: AppColors.textMuted,
        fontFamily: 'monospace',
      ),
    );

    if (fullWidth) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm,
        ),
        child: Row(
          children: [
            label,
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: bar),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [bar, const SizedBox(height: 4), label],
    );
  }
}
