import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart' as pc;
import '../app_logger.dart';

/// Certificado TLS autofirmado del relay. Misma receta que el backend Go
/// (`internal/cert`):
///   - clave ECDSA P-256 y firma ecdsa-with-SHA256;
///   - número de serie aleatorio de 128 bits;
///   - SAN con la IP de la LAN, 127.0.0.1 y localhost;
///   - validez de 2 años.
///
/// Sin HTTPS el navegador de otro equipo no es un contexto seguro: no tiene
/// WebCrypto y no puede enviar ni recibir archivos (cifrado de extremo a
/// extremo obligatorio).
///
/// Se guarda en disco y se reutiliza mientras siga vigente y cubra la IP
/// actual, para que el navegador no pida aceptar el certificado cada vez.
class RelayCertStore {
  RelayCertStore({Future<Directory> Function()? directory})
      : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  static const _fileName = 'relay_tls.json';
  static const validity = Duration(days: 730);
  static const renewBefore = Duration(days: 30);

  /// Contexto TLS listo para `HttpServer.bindSecure`.
  Future<SecurityContext> securityContext(List<String> lanIps) async {
    final cert = await getOrCreate(lanIps);
    return SecurityContext()
      ..useCertificateChainBytes(utf8.encode(cert.certPem))
      ..usePrivateKeyBytes(utf8.encode(cert.keyPem));
  }

  /// Certificado guardado si sigue sirviendo; si no, uno nuevo.
  Future<RelayCert> getOrCreate(List<String> lanIps, {DateTime? now}) async {
    final file = File(p.join((await _directory()).path, _fileName));
    final at = now ?? DateTime.now();
    try {
      final saved = RelayCert.fromJson(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
      if (saved.covers(lanIps, at)) return saved;
      AppLogger.instance.info('relay_cert: certificado vencido o con otra IP, se genera uno nuevo');
    } on PathNotFoundException {
      // Primera vez.
    } catch (e) {
      AppLogger.instance.warn('relay_cert: certificado guardado ilegible, se genera uno nuevo: $e');
    }
    final cert = RelayCert.generate(lanIps, now: at);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(cert.toJson()), flush: true);
    AppLogger.instance.info('relay_cert: certificado TLS generado para ${cert.ips.join(', ')}');
    return cert;
  }
}

class RelayCert {
  RelayCert({required this.certPem, required this.keyPem, required this.ips, required this.notAfter});

  final String certPem;
  final String keyPem;
  /// IPs del SAN (sin contar 127.0.0.1).
  final List<String> ips;
  final DateTime notAfter;

  /// No vence en los próximos 30 días y cubre todas las IPs pedidas.
  bool covers(List<String> lanIps, DateTime now) =>
      now.add(RelayCertStore.renewBefore).isBefore(notAfter) && lanIps.every(ips.contains);

  factory RelayCert.fromJson(Map<String, dynamic> json) => RelayCert(
        certPem: json['certPem'] as String,
        keyPem: json['keyPem'] as String,
        ips: (json['ips'] as List).cast<String>(),
        notAfter: DateTime.parse(json['notAfter'] as String),
      );

  Map<String, dynamic> toJson() => {
        'certPem': certPem,
        'keyPem': keyPem,
        'ips': ips,
        'notAfter': notAfter.toUtc().toIso8601String(),
      };

  factory RelayCert.generate(List<String> lanIps, {DateTime? now}) {
    final rng = _secureRandom();
    final domain = pc.ECDomainParameters('secp256r1');
    final pair = (pc.ECKeyGenerator()
          ..init(pc.ParametersWithRandom(pc.ECKeyGeneratorParameters(domain), rng)))
        .generateKeyPair();
    final privateKey = pair.privateKey;
    final publicPoint = pair.publicKey.Q!.getEncoded(false); // 0x04 || x || y

    final notBefore = (now ?? DateTime.now()).toUtc().subtract(const Duration(hours: 1));
    final notAfter = notBefore.add(RelayCertStore.validity);
    final ips = lanIps.where((ip) => InternetAddress.tryParse(ip) != null).toSet().toList();

    final name = _seq([
      _set([_seq([_oid(_oidCommonName), _utf8('SrvFiles')])]),
      _set([_seq([_oid(_oidOrganization), _utf8('SrvFiles (autofirmado)')])]),
    ]);
    final serial = Uint8List.fromList(List.generate(16, (_) => rng.nextUint8()));

    final tbs = _seq([
      _tlv(0xa0, _int(Uint8List.fromList([2]))), // versión v3
      _int(serial),
      _seq([_oid(_oidEcdsaSha256)]),
      name,
      _seq([_utcTime(notBefore), _utcTime(notAfter)]),
      name,
      _seq([
        _seq([_oid(_oidEcPublicKey), _oid(_oidP256)]),
        _bitString(publicPoint),
      ]),
      _tlv(0xa3, _seq([
        _extension(_oidSubjectAltName, _seq([
          for (final ip in ['127.0.0.1', ...ips]) _tlv(0x87, InternetAddress(ip).rawAddress),
          _tlv(0x82, ascii.encode('localhost')),
        ])),
        _extension(_oidBasicConstraints, _seq([]), critical: true),
        _extension(_oidKeyUsage, _tlv(0x03, Uint8List.fromList([0x07, 0x80])), critical: true), // digitalSignature
        _extension(_oidExtKeyUsage, _seq([_oid(_oidServerAuth)])),
      ])),
    ]);

    final signer = pc.ECDSASigner(pc.SHA256Digest(), pc.HMac(pc.SHA256Digest(), 64)) // RFC 6979
      ..init(true, pc.PrivateKeyParameter<pc.ECPrivateKey>(privateKey));
    final sig = signer.generateSignature(tbs) as pc.ECSignature;
    final certDer = _seq([
      tbs,
      _seq([_oid(_oidEcdsaSha256)]),
      _bitString(_seq([_int(_unsigned(sig.r)), _int(_unsigned(sig.s))])),
    ]);

    // PKCS#8 con un ECPrivateKey (RFC 5915) adentro, como "PRIVATE KEY".
    final keyDer = _seq([
      _int(Uint8List.fromList([0])),
      _seq([_oid(_oidEcPublicKey), _oid(_oidP256)]),
      _tlv(0x04, _seq([
        _int(Uint8List.fromList([1])),
        _tlv(0x04, _unsigned(privateKey.d!, length: 32)),
        _tlv(0xa1, _bitString(publicPoint)),
      ])),
    ]);

    return RelayCert(
      certPem: _pem('CERTIFICATE', certDer),
      keyPem: _pem('PRIVATE KEY', keyDer),
      ips: ips,
      notAfter: notAfter,
    );
  }
}

