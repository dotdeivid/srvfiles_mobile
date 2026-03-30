import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/discovery_service.dart';
import '../../theme/app_colors.dart';

/// Bottom sheet that lets the user view the current server info, scan for
/// other SrvFiles servers on the LAN, or connect to one manually by IP.
class ConnectSheet extends StatefulWidget {
  const ConnectSheet({
    super.key,
    required this.onConnect,
    required this.onDisconnect,
    this.currentServerUrl,
    this.webUrl,
    this.relayIp,
    this.relayPort = 3001,
    this.relayPin,
    this.isRelayServer = false,
    this.isRelayRunning = false,
  });

  final void Function(String url) onConnect;
  final VoidCallback onDisconnect;
  final String? currentServerUrl;
  final String? webUrl;
  final String? relayIp;
  final int relayPort;
  final String? relayPin;
  final bool isRelayServer;
  final bool isRelayRunning;

  @override
  State<ConnectSheet> createState() => _ConnectSheetState();
}

class _ConnectSheetState extends State<ConnectSheet> {
  final _discovery = DiscoveryService();
  final _ipController = TextEditingController();

  bool _scanning = true;
  List<DiscoveredServer> _servers = [];

  @override
  void initState() {
    super.initState();
    if (widget.currentServerUrl != null || !widget.isRelayServer) {
      _scan();
    } else {
      _scanning = false;
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _servers = [];
    });
    final results = await _discovery.scanLan();
    if (mounted) {
      setState(() {
        _servers = results;
        _scanning = false;
      });
    }
  }

  void _connectTo(String url) {
    Navigator.of(context).pop();
    widget.onConnect(url);
  }

  void _connectManual() {
    final input = _ipController.text.trim();
    if (input.isEmpty) return;
    String url = input;
    if (!url.startsWith('http')) url = 'http://$url';
    if (!RegExp(r':\d+$').hasMatch(url)) url = '$url:3001';
    _connectTo(url);
  }

  // ─── URL row with copy button ─────────────────────────────────────

  Widget _buildUrlRow(String label, IconData icon, String address) {
    return Row(
      children: [
        Icon(icon, color: AppColors.textMuted.withValues(alpha: 0.6), size: 14),
        const SizedBox(width: AppSpacing.xs),
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: TextStyle(
              color: AppColors.textMuted.withValues(alpha: 0.8),
              fontSize: 10,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
        ),
        Expanded(
          child: Text(
            address,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: address));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Copiado: $address'),
                duration: const Duration(seconds: 2),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.accentPrimary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(Icons.copy_rounded,
                color: AppColors.textMuted.withValues(alpha: 0.7), size: 14),
          ),
        ),
      ],
    );
  }

  // ─── Server info card ─────────────────────────────────────────────

  Widget _buildServerInfoCard({
    required String address,
    required String badgeText,
    required IconData icon,
    String? webAddress,
    String? pin,
    String? description,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.accentPrimary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.accentPrimary.withValues(alpha: 0.15),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Badge
            Row(
              children: [
                Icon(icon, color: AppColors.accentPrimary, size: 18),
                const SizedBox(width: AppSpacing.sm),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.accentPrimary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badgeText,
                    style: const TextStyle(
                      color: AppColors.accentPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // URLs with copy button
            _buildUrlRow('Servidor', Icons.dns_rounded, address),
            if (webAddress != null && webAddress != address) ...[
              const SizedBox(height: 6),
              _buildUrlRow('Web', Icons.language_rounded, webAddress),
            ],
            if (pin != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.lock_rounded,
                      color: AppColors.textMuted.withValues(alpha: 0.6),
                      size: 14),
                  const SizedBox(width: AppSpacing.xs),
                  SizedBox(
                    width: 52,
                    child: Text(
                      'PIN',
                      style: TextStyle(
                        color: AppColors.textMuted.withValues(alpha: 0.8),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      pin,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (description != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                description,
                style: TextStyle(
                  color: AppColors.textMuted.withValues(alpha: 0.8),
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLocalServer = widget.isRelayServer && widget.currentServerUrl == null;
    final otherServers = _servers
        .where((s) => s.url != widget.currentServerUrl)
        .toList();

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: AppSpacing.sm),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderMedium,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm,
            ),
            child: Text(
              isLocalServer
                  ? 'Tu servidor'
                  : widget.currentServerUrl != null
                      ? 'Servidor conectado'
                      : 'Conectar a servidor',
              style: theme.textTheme.titleMedium,
            ),
          ),

          // ─── Server card (local or external) ──────────────────────
          if (isLocalServer)
            _buildServerInfoCard(
              address: '${widget.relayIp ?? '...'}:${widget.relayPort}',
              badgeText: 'Activo',
              icon: Icons.wifi_tethering_rounded,
              pin: widget.relayPin,
              description: 'Otros dispositivos pueden conectarse desde el navegador a esta dirección.',
            )
          else if (widget.currentServerUrl != null) ...[
            _buildServerInfoCard(
              address: widget.currentServerUrl!
                  .replaceAll('http://', '')
                  .replaceAll('https://', ''),
              webAddress: widget.webUrl
                  ?.replaceAll('http://', '')
                  .replaceAll('https://', ''),
              badgeText: 'Conectado',
              icon: Icons.wifi_rounded,
              description: 'Servidor al que estás conectado actualmente.',
            ),
            const Divider(
              color: AppColors.borderSubtle,
              indent: AppSpacing.lg,
              endIndent: AppSpacing.lg,
              height: 1,
            ),
          ],

          // ─── Scan / connect (only if NOT local server) ────────────
          if (!isLocalServer) ...[
            if (_scanning)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: AppColors.accentPrimary,
                        ),
                      ),
                      SizedBox(width: AppSpacing.sm),
                      Text(
                        'Buscando servidores...',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              )
            else if (otherServers.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm,
                ),
                child: Text(
                  'No se encontraron otros servidores en la red.',
                  style: theme.textTheme.bodySmall,
                ),
              )
            else ...[
              ...otherServers.map(
                (server) => ListTile(
                  onTap: () => _connectTo(server.url),
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.accentPrimary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.computer_rounded,
                      color: AppColors.accentPrimary,
                      size: 18,
                    ),
                  ),
                  title: Text(server.appName, style: theme.textTheme.bodyMedium),
                  subtitle: Text(
                    server.ip,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: AppColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textMuted,
                    size: 20,
                  ),
                ),
              ),
              const Divider(
                color: AppColors.borderSubtle,
                indent: AppSpacing.lg,
                endIndent: AppSpacing.lg,
              ),
            ],

            // Manual IP input
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ipController,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.go,
                      onSubmitted: (_) => _connectManual(),
                      decoration: const InputDecoration(
                        hintText: '192.168.1.x:3001',
                        prefixIcon: Icon(Icons.lan_rounded, color: AppColors.textMuted),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ElevatedButton(
                    onPressed: _connectManual,
                    child: const Text('Conectar'),
                  ),
                ],
              ),
            ),

            // Rescan button
            if (!_scanning)
              Center(
                child: TextButton.icon(
                  onPressed: _scan,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Volver a escanear', style: TextStyle(fontSize: 13)),
                  style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
                ),
              ),
          ],

          // Disconnect → back to splash
          Center(
            child: TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onDisconnect();
              },
              style: TextButton.styleFrom(
                foregroundColor: AppColors.danger,
              ),
              child: const Text('Desconectarse', style: TextStyle(fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}
