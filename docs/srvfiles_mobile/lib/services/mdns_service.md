# services/mdns_service.dart

**File:** `lib/services/mdns_service.dart`
**Rol:** Descubrimiento y anuncio por mDNS (Android NSD / iOS Bonjour, paquete `nsd`).

---

Reemplaza al barrido de la subred, que probaba 254 direcciones por HTTP: cada equipo se anuncia como `_srvfiles._tcp` (`srvfilesServiceType`) y los demás solo escuchan. El backend Go se anuncia igual (`backend/internal/announce`).

| Método | Descripción |
|---|---|
| `Future<void> advertise({name, port})` | Anuncia el relay (TXT `app=srvfiles`, `deviceType=mobile`). Reemplaza un anuncio anterior; el nombre se recorta a 63 bytes. |
| `Future<void> stopAdvertising()` | Retira el anuncio. |
| `Future<List<String>> browse({window = 3 s})` | Escucha anuncios durante `window` y devuelve `http://ip:puerto` (IPv4). No valida: `DiscoveryService` prueba `/api/health`. |

Los errores (plugin no disponible, red sin multicast) se registran y devuelven "nada encontrado", así `DiscoveryService.discover` cae al barrido. En iOS el tipo de servicio figura en `NSBonjourServices` (`Info.plist`).
