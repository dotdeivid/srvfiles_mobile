import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_colors.dart';
import '../widgets/gradient_text.dart';
import '../services/discovery_service.dart';
import '../services/device_name_service.dart';
import '../widgets/name_dialog.dart';
import 'home_screen.dart';

const String _lastServerKey = 'srvfiles-last-server';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final _discoveryService = DiscoveryService();
  final _deviceNameService = DeviceNameService();

  bool _searching = true;
  bool _showOptions = false;
  String? _error;
  final _ipController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _autoConnect();
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _autoConnect() async {
    setState(() {
      _searching = true;
      _error = null;
    });

    // Mostrar opciones después de 2 segundos para que el usuario pueda
    // escribir manualmente mientras el scan sigue en background
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _searching) {
        setState(() => _showOptions = true);
      }
    });

    // 1. Intentar con el último servidor guardado
    final prefs = await SharedPreferences.getInstance();
    final lastServer = prefs.getString(_lastServerKey);

    if (lastServer != null) {
      final ok = await _discoveryService.tryConnect(lastServer);
      if (ok && mounted) {
        await _onServerFound(lastServer);
        return;
      }
    }

    // 2. Scan directo de la subred LAN
    debugPrint('[Splash] Iniciando scan LAN...');
    final servers = await _discoveryService.scanLan();
    if (servers.isNotEmpty && mounted) {
      debugPrint('[Splash] Servidor encontrado: ${servers.first.url}');
      await _onServerFound(servers.first.url);
      return;
    }

    debugPrint('[Splash] No se encontró servidor en la LAN');
    if (mounted) {
      setState(() {
        _searching = false;
        _showOptions = true;
      });
    }
  }

  Future<void> _saveLastServer(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastServerKey, url);
  }

  Future<void> _ensureDeviceName() async {
    final isFirst = await _deviceNameService.isFirstLaunch();
    if (isFirst && mounted) {
      final defaultName = _deviceNameService.generateRandomName();
      final chosenName = await NameDialog.show(context, defaultName);
      await _deviceNameService.saveName(chosenName ?? defaultName);
    }
  }

  Future<void> _onServerFound(String serverUrl) async {
    await _saveLastServer(serverUrl);
    await _ensureDeviceName();

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HomeScreen(serverUrl: serverUrl),
        ),
      );
    }
  }

  Future<void> _onSkipServer() async {
    await _ensureDeviceName();

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const HomeScreen(serverUrl: null),
        ),
      );
    }
  }

  Future<void> _connectManual() async {
    final input = _ipController.text.trim();
    if (input.isEmpty) return;

    // Agregar http:// y puerto si no los tiene
    String url = input;
    if (!url.startsWith('http')) {
      url = 'http://$url';
    }
    if (!RegExp(r':\d+$').hasMatch(url)) {
      url = '$url:3001';
    }

    setState(() {
      _searching = true;
      _error = null;
    });

    final ok = await _discoveryService.tryConnect(url);
    if (ok && mounted) {
      await _onServerFound(url);
    } else if (mounted) {
      setState(() {
        _searching = false;
        _error = 'No se pudo conectar a $url';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ─── Logo con Hero ─────────────────────────────
                Hero(
                  tag: 'srvfiles-logo',
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.bgSecondary,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.borderMedium),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.folder_shared_rounded,
                        color: AppColors.accentPrimary,
                        size: 32,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.md),

                GradientText(
                  'SrvFiles',
                  style: theme.textTheme.headlineMedium,
                ),

                const SizedBox(height: AppSpacing.xxl),

                // ─── Spinner ───────────────────────────────────
                if (_searching) ...[
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.accentPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Buscando servidor...',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],

                // ─── Error ─────────────────────────────────────
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.danger,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],

                // ─── Opciones cuando no se encuentra servidor ──
                if (_showOptions) ...[
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Ingresá la IP del servidor',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Abrí SrvFiles en tu PC y copiá la dirección IP que aparece.',
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _ipController,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _connectManual(),
                    decoration: const InputDecoration(
                      hintText: '192.168.1.x:3001',
                      prefixIcon: Icon(
                        Icons.lan_rounded,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _searching ? null : _connectManual,
                      child: const Text('Conectar'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _searching ? null : _onSkipServer,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.borderMedium),
                      ),
                      child: const Text('Omitir servidor'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
