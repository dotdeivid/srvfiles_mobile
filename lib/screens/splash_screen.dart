import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_colors.dart';
import '../widgets/gradient_text.dart';
import '../widgets/pulsing_dot.dart';
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
  String? _error;
  final _ipController = TextEditingController();
  List<DiscoveredServer> _foundServers = [];

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() {
      _searching = true;
      _error = null;
      _foundServers = [];
    });

    // 1. Intentar con el último servidor guardado para mostrarlo rápido
    final prefs = await SharedPreferences.getInstance();
    final lastServer = prefs.getString(_lastServerKey);
    if (lastServer != null) {
      final server = await _discoveryService.probe(lastServer);
      if (server != null && mounted) {
        setState(() => _foundServers = [server]);
      }
    }

    // 2. Scan completo de la subred LAN
    debugPrint('[Splash] Iniciando scan LAN...');
    final servers = await _discoveryService.scanLan();
    debugPrint('[Splash] Scan completado: ${servers.length} servidores');

    if (mounted) {
      final existing = _foundServers.map((s) => s.url).toSet();
      final merged = [
        ..._foundServers,
        ...servers.where((s) => !existing.contains(s.url)),
      ];
      setState(() {
        _foundServers = merged;
        _searching = false;
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

  Future<void> _onServerSelected(String serverUrl) async {
    await _saveLastServer(serverUrl);
    await _ensureDeviceName();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => HomeScreen(serverUrl: serverUrl)),
      );
    }
  }

  Future<void> _onSkipServer() async {
    await _ensureDeviceName();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen(serverUrl: null)),
      );
    }
  }

  Future<void> _connectManual() async {
    final input = _ipController.text.trim();
    if (input.isEmpty) return;

    String url = input;
    if (!url.startsWith('http')) url = 'http://$url';
    if (!RegExp(r':\d+$').hasMatch(url)) url = '$url:3001';

    setState(() {
      _searching = true;
      _error = null;
    });

    final ok = await _discoveryService.tryConnect(url);
    if (ok && mounted) {
      await _onServerSelected(url);
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ─── Logo ──────────────────────────────────────────
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

              // ─── Lista de servidores encontrados ───────────────
              if (_foundServers.isNotEmpty) ...[
                _buildServerList(theme),
                const SizedBox(height: AppSpacing.xl),
              ],

              // ─── Campo manual ──────────────────────────────────
              // "Buscando..." mientras escanea, o el label normal al terminar
              Align(
                alignment: Alignment.centerLeft,
                child: _searching
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: AppColors.accentPrimary,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            'Buscando servidores...',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        'Ingresá la IP del servidor',
                        style: theme.textTheme.titleSmall,
                      ),
              ),

              const SizedBox(height: AppSpacing.sm),

              if (!_searching && _foundServers.isEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Abrí SrvFiles en tu PC y copiá la dirección IP que aparece.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),

              const SizedBox(height: AppSpacing.md),

              // ─── Error ─────────────────────────────────────────
              if (_error != null) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.danger,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],

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
          ),
        ),
      ),
    );
  }

  Widget _buildServerList(ThemeData theme) {
    return Container(
      width: double.infinity,
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
                Text(
                  'Servidores encontrados',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // Filas de servidores
          ..._foundServers.map((server) => _ServerRow(
                server: server,
                onTap: _searching ? null : () => _onServerSelected(server.url),
              )),
        ],
      ),
    );
  }
}

// ─── Fila de un servidor descubierto ─────────────────────────────────

class _ServerRow extends StatelessWidget {
  const _ServerRow({required this.server, required this.onTap});

  final DiscoveredServer server;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.borderSm,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          children: [
            const PulsingDot(size: 8),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.computer_rounded,
                        size: 14,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          server.appName,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    server.ip,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.link_rounded, size: 14),
              label: const Text('Conectar', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 4,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
