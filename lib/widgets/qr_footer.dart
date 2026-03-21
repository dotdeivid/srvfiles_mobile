import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../theme/app_colors.dart';
import '../models/app_config.dart';

/// Footer con QR code para acceder desde otro dispositivo.
/// Replica QRFooter.tsx del frontend web.
class QrFooter extends StatelessWidget {
  const QrFooter({super.key, required this.config});

  final AppConfig? config;

  @override
  Widget build(BuildContext context) {
    if (config == null) return const SizedBox.shrink();

    final lanUrl = 'http://${config!.lanIp}:${config!.port}';
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.lg,
        horizontal: AppSpacing.md,
      ),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.borderSubtle),
        ),
      ),
      child: Column(
        children: [
          Text(
            'Accedé desde otro dispositivo',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Escaneá el código QR para abrir la app',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),

          // QR Code
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              borderRadius: AppRadius.borderMd,
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: QrImageView(
              data: lanUrl,
              version: QrVersions.auto,
              size: 140,
              backgroundColor: Colors.transparent,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: AppColors.textAccent,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: AppColors.textAccent,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // URL
          Text(
            lanUrl,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textAccent,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
