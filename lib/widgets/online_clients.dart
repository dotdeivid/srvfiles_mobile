import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../models/transfer_client.dart';
import '../models/active_transfer.dart';
import '../utils/format.dart';
import 'pulsing_dot.dart';

/// Lista de dispositivos conectados con botón "Enviar" y progreso de transferencia.
/// Replica OnlineClients.tsx del frontend web.
class OnlineClients extends StatelessWidget {
  const OnlineClients({
    super.key,
    required this.clients,
    required this.myClientId,
    required this.activeTransfer,
    required this.onSendFile,
    required this.onCancelTransfer,
    this.onViewServer,
  });

  final List<TransferClient> clients;
  final String? myClientId;
  final ActiveTransfer? activeTransfer;
  final void Function(String clientId, String peerName) onSendFile;
  final VoidCallback onCancelTransfer;
  final void Function(String serverUrl)? onViewServer;

  @override
  Widget build(BuildContext context) {
    final others = clients.where((c) => c.clientId != myClientId).toList();

    if (others.isEmpty) return const SizedBox.shrink();

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Container(
        margin: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm,
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: AppRadius.borderMd,
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.xs,
                bottom: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  const PulsingDot(size: 8),
                  const SizedBox(width: AppSpacing.sm),
                  Semantics(
                    label: '${others.length} dispositivos conectados',
                    child: Text(
                      'Dispositivos conectados',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Lista de peers
            ...others.map((client) => _ClientRow(
                  client: client,
                  activeTransfer: activeTransfer,
                  onSendFile: onSendFile,
                  onCancel: onCancelTransfer,
                  onViewServer: onViewServer,
                )),
          ],
        ),
      ),
    );
  }
}

// ─── Fila de un dispositivo ──────────────────────────────────────────

class _ClientRow extends StatelessWidget {
  const _ClientRow({
    required this.client,
    required this.activeTransfer,
    required this.onSendFile,
    required this.onCancel,
    this.onViewServer,
  });

  final TransferClient client;
  final ActiveTransfer? activeTransfer;
  final void Function(String clientId, String peerName) onSendFile;
  final VoidCallback onCancel;
  final void Function(String serverUrl)? onViewServer;

  @override
  Widget build(BuildContext context) {
    final isThisRow = activeTransfer?.peerId == client.clientId;
    final isOtherRow = activeTransfer != null && !isThisRow;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: isThisRow ? AppColors.bgGlass : Colors.transparent,
        borderRadius: AppRadius.borderSm,
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Punto verde
              const PulsingDot(size: 8),
              const SizedBox(width: AppSpacing.sm),

              // Nombre + IP
              Expanded(
                child: Semantics(
                  label: '${client.appName}, ${client.isMobile ? 'móvil' : 'escritorio'}, IP ${client.ip}',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            client.isMobile
                                ? Icons.phone_android
                                : client.isServer
                                    ? Icons.computer_rounded
                                    : Icons.language,
                            size: 14,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              client.appName,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (client.isServer) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.accentPrimary.withValues(alpha: 0.12),
                                border: Border.all(color: AppColors.accentPrimary.withValues(alpha: 0.25)),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'srv',
                                style: TextStyle(
                                  color: AppColors.accentPrimary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        client.ip,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Botón enviar o cancelar
              if (isThisRow && activeTransfer != null)
                Semantics(
                  button: true,
                  label: 'Cancelar transferencia',
                  child: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    color: AppColors.textMuted,
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      onCancel();
                    },
                    tooltip: 'Cancelar transferencia',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (client.isServer && onViewServer != null)
                      Semantics(
                        button: true,
                        label: 'Ver archivos de ${client.appName}',
                        child: TextButton.icon(
                          onPressed: isOtherRow
                              ? null
                              : () {
                                  HapticFeedback.lightImpact();
                                  onViewServer!('http://${client.ip}:3001');
                                },
                          icon: const Icon(Icons.folder_open_rounded, size: 14),
                          label: const Text('Ver', style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: 4,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            foregroundColor: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    Semantics(
                      button: true,
                      label: 'Enviar archivo a ${client.appName}',
                      child: TextButton.icon(
                        onPressed: isOtherRow
                            ? null
                            : () {
                                HapticFeedback.lightImpact();
                                onSendFile(client.clientId, client.appName);
                              },
                        icon: const Icon(Icons.upload_rounded, size: 14),
                        label: const Text('Enviar', style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // Progreso de transferencia (solo en esta fila)
          if (isThisRow && activeTransfer != null) ...[
            const SizedBox(height: AppSpacing.xs),
            if (activeTransfer!.waiting)
              const Padding(
                padding: EdgeInsets.only(left: 20),
                child: Text(
                  'Esperando respuesta...',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else ...[
              // Barra de progreso animada
              Padding(
                padding: const EdgeInsets.only(left: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: AppRadius.borderSm,
                      child: SizedBox(
                        height: 6,
                        child: Stack(
                          children: [
                            Container(color: AppColors.bgGlass),
                            AnimatedFractionallySizedBox(
                              duration: const Duration(milliseconds: 200),
                              widthFactor: (activeTransfer!.progress / 100)
                                  .clamp(0.0, 1.0),
                              child: Container(
                                decoration: const BoxDecoration(
                                  gradient: AppColors.accentGradient,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          '${activeTransfer!.progress}%',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          formatBytes(activeTransfer!.fileSize),
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
