import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../utils/format.dart';
import '../utils/file_icons.dart';

/// BottomSheet para staging de archivos antes de subir.
/// Muestra la lista de archivos seleccionados, permite remover
/// individuales, limpiar todos, y subir con barra de progreso.
class UploadSheet extends StatelessWidget {
  const UploadSheet({
    super.key,
    required this.files,
    required this.uploading,
    required this.uploadProgress,
    required this.onRemove,
    required this.onClearAll,
    required this.onUpload,
    this.maxFileSizeMb,
  });

  final List<File> files;
  final bool uploading;
  final double uploadProgress;
  final void Function(int index) onRemove;
  final VoidCallback onClearAll;
  final VoidCallback onUpload;
  final int? maxFileSizeMb;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalSize = files.fold<int>(0, (sum, f) => sum + f.lengthSync());

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
                final name = file.path.split('/').last;
                final size = file.lengthSync();
                final overLimit = maxFileSizeMb != null &&
                    size > maxFileSizeMb! * 1024 * 1024;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Text(getFileIcon(name), style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
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
                                  ? '${formatBytes(size)} — excede el límite'
                                  : formatBytes(size),
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
                          onPressed: () => onRemove(index),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
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
            Text(
              '${(uploadProgress * 100).round()}%',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],

          // Botón subir
          if (!uploading)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onUpload,
                icon: const Icon(Icons.upload_rounded, size: 18),
                label: Text(
                  'Subir ${files.length > 1 ? '${files.length} archivos' : 'archivo'}'
                  ' (${formatBytes(totalSize)})',
                ),
              ),
            ),
        ],
      ),
    );
  }
}
