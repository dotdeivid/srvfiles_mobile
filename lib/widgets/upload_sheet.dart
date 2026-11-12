import 'package:flutter/material.dart';
import '../features/files/files_controller.dart' show StagedFile;
import '../theme/app_colors.dart';
import '../utils/format.dart';
import '../utils/file_icons.dart';

/// BottomSheet para staging de archivos antes de subir.
/// Muestra la lista de archivos seleccionados, permite remover
/// individuales, limpiar todos, y subir con barra de progreso.
///
/// [maxFileSizeMb] null o 0 significa "sin límite". Si algún archivo lo
/// supera, el botón de subir queda deshabilitado.
class UploadSheet extends StatelessWidget {
  const UploadSheet({
    super.key,
    required this.files,
    required this.uploading,
    required this.uploadProgress,
    required this.onRemove,
    required this.onClearAll,
    required this.onUpload,
    this.onCancel,
    this.maxFileSizeMb,
  });

  final List<StagedFile> files;
  final bool uploading;
  final double uploadProgress;
  final void Function(int index) onRemove;
  final VoidCallback onClearAll;
  final VoidCallback onUpload;
  final VoidCallback? onCancel;
  final int? maxFileSizeMb;

  int? get _maxBytes =>
      (maxFileSizeMb ?? 0) > 0 ? maxFileSizeMb! * 1024 * 1024 : null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalSize = files.fold<int>(0, (sum, f) => sum + f.size);
    final maxBytes = _maxBytes;
    final anyOverLimit = maxBytes != null && files.any((f) => f.size > maxBytes);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: const BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        border: Border(
          top: BorderSide(color: AppColors.borderMedium),
          left: BorderSide(color: AppColors.borderMedium),
          right: BorderSide(color: AppColors.borderMedium),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.textMuted,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${files.length} archivo${files.length > 1 ? 's' : ''} seleccionado${files.length > 1 ? 's' : ''}',
                style: theme.textTheme.titleSmall,
              ),
              if (!uploading)
                TextButton(
                  onPressed: onClearAll,
                  child: const Text('Limpiar'),
                ),
            ],
          ),

          const SizedBox(height: AppSpacing.sm),

          // Lista de archivos
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: files.length,
              itemBuilder: (context, index) {
                final file = files[index];
                final overLimit = maxBytes != null && file.size > maxBytes;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Text(getFileIcon(file.name), style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              file.name,
                              style: TextStyle(
                                fontSize: 13,
                                color: overLimit
                                    ? AppColors.danger
                                    : AppColors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              overLimit
                                  ? '${formatBytes(file.size)} — excede el límite de $maxFileSizeMb MB'
                                  : formatBytes(file.size),
                              style: TextStyle(
                                fontSize: 11,
                                color: overLimit
                                    ? AppColors.danger
                                    : AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!uploading)
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          color: AppColors.textMuted,
                          tooltip: 'Quitar ${file.name}',
                          onPressed: () => onRemove(index),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 40,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: AppSpacing.sm),

          // Barra de progreso (durante upload)
          if (uploading) ...[
            ClipRRect(
              borderRadius: AppRadius.borderSm,
              child: SizedBox(
                height: 8,
                child: Stack(
                  children: [
                    Container(color: AppColors.bgGlass),
                    FractionallySizedBox(
                      widthFactor: uploadProgress.clamp(0.0, 1.0),
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
            const SizedBox(height: AppSpacing.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(uploadProgress * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontFamily: 'monospace',
                  ),
                ),
                if (onCancel != null)
                  TextButton(
                    onPressed: onCancel,
                    style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                    child: const Text('Cancelar'),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
          ],

          // Botón subir
          if (!uploading)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: anyOverLimit || files.isEmpty ? null : onUpload,
                icon: const Icon(Icons.upload_rounded, size: 18),
                label: Text(
                  anyOverLimit
                      ? 'Quitá los archivos que exceden el límite'
                      : 'Subir ${files.length > 1 ? '${files.length} archivos' : 'archivo'}'
                          ' (${formatBytes(totalSize)})',
                ),
              ),
            ),
        ],
      ),
    );
  }
}
