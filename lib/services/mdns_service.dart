import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:nsd/nsd.dart' as nsd;
import 'app_logger.dart';

/// Tipo de servicio mDNS que anuncian todos los SrvFiles de la red: el relay
/// de cada teléfono y el backend de escritorio.
const srvfilesServiceType = '_srvfiles._tcp';

/// Descubrimiento por mDNS (Android NSD / iOS Bonjour).
///
/// Reemplaza al barrido de la subred, que probaba 254 direcciones por HTTP:
/// cada equipo se anuncia y los demás solo escuchan. Los errores (plugin no
/// disponible, red sin multicast) se registran y devuelven "nada encontrado",
/// así el que llama puede caer al barrido.
class MdnsService {
  nsd.Registration? _registration;

  /// Anuncia este dispositivo en [port]. Reemplaza un anuncio anterior (por
  /// ejemplo al cambiar el nombre).
  Future<void> advertise({required String name, required int port}) async {
    await stopAdvertising();
    try {
      _registration = await nsd.register(nsd.Service(
        name: _instanceName(name),
        type: srvfilesServiceType,
        port: port,
        txt: {
          'app': _bytes('srvfiles'),
          'deviceType': _bytes('mobile'),
        },
      ));
      AppLogger.instance.debug('[mDNS] advertising "$name" on port $port');
    } catch (e) {
      AppLogger.instance.warn('[mDNS] could not advertise: $e');
    }
  }

  Future<void> stopAdvertising() async {
    final registration = _registration;
    _registration = null;
    if (registration == null) return;
    try {
      await nsd.unregister(registration);
    } catch (e) {
      AppLogger.instance.warn('[mDNS] could not stop advertising: $e');
    }
  }

  /// Escucha anuncios durante [window] y devuelve las URLs `http://ip:puerto`
  /// encontradas (sin validar: el que llama prueba `/api/health`).
  Future<List<String>> browse({Duration window = const Duration(seconds: 3)}) async {
    nsd.Discovery? discovery;
    try {
      discovery = await nsd.startDiscovery(
        srvfilesServiceType,
        ipLookupType: nsd.IpLookupType.v4,
      );
      await Future<void>.delayed(window);
      final urls = <String>{
        for (final service in discovery.services)
          if (service.port != null)
            for (final address in service.addresses ?? const <InternetAddress>[])
              if (address.type == InternetAddressType.IPv4)
                'http://${address.address}:${service.port}',
      };
      AppLogger.instance.debug('[mDNS] found ${urls.length} service(s)');
      return urls.toList();
    } catch (e) {
      AppLogger.instance.warn('[mDNS] discovery failed: $e');
      return const [];
    } finally {
      if (discovery != null) {
        try {
          await nsd.stopDiscovery(discovery);
        } catch (_) {}
      }
    }
  }

  static Uint8List _bytes(String value) => Uint8List.fromList(utf8.encode(value));

  /// Las etiquetas DNS admiten hasta 63 bytes.
  static String _instanceName(String name) {
    final clean = name.trim().isEmpty ? 'SrvFiles' : name.trim();
    var result = clean;
    while (utf8.encode(result).length > 63) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}
