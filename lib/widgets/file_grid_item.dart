import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../widgets/glass_card.dart';
import '../models/file_info.dart';
import '../utils/file_icons.dart';
import '../utils/format.dart';
import '../utils/file_type_helper.dart';

/// Tarjeta de archivo en modo grid. Replica el file-card del FileItem.tsx web.
/// Incluye long-press para menú contextual.
class FileGridItem extends StatelessWidget {
  const FileGridItem({
    super.key,
    required this.file,
    required this.onDownload,
    required this.onShare,
    this.onPreview,
    this.onCopyLink,
    this.onDelete,
  });

  final FileInfo file;
  final VoidCallback onDownload;
  final VoidCallback onShare;
  /// Called when the user taps the eye icon. Null hides the button.
  final VoidCallback? onPreview;
  final VoidCallback? onCopyLink;
  final VoidCallback? onDelete;

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
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.textMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
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
            ListTile(
              leading: const Icon(Icons.download_rounded,
                  color: AppColors.textSecondary, size: 22),
              title: const Text('Descargar',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.of(ctx).pop();
                onDownload();
              },
              dense: true,
            ),
            ListTile(
              leading: const Icon(Icons.share_rounded,
                  color: AppColors.textSecondary, size: 22),
              title: const Text('Compartir',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.of(ctx).pop();
                onShare();
              },
              dense: true,
            ),
            if (onCopyLink != null)
              ListTile(
                leading: const Icon(Icons.link_rounded,
                    color: AppColors.textSecondary, size: 22),
                title: const Text('Copiar enlace',
                    style:
                        TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(ctx).pop();
                  onCopyLink!();
                },
                dense: true,
              ),
            if (onDelete != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: AppColors.danger, size: 22),
                title: const Text('Eliminar',
                    style: TextStyle(color: AppColors.danger, fontSize: 14)),
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(ctx).pop();
                  onDelete!();
                },
                dense: true,
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${file.name}, ${formatBytes(file.size)}',
      child: GestureDetector(
        onLongPress: () => _showContextMenu(context),
        child: GlassCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Emoji grande
              Text(
                getFileIcon(file.name),
                style: const TextStyle(fontSize: 36),
              ),
              const SizedBox(height: AppSpacing.sm),

              // Nombre
              Text(
                file.name,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),

              // Tamaño
              Text(
                formatBytes(file.size),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),

              const Spacer(),

              // Acciones
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (onPreview != null && FileTypeHelper.canPreview(file.name))
                    Semantics(
                      button: true,
                      label: 'Vista previa ${file.name}',
                      child: IconButton(
                        icon: const Icon(Icons.visibility_rounded, size: 18),
                        color: AppColors.textAccent,
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          onPreview!();
                        },
                        tooltip: 'Vista previa',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      ),
                    ),
                  Semantics(
                    button: true,
                    label: 'Descargar ${file.name}',
                    child: IconButton(
                      icon: const Icon(Icons.download_rounded, size: 18),
                      color: AppColors.textSecondary,
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        onDownload();
                      },
                      tooltip: 'Descargar',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Compartir ${file.name}',
                    child: IconButton(
                      icon: const Icon(Icons.share_rounded, size: 18),
                      color: AppColors.textSecondary,
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        onShare();
                      },
                      tooltip: 'Compartir',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
