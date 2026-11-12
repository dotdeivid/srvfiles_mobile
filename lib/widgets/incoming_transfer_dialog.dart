import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../models/transfer_request.dart';
import '../utils/format.dart';
import '../utils/file_icons.dart';

/// Diálogo modal que aparece cuando otro dispositivo quiere enviarnos un archivo.
/// Replica IncomingTransferModal.tsx del frontend web.
class IncomingTransferDialog extends StatelessWidget {
  const IncomingTransferDialog({
    super.key,
    required this.request,
    required this.onAccept,
    required this.onReject,
  });

  final IncomingTransferRequest request;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  /// Muestra el diálogo y retorna true si se aceptó, false si se rechazó.
  ///
  /// Si [dismissed] se completa antes de que el usuario responda (el emisor
  /// canceló o venció el plazo), el diálogo se cierra solo y retorna null.
  static Future<bool?> show(
    BuildContext context,
    IncomingTransferRequest request, {
    Future<void>? dismissed,
  }) {
    var open = true;
    BuildContext? dialogContext;
    void close(BuildContext ctx, bool? value) {
      if (!open) return;
      open = false;
      Navigator.of(ctx).pop(value);
    }

    var dismissedEarly = false;
    dismissed?.then((_) {
      final ctx = dialogContext;
      if (ctx != null && ctx.mounted) {
        close(ctx, null);
      } else {
        dismissedEarly = true;
      }
    });

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogContext = ctx;
        if (dismissedEarly) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (ctx.mounted) close(ctx, null);
          });
        }
        return IncomingTransferDialog(
          request: request,
          onAccept: () => close(ctx, true),
          onReject: () => close(ctx, false),
        );
      },
    ).whenComplete(() => open = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      backgroundColor: AppColors.bgSecondary,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.borderLg,
        side: const BorderSide(color: AppColors.borderMedium),
      ),
      title: Row(
        children: [
          const Icon(
            Icons.download_rounded,
            color: AppColors.accentPrimary,
            size: 22,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text('Archivo entrante', style: theme.textTheme.titleSmall),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Remitente
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.bgGlass,
              borderRadius: AppRadius.borderSm,
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.devices_rounded,
                  color: AppColors.textSecondary,
                  size: 18,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    request.fromName,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // Archivo
          Row(
            children: [
              Text(
                getFileIcon(request.fileName),
                style: const TextStyle(fontSize: 32),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.fileName,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatBytes(request.fileSize),
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.md),

          Text(
            '¿Querés recibir este archivo?',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
      actions: [
        Semantics(
          button: true,
          label: 'Rechazar transferencia',
          child: TextButton(
            onPressed: () {
              HapticFeedback.mediumImpact();
              onReject();
            },
            child: const Text('Rechazar'),
          ),
        ),
        Semantics(
          button: true,
          label: 'Aceptar transferencia',
          child: ElevatedButton(
            onPressed: () {
              HapticFeedback.mediumImpact();
              onAccept();
            },
            child: const Text('Aceptar'),
          ),
        ),
      ],
    );
  }
}
