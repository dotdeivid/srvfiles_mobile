import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Barra de búsqueda glassmórfica con clear button.
/// Replica el search input del FileList.tsx web.
class FileSearchBar extends StatelessWidget {
  const FileSearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(
        fontSize: 14,
        color: AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: 'Buscar archivos...',
        prefixIcon: const Icon(Icons.search, color: AppColors.textMuted, size: 20),
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close, size: 18, color: AppColors.textMuted),
                onPressed: () {
                  controller.clear();
                  onClear?.call();
                },
              )
            : null,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }
}
