# services/relay/relay_cert.dart

**File:** `lib/services/relay/relay_cert.dart`

## Purpose

Self-signed TLS certificate for the relay's HTTPS server. Same recipe as the Go backend (`internal/cert`): ECDSA P-256 key, `ecdsa-with-SHA256` signature, random 128-bit serial, SAN with `127.0.0.1`, the LAN IP and `localhost`, 2-year validity.

The X.509 and PKCS#8 structures are written with a minimal DER encoder in the same file; the key pair and the signature come from `pointycastle` (deterministic ECDSA, RFC 6979).

## Exports / Public API

### `RelayCertStore`

| Member | Description |
|---|---|
| `RelayCertStore({Future<Directory> Function()? directory})` | Folder where the certificate is kept (default: `getApplicationSupportDirectory`, not the shared folder). |
| `Future<SecurityContext> securityContext(List<String> lanIps)` | Context for `HttpServer.bindSecure`. |
| `Future<RelayCert> getOrCreate(List<String> lanIps, {DateTime? now})` | Reuses `relay_tls.json` while it covers every IP and has more than 30 days left; otherwise generates and saves a new one. |

### `RelayCert`

`certPem`, `keyPem`, `ips` (SAN IPs other than `127.0.0.1`), `notAfter`; `covers(lanIps, now)`, `toJson` / `fromJson`, and `RelayCert.generate(lanIps)`.

## Notes

- Keeping the certificate means browsers only ask to accept it once per network.
- When the LAN IP changes while the relay runs, `EmbeddedRelay.start()` restarts HTTPS on the same port with a certificate for the new IP.
