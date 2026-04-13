import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../models/file_info.dart';
import '../utils/file_icons.dart';
import '../utils/format.dart';
import '../utils/file_type_helper.dart';

/// Fila de archivo en modo lista. Replica el file-row del FileItem.tsx web.
/// Incluye long-press para menú contextual y animación de entrada.
class FileListItem extends StatelessWidget {
  const FileListItem({
    super.key,
    required this.file,
    required this.onDownload,
    this.onPreview,
    this.onShare,
    this.onCopyLink,
    this.onDelete,
    this.downloadIcon = Icons.download_rounded,
    this.downloadTooltip = 'Descargar',
  });

  final FileInfo file;
  final VoidCallback onDownload;
  /// Called when the user taps the eye icon. Null hides the button.
  final VoidCallback? onPreview;
  final VoidCallback? onShare;
  final VoidCallback? onCopyLink;
  final VoidCallback? onDelete;
  /// Ícono del botón de acción principal (descarga/abrir).
  final IconData downloadIcon;
  final String downloadTooltip;

  void _showContextMenu(BuildContext context) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.textMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // File info header
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Text(getFileIcon(file.name),
                      style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          file.name,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          formatBytes(file.size),
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
            ),
            const Divider(color: AppColors.borderSubtle, height: 1),
            _ContextMenuItem(
              icon: Icons.download_rounded,
              label: 'Descargar',
              onTap: () {
                Navigator.of(ctx).pop();
                onDownload();
              },
            ),
            if (onShare != null)
              _ContextMenuItem(
                icon: Icons.share_rounded,
                label: 'Compartir',
                onTap: () {
                  Navigator.of(ctx).pop();
                  onShare!();
                },
              ),
            if (onCopyLink != null)
              _ContextMenuItem(
                icon: Icons.link_rounded,
                label: 'Copiar enlace',
                onTap: () {
                  Navigator.of(ctx).pop();
                  onCopyLink!();
                },
              ),
            if (onDelete != null)
              _ContextMenuItem(
                icon: Icons.delete_outline_rounded,
                label: 'Eliminar',
                onTap: () {
                  Navigator.of(ctx).pop();
                  onDelete!();
                },
                destructive: true,
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Semantics(
      label: '${file.name}, ${formatBytes(file.size)}',
      child: InkWell(
        onLongPress: () => _showContextMenu(context),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.borderSubtle),
            ),
          ),
          child: Row(
            children: [
              // Emoji icono
              Text(
                getFileIcon(file.name),
                style: const TextStyle(fontSize: 22),
              ),
              const SizedBox(width: AppSpacing.sm),

              // Nombre + tamaño
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatBytes(file.size),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),

              // Acciones
              if (onPreview != null && FileTypeHelper.canPreview(file.name))
                Semantics(
                  button: true,
                  label: 'Vista previa ${file.name}',
                  child: IconButton(
                    icon: const Icon(Icons.visibility_rounded, size: 20),
                    color: AppColors.textAccent,
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      onPreview!();
                    },
                    tooltip: 'Vista previa',
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              Semantics(
                button: true,
                label: '$downloadTooltip ${file.name}',
                child: IconButton(
                  icon: Icon(downloadIcon, size: 20),
                  color: AppColors.textSecondary,
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    onDownload();
                  },
                  tooltip: downloadTooltip,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              if (onShare != null)
                Semantics(
                  button: true,
                  label: 'Compartir ${file.name}',
                  child: IconButton(
                    icon: const Icon(Icons.share_rounded, size: 20),
                    color: AppColors.textSecondary,
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      onShare!();
                    },
                    tooltip: 'Compartir',
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              if (onDelete != null)
                Semantics(
                  button: true,
                  label: 'Eliminar ${file.name}',
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                    color: AppColors.danger,
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      onDelete!();
                    },
                    tooltip: 'Eliminar',
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _ContextMenuItem extends StatelessWidget {
  const _ContextMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.danger : AppColors.textSecondary;
    final textColor = destructive ? AppColors.danger : AppColors.textPrimary;
    return ListTile(
      leading: Icon(icon, color: color, size: 22),
      title: Text(
        label,
        style: TextStyle(color: textColor, fontSize: 14),
      ),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      dense: true,
    );
  }
}
