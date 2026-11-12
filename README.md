# SrvFiles Mobile

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

App Android para el ecosistema [SrvFiles](https://github.com/dotdeivid/srvfiles) — transferencia de archivos en red local sin internet, sin cuenta, sin configuración.

## Modos de operación

- **Cliente** — se conecta a un servidor SrvFiles (desktop o mobile) para explorar, subir y descargar archivos
- **Servidor** — levanta un servidor HTTP + WebSocket propio; cualquier navegador o dispositivo de la red puede conectarse
- **Relay P2P** — actúa como punto de encuentro para que otros dispositivos se transfieran archivos entre sí
- **Envío directo** — escanea la red y envía archivos directamente a otros dispositivos sin servidor central

## Características principales

- Explorar, subir, descargar y eliminar archivos del servidor
- **Previsualización de archivos** — botón "ver" en lista y grilla; imágenes, video, audio, PDF y texto se abren en pantalla completa sin descargar permanentemente (ver tabla abajo)
- Transferencia P2P directa entre dispositivos (sin pasar por disco)
- **Cifrado de extremo a extremo obligatorio** — cada transferencia negocia su propia clave (ECDH P-256 + AES-256-GCM) entre emisor y receptor; el relay o servidor solo reenvía y no puede leer el archivo. Ambos ven un código de 6 dígitos y el receptor confirma que coincide antes de aceptar. Además, el canal con el servidor va cifrado (candado en el encabezado). Protocolo: `docs/protocol.md` de srvfiles_web
- Descargas, archivos recibidos y modo servidor comparten una sola carpeta: `Download/SrvFiles`, la misma que el servidor web y la app de escritorio (si Android no permite escribir ahí, el almacenamiento propio de la app; en iOS, la app Archivos). Sin permisos especiales: la app ve en esa carpeta solo los archivos que creó ella. Lo que había en las carpetas anteriores se mueve solo la primera vez
- Descubrimiento automático de servidores en la red local al abrir la app
- Autenticación PIN al conectarse a servidores protegidos
- ConnectSheet: info del servidor activo (IP, PIN, estado) accesible desde el header
- Indicador de espacio en disco en tiempo real
- QR de acceso al servidor
- Servicio en primer plano: el WebSocket sigue activo con la pantalla bloqueada (solo cuando la app está en segundo plano)
- Notificaciones locales al completar descargas o transferencias P2P (Android 13+ pide permiso al primer arranque)
- **Logging estructurado** — AppLogger con niveles debug/info/warn/error; visible en consola en debug y en archivo en release
- **Ícono unificado** — mismo ícono SF violeta que web y Tauri; visible en el launcher y el splash screen

---

## Archivos que se pueden previsualizar

| Categoría | Extensiones | Mobile |
|-----------|------------|--------|
| **Imagen** | jpg, jpeg, png, gif, webp, bmp, ico | `photo_view` (zoom con gestos) |
| **SVG** | svg | `flutter_svg` |
| **Video** | mp4, mov, m4v, webm | `video_player` + `chewie` |
| **Audio** | mp3, wav, aac, m4a, ogg, flac, opus | `audioplayers` + UI con play/pausa y barra |
| **PDF** | pdf | `pdfx` (scroll de páginas) |
| **Texto / Código** | txt, md, json, xml, csv, yaml, yml, html, js, ts, dart, py, go, rs, c, cpp, h, css, sh, bash | Widget monospace scrollable |
| **Desconocido** | docx, xlsx, zip, apk, etc. | Botón "Abrir con" → `open_filex` |

Los archivos del servidor se descargan a un directorio temporal y se eliminan al cerrar el previsualizador. Los archivos ya recibidos (en `Download/SrvFiles`) se abren directamente desde disco.

---

## Comandos

### Requisitos

| Herramienta | Versión |
|-------------|---------|
| Flutter | 3.50+ (stable) |
| Dart SDK | 3.13+ |
| Android SDK | compila contra API 37; instala desde API 24 (Android 7.0) |
| Java | 17 |
| Gradle / AGP / Kotlin | 9.5.0 / 9.3.1 / 2.4.20 (vienen en el wrapper del proyecto) |

> Los widgets Material vienen de `package:material_ui` (Flutter los separó del SDK en 3.47). Usar `import 'package:material_ui/material_ui.dart';` en lugar de `package:flutter/material.dart`.

```bash
flutter doctor
```

### Desarrollo

```bash
flutter pub get
flutter run
```

El dispositivo tiene que estar en la misma red WiFi que los demás dispositivos.

### Tests

```bash
flutter test
```

### Build APK

```bash
# Debug
flutter build apk --debug

# Release
flutter build apk --release --build-name="1.0.0" --build-number="1"
```

APK en `build/app/outputs/flutter-apk/`.

### Instalar directo en el dispositivo

```bash
flutter install
```

### Release automática (CI/CD)

```bash
git tag v1.0.0 && git push origin v1.0.0
```

Genera el APK y lo publica en GitHub Releases como `SrvFiles-vX.Y.Z.apk`.

---

## Notas importantes

- El servidor mobile sirve la UI web del frontend embebida en el APK — cualquier navegador de la red puede acceder sin instalar nada.
- El PIN se genera automáticamente en cada sesión de servidor y se muestra en el ConnectSheet.
- La firma de release por defecto es la de debug de Flutter (válida para sideloading). Para Google Play se necesita configurar un keystore.
- El espacio en disco se obtiene vía `StatFs` nativo (MethodChannel), sin dependencias externas.

## Licencia

Distribuido bajo la licencia [Apache 2.0](LICENSE). © 2026 dotdeivid.