// ─── DER mínimo ──────────────────────────────────────────────────────

const _oidCommonName = [2, 5, 4, 3];
const _oidOrganization = [2, 5, 4, 10];
const _oidEcPublicKey = [1, 2, 840, 10045, 2, 1];
const _oidP256 = [1, 2, 840, 10045, 3, 1, 7];
const _oidEcdsaSha256 = [1, 2, 840, 10045, 4, 3, 2];
const _oidSubjectAltName = [2, 5, 29, 17];
const _oidBasicConstraints = [2, 5, 29, 19];
const _oidKeyUsage = [2, 5, 29, 15];
const _oidExtKeyUsage = [2, 5, 29, 37];
const _oidServerAuth = [1, 3, 6, 1, 5, 5, 7, 3, 1];

Uint8List _tlv(int tag, List<int> value) {
  final len = value.length;
  final header = <int>[tag];
  if (len < 0x80) {
    header.add(len);
  } else {
    final bytes = <int>[];
    for (var n = len; n > 0; n >>= 8) {
      bytes.insert(0, n & 0xff);
    }
    header..add(0x80 | bytes.length)..addAll(bytes);
  }
  return Uint8List.fromList([...header, ...value]);
}

Uint8List _seq(List<List<int>> items) => _tlv(0x30, items.expand((e) => e).toList());
Uint8List _set(List<List<int>> items) => _tlv(0x31, items.expand((e) => e).toList());
Uint8List _utf8(String s) => _tlv(0x0c, utf8.encode(s));
Uint8List _bitString(List<int> bytes) => _tlv(0x03, [0, ...bytes]);

/// INTEGER positivo: sin ceros de más a la izquierda y con un 0 delante si el
/// primer bit está en 1 (si no, se leería como negativo).
Uint8List _int(Uint8List magnitude) {
  var start = 0;
  while (start < magnitude.length - 1 && magnitude[start] == 0) {
    start++;
  }
  final trimmed = magnitude.sublist(start);
  return _tlv(0x02, trimmed[0] & 0x80 != 0 ? [0, ...trimmed] : trimmed);
}

Uint8List _oid(List<int> parts) {
  final out = <int>[40 * parts[0] + parts[1]];
  for (final part in parts.skip(2)) {
    final chunk = <int>[part & 0x7f];
    for (var n = part >> 7; n > 0; n >>= 7) {
      chunk.insert(0, 0x80 | (n & 0x7f));
    }
    out.addAll(chunk);
  }
  return _tlv(0x06, out);
}

/// UTCTime (YYMMDDHHMMSSZ): válido hasta 2049, de sobra para 2 años.
Uint8List _utcTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  final u = t.toUtc();
  return _tlv(0x17, ascii.encode(
      '${two(u.year % 100)}${two(u.month)}${two(u.day)}${two(u.hour)}${two(u.minute)}${two(u.second)}Z'));
}

Uint8List _extension(List<int> oid, Uint8List value, {bool critical = false}) => _seq([
      _oid(oid),
      if (critical) _tlv(0x01, [0xff]),
      _tlv(0x04, value),
    ]);

Uint8List _unsigned(BigInt n, {int? length}) {
  var hex = n.toRadixString(16);
  if (hex.length.isOdd) hex = '0$hex';
  final bytes = [for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
  if (length != null) {
    while (bytes.length < length) {
      bytes.insert(0, 0);
    }
  }
  return Uint8List.fromList(bytes);
}

String _pem(String label, List<int> der) {
  final b64 = base64.encode(der);
  final lines = [for (var i = 0; i < b64.length; i += 64) b64.substring(i, min(i + 64, b64.length))];
  return '-----BEGIN $label-----\n${lines.join('\n')}\n-----END $label-----\n';
}

pc.SecureRandom _secureRandom() {
  final rng = Random.secure();
  final seed = Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
  return pc.FortunaRandom()..seed(pc.KeyParameter(seed));
}
