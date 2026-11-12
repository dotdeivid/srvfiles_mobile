import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';
import '../models/app_config.dart';

/// Footer con QR code para acceder desde otro dispositivo.
/// Replica QRFooter.tsx del frontend web.
///
/// El QR va en módulos oscuros sobre fondo blanco: los QR invertidos (claro
/// sobre oscuro) no los leen muchas cámaras. La URL usa el puerto del
/// frontend web, que es el que abre el navegador.
class QrFooter extends StatelessWidget {
  const QrFooter({super.key, required this.config});

  final AppConfig? config;

  @override
  Widget build(BuildContext context) {
    final cfg = config;
    if (cfg == null || cfg.lanIp.isEmpty) return const SizedBox.shrink();

    final lanUrl = 'http://${cfg.lanIp}:${cfg.frontendPort}';
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
          const SizedBox(height: AppSpacing.md),

          // QR Code
          Semantics(
            label: 'Código QR con la dirección $lanUrl',
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: AppRadius.borderMd,
              ),
              child: QrImageView(
                data: lanUrl,
                version: QrVersions.auto,
                size: 140,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Colors.black,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Colors.black,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SelectableText(
            lanUrl,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Copyright
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                '© 2026 Carlos David Sandoval · ',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
              TextButton(
                onPressed: () => launchUrl(
                  Uri.parse('https://github.com/dotdeivid'),
                  mode: LaunchMode.externalApplication,
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 36),
                ),
                child: const Text(
                  'github.com/dotdeivid',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textAccent,
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.textAccent,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
