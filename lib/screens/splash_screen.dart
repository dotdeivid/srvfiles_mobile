import 'dart:async';
import 'package:flutter/material.dart';
import '../config/api_config.dart';
import '../theme/app_colors.dart';
import '../utils/server_url.dart';
import '../widgets/gradient_text.dart';
import '../widgets/pulsing_dot.dart';
import '../services/discovery_service.dart';
import '../services/embedded_relay.dart';
import '../services/notification_service.dart';
import '../services/server_history.dart';
import '../services/app_logger.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final _discoveryService = DiscoveryService();
  final _history = const ServerHistory();

  bool _searching = true;
  bool _connecting = false;
  String? _error;
  final _ipController = TextEditingController();
  List<DiscoveredServer> _foundServers = [];

  /// Se incrementa en cada escaneo; un escaneo viejo deja de publicar.
  int _scanId = 0;

  @override
  void initState() {
    super.initState();
    // En el splash nadie usa el relay local: liberarlo.
    unawaited(EmbeddedRelay.shared.stop());
    _scan();
    // Pedir el permiso de notificaciones ya con la UI visible.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(NotificationService().requestPermission());
    });
  }

  @override
  void dispose() {
    _scanId++; // cancela el escaneo en curso
    _ipController.dispose();
    super.dispose();
  }

  void _addServers(Iterable<DiscoveredServer> servers) {
    final existing = _foundServers.map((s) => s.url).toSet();
    final fresh = servers
        .where((s) => s.servesFiles && !existing.contains(s.url))
        .toList();
    if (fresh.isEmpty) return;
    setState(() => _foundServers = [..._foundServers, ...fresh]);
  }

  Future<void> _scan() async {
    final scanId = ++_scanId;
    bool cancelled() => scanId != _scanId || !mounted;
    setState(() {
      _searching = true;
      _error = null;
      _foundServers = [];
    });

    // El último servidor y el barrido de la subred van en paralelo.
    final lastProbe = () async {
      try {
        final lastServer = await _history.getLastServer();
        if (lastServer == null) return;
        AppLogger.instance.debug('[Splash] probing last server: $lastServer');
        final server = await _discoveryService.probe(lastServer);
        if (server != null && !cancelled()) {
          AppLogger.instance.info(
            '[Splash] last server reachable: $lastServer',
          );
          _addServers([server]);
        }
      } catch (e) {
        AppLogger.instance.warn('[Splash] error probing last server: $e');
      }
    }();

    AppLogger.instance.info('[Splash] starting LAN scan');
    try {
      final servers = await _discoveryService.scanLan(isCancelled: cancelled);
      await lastProbe;
      if (cancelled()) return;
      AppLogger.instance.info(
        '[Splash] LAN scan complete: ${servers.length} servers found',
      );
      _addServers(servers);
      setState(() => _searching = false);
    } catch (e) {
      AppLogger.instance.error('[Splash] LAN scan failed', error: e);
      if (!cancelled()) {
        setState(() {
          _searching = false;
          _error =
              'No se pudo escanear la red. ¿Estás conectado a una red wifi?';
        });
      }
    }
  }

  Future<void> _onServerSelected(String serverUrl) async {
    AppLogger.instance.info('[Splash] server selected: $serverUrl');
    await _history.saveLastServer(serverUrl);
    if (mounted) {
      unawaited(
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => HomeScreen(serverUrl: serverUrl)),
        ),
      );
    }
  }

  Future<void> _onSkipServer() async {
    if (mounted) {
      unawaited(
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen(serverUrl: null)),
        ),
      );
    }
  }

  Future<void> _onBeServer() async {
    if (mounted) {
      unawaited(
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) =>
                const HomeScreen(serverUrl: null, autoServerMode: true),
          ),
        ),
      );
    }
  }

  Future<void> _connectManual() async {
    final url = normalizeServerUrl(_ipController.text);
    if (url == null) {
      setState(
        () => _error =
            'Dirección inválida. Ejemplo: 192.168.1.20:$defaultServerPort',
      );
      return;
    }

    AppLogger.instance.info('[Splash] manual connect attempt: $url');
    setState(() {
      _connecting = true;
      _error = null;
    });

    final ok = await _discoveryService.tryConnect(url);
    if (!mounted) return;
    if (ok) {
      await _onServerSelected(url);
    } else {
      AppLogger.instance.warn('[Splash] manual connect failed: $url');
      setState(() {
        _connecting = false;
        _error = 'No se encontró un servidor SrvFiles en $url';
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

              GradientText('SrvFiles', style: theme.textTheme.headlineMedium),

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
                  hintText: '192.168.1.x:$defaultServerPort',
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
                  onPressed: _connecting ? null : _connectManual,
                  child: _connecting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Conectar'),
                ),
              ),

              const SizedBox(height: AppSpacing.md),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _connecting ? null : _onSkipServer,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.borderMedium),
                  ),
                  child: const Text('Envío directo'),
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              Center(
                child: TextButton(
                  onPressed: _connecting ? null : _onBeServer,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textMuted,
                  ),
                  child: const Text(
                    'Usar este dispositivo como servidor',
                    style: TextStyle(fontSize: 13),
                  ),
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
          ..._foundServers.map(
            (server) => _ServerRow(
              server: server,
              onTap: _connecting ? null : () => _onServerSelected(server.url),
            ),
          ),
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
                      Icon(
                        server.isMobile
                            ? Icons.phone_android_rounded
                            : Icons.computer_rounded,
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
