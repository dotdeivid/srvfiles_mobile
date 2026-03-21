import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Diálogo para configurar el nombre del dispositivo (primera vez).
/// Replica NameModal.tsx del frontend web.
class NameDialog extends StatefulWidget {
  const NameDialog({
    super.key,
    required this.defaultName,
  });

  final String defaultName;

  /// Muestra el diálogo y retorna el nombre elegido, o null si se omite.
  static Future<String?> show(BuildContext context, String defaultName) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => NameDialog(defaultName: defaultName),
    );
  }

  @override
  State<NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<NameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.defaultName);
    // Seleccionar todo el texto al abrir
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(
        '¿Cómo querés que te vean?',
        style: theme.dialogTheme.titleTextStyle,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Este nombre aparece cuando otros dispositivos te ven en la red.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _controller,
            maxLength: 32,
            autofocus: true,
            style: theme.textTheme.bodyLarge,
            decoration: const InputDecoration(
              hintText: 'Ej: Mi Celular',
              counterText: '',
            ),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Omitir'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text('Guardar'),
        ),
      ],
    );
  }

  void _save() {
    Navigator.of(context).pop(_controller.text);
  }
}
