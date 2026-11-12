import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../models/transfer_request.dart';
import '../services/e2e_service.dart';
import '../utils/format.dart';
import '../utils/file_icons.dart';

/// Diálogo modal que aparece cuando otro dispositivo quiere enviarnos un archivo.
/// Replica IncomingTransferModal.tsx del frontend web.
///
/// Muestra el código de verificación E2E ([sas]). "Aceptar" solo se habilita
/// cuando el usuario confirma que coincide con el que ve el emisor: así se
/// detecta un intermediario que haya cambiado las claves.
class IncomingTransferDialog extends StatefulWidget {
  const IncomingTransferDialog({
    super.key,
    required this.request,
    required this.sas,
    required this.onAccept,
    required this.onReject,
  });

  final IncomingTransferRequest request;
  final String sas;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  /// Muestra el diálogo y retorna true si se aceptó, false si se rechazó.
  ///
  /// Si [dismissed] se completa antes de que el usuario responda (el emisor
  /// canceló o venció el plazo), el diálogo se cierra solo y retorna null.
  static Future<bool?> show(
    BuildContext context,
    IncomingTransferRequest request, {
    required String sas,
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
          sas: sas,
          onAccept: () => close(ctx, true),
          onReject: () => close(ctx, false),
        );
      },
    ).whenComplete(() => open = false);
  }

  @override
  State<IncomingTransferDialog> createState() => _IncomingTransferDialogState();
}

class _IncomingTransferDialogState extends State<IncomingTransferDialog> {
  bool _confirmed = false;

  IncomingTransferRequest get request => widget.request;

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

          // Código de verificación E2E
          Semantics(
            label: 'Código de verificación ${widget.sas.split('').join(' ')}',
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.accentPrimary.withValues(alpha: 0.08),
                borderRadius: AppRadius.borderSm,
                border: Border.all(color: AppColors.accentPrimary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_user_rounded, size: 18, color: AppColors.accentPrimary),
                  const SizedBox(width: AppSpacing.sm),
                  const Expanded(
                    child: Text('Código de verificación',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  ),
                  Text(
                    E2ESession.formatSas(widget.sas),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          CheckboxListTile(
            value: _confirmed,
            onChanged: (v) => setState(() => _confirmed = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            title: Text(
              'El código coincide con el que se ve en ${request.fromName}',
              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
            ),
          ),

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
              widget.onReject();
            },
            child: const Text('Rechazar'),
          ),
        ),
        Semantics(
          button: true,
          label: 'Aceptar transferencia',
          child: ElevatedButton(
            onPressed: _confirmed
                ? () {
                    HapticFeedback.mediumImpact();
                    widget.onAccept();
                  }
                : null,
            child: const Text('Aceptar'),
          ),
        ),
      ],
    );
  }
}
