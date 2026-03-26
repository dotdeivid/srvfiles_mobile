import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';

/// Diálogo para ingresar el PIN de un servidor protegido.
/// Retorna el PIN ingresado o `null` si el usuario canceló.
class PinEntryDialog extends StatefulWidget {
  const PinEntryDialog({super.key, this.error, this.onValidate});

  final String? error;

  /// Si se proporciona, el diálogo valida el PIN llamando a esta función.
  /// Retorna null si el PIN es correcto, o un mensaje de error si es incorrecto.
  /// Esto permite mantener el diálogo abierto sin cerrar y reabrir.
  final Future<String?> Function(String pin)? onValidate;

  /// Muestra el diálogo con validación inline (sin cerrar/reabrir en error).
  static Future<String?> show(
    BuildContext context, {
    String? error,
    Future<String?> Function(String pin)? onValidate,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PinEntryDialog(error: error, onValidate: onValidate),
    );
  }

  @override
  State<PinEntryDialog> createState() => _PinEntryDialogState();
}

class _PinEntryDialogState extends State<PinEntryDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _error = widget.error;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _controller.text.trim();
    if (pin.length != 6) {
      setState(() => _error = 'El PIN debe tener 6 dígitos');
      return;
    }

    if (widget.onValidate != null) {
      setState(() => _submitting = true);
      final errorMsg = await widget.onValidate!(pin);
      if (!mounted) return;
      setState(() => _submitting = false);
      if (errorMsg != null) {
        setState(() => _error = errorMsg);
        // Keep dialog open, just show error — no keyboard flicker
        return;
      }
    }

    if (mounted) Navigator.of(context).pop(pin);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      backgroundColor: AppColors.bgSecondary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.lock_rounded, size: 20, color: AppColors.accentPrimary),
          const SizedBox(width: 8),
          Text(
            'Servidor protegido',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ingresá el PIN para conectarte al servidor.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              letterSpacing: 8,
              fontFamily: 'monospace',
            ),
            decoration: InputDecoration(
              hintText: '······',
              hintStyle: TextStyle(
                fontSize: 24,
                letterSpacing: 8,
                color: AppColors.textMuted.withValues(alpha: 0.4),
              ),
              filled: true,
              fillColor: AppColors.bgPrimary,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.borderMedium),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.borderMedium),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.accentPrimary),
              ),
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.error_outline, size: 14, color: AppColors.danger),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.danger, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(null),
          child: const Text('Cancelar'),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (_, value, _) {
            return FilledButton(
              onPressed: (value.text.length == 6 && !_submitting) ? _submit : null,
              style: FilledButton.styleFrom(backgroundColor: AppColors.accentPrimary),
              child: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Conectar'),
            );
          },
        ),
      ],
    );
  }
}
