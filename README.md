# SrvFiles Mobile

Aplicación móvil Android para [SrvFiles](https://github.com/tu-usuario/srvfiles) — el sistema de transferencia de archivos en red local sin internet, sin cuenta, sin configuración.

---

## ¿Qué es?

SrvFiles Mobile es el cliente Android del ecosistema SrvFiles. Permite conectarse a un servidor SrvFiles corriendo en una PC de la misma red para explorar, descargar y subir archivos, además de transferir archivos directamente entre dispositivos vía P2P.

También puede funcionar **sin ningún servidor**: el celular levanta su propio relay embebido y actúa como punto de encuentro para que otros dispositivos se conecten entre sí.

---

## Funcionalidades

### Modo con servidor (conectado a SrvFiles desktop)

- **Explorar archivos** — lista los archivos disponibles en el servidor con búsqueda en tiempo real
- **Vista lista y grilla** — toggle entre ambas vistas
- **Descarga de archivos** — descarga cualquier archivo del servidor al dispositivo
- **Subida de archivos** — seleccioná archivos del dispositivo y subílos al servidor
- **Compartir archivos** — compartí cualquier archivo del servidor con otras apps del sistema
- **Espacio en disco** — barra visual de uso del disco del servidor en el AppBar
- **Código QR** — muestra el QR de acceso al servidor al pie de la pantalla

### Transferencia P2P directa

- **Dispositivos conectados** — lista en tiempo real de todos los clientes conectados al relay, con ícono por tipo: 🖥️ servidor Tauri, 🌐 navegador web, 📱 móvil
- **Badge servidor** — los peers que son servidores SrvFiles muestran un badge "srv" y un botón "Ver" para navegar a sus archivos
- **Cambio de servidor** — al tocar la IP en el header, se abre un sheet con el servidor actual (no clickeable), otros servidores encontrados en la red y un campo de IP manual para conectarse a cualquier otro servidor
- **Enviar archivo a un peer** — seleccioná un dispositivo de la lista y enviále un archivo directamente, sin pasar por disco
- **Aceptar / rechazar transferencias entrantes** — dialog de confirmación al recibir una solicitud
- **Progreso de transferencia** — barra animada durante el envío y recepción
- **Archivos recibidos** — los archivos recibidos por P2P se guardan en `Documents/SrvFiles/received/` y aparecen en una sección persistente dentro de la pantalla principal
- **Abrir y compartir archivos recibidos** — abrí el archivo con la app del sistema o compartilo
- **Eliminar archivos recibidos** — menú contextual (long press) con opción de eliminar

### Modo sin servidor (solo P2P)

- **Relay embebido** — al tocar "Omitir servidor" en el splash, el celular levanta automáticamente un mini servidor WebSocket en la LAN
- **Descubrimiento automático** — otros dispositivos con SrvFiles (desktop o mobile) descubren el relay y se conectan sin configuración
- **Transferencias phone-to-phone** — dos celulares pueden intercambiar archivos sin necesidad de una PC

### Descubrimiento automático de servidores

- Al abrir la app, escanea la subred local en paralelo buscando servidores SrvFiles activos (puerto 3001)
- Si ya se conectó antes, prueba primero el último servidor conocido (respuesta inmediata)
- Los servidores encontrados se muestran como tiles seleccionables — el usuario elige a cuál conectarse (sin auto-conexión)
- Si no encuentra nada, muestra el campo para ingresar la IP manualmente; también está disponible "Omitir servidor" para modo P2P puro

### General

- **Tema oscuro** con glassmorphism, gradientes y animaciones
- **Notificaciones locales** al completar una descarga o recibir un archivo
- **Nombre de dispositivo** — identificate con un nombre visible para los demás peers (se configura en el primer arranque)
- **Reconexión automática** — si el servidor se desconecta, reintenta automáticamente cada 3 segundos
- **Indicador de conexión perdida** — banner rojo cuando el servidor se desconecta; oculta la lista de archivos y el botón de subir hasta reconectar
- **Copyright al pie** — el footer del QR incluye los créditos del autor con link al repositorio

---

## Ecosistema SrvFiles

| Componente | Repo | Descripción |
|------------|------|-------------|
| **Backend** | [srvfiles](https://github.com/dotdeivid/srvfiles) | Servidor Express + WebSocket (Node.js) |
| **Frontend web** | [srvfiles](https://github.com/dotdeivid/srvfiles) | Cliente React/Vite |
| **Desktop (Tauri)** | [srvfiles](https://github.com/dotdeivid/srvfiles) | App nativa macOS/Windows/Linux — actúa como servidor + cliente |
| **Mobile (este repo)** | — | Cliente Android Flutter |

Los cuatro componentes comparten el mismo protocolo WebSocket para P2P. Un celular puede transferir archivos directamente a la app de escritorio y viceversa.

---

## Desarrollo

### Requisitos

| Herramienta | Versión mínima |
|-------------|----------------|
| Flutter | 3.19 (stable) |
| Dart SDK | 3.3 |
| Android SDK | API 21 (Android 5.0) |
| Java | 17 |

```bash
# Verificar entorno
flutter doctor
```

### Correr en desarrollo

```bash
# Instalar dependencias
flutter pub get

# Correr en dispositivo o emulador conectado
flutter run
```

Para que el descubrimiento automático funcione, el dispositivo tiene que estar en la misma red WiFi que la PC con SrvFiles corriendo.

### Correr los tests

```bash
flutter test
```

El proyecto incluye tests unitarios y de widgets para todos los componentes principales (modelos, widgets, servicios, relay embebido).

---

## Build

### APK de debug (desarrollo)

```bash
flutter build apk --debug
```

El APK queda en `build/app/outputs/flutter-apk/app-debug.apk`.

### APK de release

```bash
flutter build apk --release \
  --build-name="1.0.0" \
  --build-number="1"
```

El APK queda en `build/app/outputs/flutter-apk/app-release.apk`.

> **Firma:** Por defecto el APK de release usa la firma de debug de Flutter, suficiente para instalar por sideloading. Para publicar en Google Play se necesita configurar un keystore.

### Instalar directamente en el dispositivo

```bash
flutter install
```

---

## CI / CD

El repositorio incluye un workflow de GitHub Actions (`.github/workflows/release.yml`) que genera el APK automáticamente al publicar un tag.

### Cómo lanzar una release

```bash
git tag v1.0.0
git push origin v1.0.0
```

Esto dispara el workflow y al terminar el APK aparece en la sección **Releases** del repositorio como `SrvFiles-v1.0.0.apk`.

### Qué hace el workflow

| Paso | Descripción |
|------|-------------|
| Checkout | Clona el repositorio |
| Java 17 | Requerido por el Android Gradle Plugin |
| Flutter stable | Configura Flutter con cache de pub |
| Cache Gradle | Cachea `~/.gradle` para builds más rápidos |
| Tests | Corre `flutter test` antes de compilar |
| Build APK | `flutter build apk --release` con versión del tag |
| Upload | Sube el APK a la GitHub Release |

---

## Estructura del proyecto

```
mobile/
├── lib/
│   ├── main.dart                        # Entry point
│   ├── config/
│   │   └── api_config.dart              # URLs de la API (archivos, WebSocket)
│   ├── models/
│   │   ├── file_info.dart               # Modelo de archivo
│   │   ├── disk_stats.dart              # Modelo de estadísticas de disco
│   │   ├── app_config.dart              # Configuración del servidor
│   │   ├── transfer_client.dart         # Peer conectado (clientId, appName, deviceType, isServer)
│   │   ├── transfer_request.dart        # Solicitud de transferencia entrante
│   │   └── active_transfer.dart         # Estado de transferencia en curso
│   ├── services/
│   │   ├── files_service.dart           # API REST (listar, subir, descargar, stats)
│   │   ├── transfer_service.dart        # Cliente WebSocket P2P
│   │   ├── discovery_service.dart       # Descubrimiento LAN (scan de subred)
│   │   ├── received_files_service.dart  # Gestión de archivos recibidos por P2P
│   │   ├── embedded_relay.dart          # Relay WebSocket embebido (modo sin servidor)
│   │   ├── device_name_service.dart     # Nombre del dispositivo (SharedPreferences)
│   │   └── notification_service.dart   # Notificaciones locales
│   ├── screens/
│   │   ├── splash_screen.dart           # Pantalla de inicio y descubrimiento
│   │   └── home_screen.dart             # Pantalla principal (archivos, P2P, recibidos)
│   ├── widgets/
│   │   ├── gradient_text.dart           # Texto con gradiente (logo)
│   │   ├── glass_card.dart              # Tarjeta con efecto vidrio
│   │   ├── disk_stats_bar.dart          # Barra de uso de disco
│   │   ├── search_bar.dart              # Campo de búsqueda
│   │   ├── file_list_item.dart          # Fila de archivo en vista lista
│   │   ├── file_grid_item.dart          # Card de archivo en vista grilla
│   │   ├── online_clients.dart          # Lista de peers conectados
│   │   ├── incoming_transfer_dialog.dart# Dialog de transferencia entrante
│   │   ├── upload_sheet.dart            # Bottom sheet de subida
│   │   ├── qr_footer.dart               # QR de acceso al servidor
│   │   ├── pulsing_dot.dart             # Punto animado de estado
│   │   ├── skeleton_loader.dart         # Loader esqueleto durante carga
│   │   └── name_dialog.dart             # Dialog de nombre de dispositivo
│   ├── theme/
│   │   ├── app_theme.dart               # ThemeData principal
│   │   └── app_colors.dart              # Paleta de colores, espaciado, radios
│   └── utils/
│       ├── format.dart                  # formatBytes(), formatDate()
│       └── file_icons.dart              # Mapeo extensión → emoji
├── test/
│   ├── models_test.dart                 # Tests de modelos
│   ├── utils_test.dart                  # Tests de utilidades
│   ├── widgets_test.dart                # Tests de widgets
│   ├── api_config_test.dart             # Tests de ApiConfig
│   ├── received_files_test.dart         # Tests de ReceivedFilesService
│   └── embedded_relay_test.dart         # Tests de integración del relay
└── .github/
    └── workflows/
        └── release.yml                  # CI: genera APK al pushear un tag
```

---

## Stack

| Capa | Tecnología |
|------|-----------|
| Framework | Flutter 3 (Dart) |
| HTTP | `package:http` |
| WebSocket | `package:web_socket_channel` |
| Archivos | `file_picker` · `path_provider` · `open_filex` · `share_plus` |
| Persistencia | `shared_preferences` |
| Notificaciones | `flutter_local_notifications` |
| QR | `qr_flutter` |
| Links externos | `url_launcher` |
| Fuentes | `google_fonts` (Outfit, Inter) |
| Relay embebido | `dart:io` HttpServer + WebSocket |
| CI/CD | GitHub Actions · `subosito/flutter-action` · `softprops/action-gh-release` |

---

## Protocolo WebSocket (P2P)

El relay (ya sea el del servidor SrvFiles desktop o el relay embebido en el celular) implementa el mismo protocolo en todos los casos:

| Mensaje | Dirección | Descripción |
|---------|-----------|-------------|
| `hello` | cliente → relay | Registro con `appName`, `deviceType` e `isServer: boolean` |
| `welcome` | relay → cliente | Confirmación con `clientId` asignado |
| `clients` | relay → todos | Lista actualizada de peers conectados (incluye `isServer` por peer) |
| `set-receiving` | cliente → relay | Marca al cliente como disponible para recibir |
| `rename` | cliente → relay | Cambia el nombre visible del cliente sin reconectar |
| `send-request` | cliente → relay → peer | Solicitud de transferencia |
| `send-accept` | peer → relay → cliente | Aceptación |
| `send-reject` | peer → relay → cliente | Rechazo |
| `send-cancel` | cualquiera → relay → otro | Cancelación |
| `send-complete` | sender → relay → receiver | Fin de la transferencia |
| `[binario]` | sender → relay → receiver | Chunk de archivo (prefijado con 36 bytes del transferId) |
