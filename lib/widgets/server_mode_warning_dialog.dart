import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_colors.dart';

/// Modal de advertencia que se muestra antes de activar el modo servidor.
/// Informa al usuario sobre el consumo de batería, la pausa en background
/// y que se generará un PIN automático para proteger el acceso.
///
/// Retorna `true` si el usuario confirmó, `null` si canceló.
class ServerModeWarningDialog extends StatefulWidget {
  const ServerModeWarningDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ServerModeWarningDialog(),
    );
  }

  @override
  State<ServerModeWarningDialog> createState() => _ServerModeWarningDialogState();
}

class _ServerModeWarningDialogState extends State<ServerModeWarningDialog> {
  bool _dontShowAgain = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      backgroundColor: AppColors.bgSecondary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Text('⚠️', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Text(
            'Activar modo servidor',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'El celular actuará como servidor SrvFiles en tu red local.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Text(
            'Tené en cuenta:',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          _bullet('Consume batería más rápido'),
          _bullet('El servidor se pausa si cerrás la app o apagás la pantalla'),
          _bullet('Cualquier dispositivo en tu red podrá acceder a los archivos'),
          const SizedBox(height: 16),

          // Aviso de PIN
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.accentPrimary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.accentPrimary.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_rounded, size: 16, color: AppColors.accentPrimary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Se generará un PIN automático para proteger el acceso',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.accentPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Checkbox "no volver a mostrar"
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => setState(() => _dontShowAgain = !_dontShowAgain),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: _dontShowAgain,
                    onChanged: (v) => setState(() => _dontShowAgain = v ?? false),
                    activeColor: AppColors.accentPrimary,
                    side: const BorderSide(color: AppColors.borderMedium),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'No volver a mostrar este aviso',
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () async {
            if (_dontShowAgain) {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('server_mode_warning_dismissed', true);
            }
            if (context.mounted) Navigator.of(context).pop(true);
          },
          style: FilledButton.styleFrom(backgroundColor: AppColors.accentPrimary),
          child: const Text('Encender'),
        ),
      ],
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Retorna si el usuario marcó "no volver a mostrar".
/// Se expone como extension para acceder desde home_screen.dart.
extension ServerModeWarningResult on bool {
  bool get dismissed => this;
}
