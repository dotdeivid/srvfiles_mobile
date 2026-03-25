# widgets/qr_footer.dart

**Archivo:** `lib/widgets/qr_footer.dart`
**Rol:** Footer con código QR de la URL del servidor para acceder desde otro dispositivo. Replica `QRFooter.tsx` del frontend web.

---

## Props

```dart
class QrFooter extends StatelessWidget {
  final AppConfig? config;
}
```

Si `config == null` (todavía cargando), retorna `SizedBox.shrink()`.

---

## URL del QR

```dart
final lanUrl = 'http://${config!.lanIp}:${config!.port}';
```

Construye la URL LAN del servidor a partir de la configuración. Esta URL es la que escanea el `QrImageView` y la que aparece como texto debajo del QR.

---

## `QrImageView`

```dart
QrImageView(
  data: lanUrl,
  version: QrVersions.auto,
  size: 140,
  backgroundColor: Colors.transparent,
  eyeStyle: const QrEyeStyle(
    eyeShape: QrEyeShape.square,
    color: AppColors.textAccent,
  ),
  dataModuleStyle: const QrDataModuleStyle(
    dataModuleShape: QrDataModuleShape.square,
    color: AppColors.textAccent,
  ),
),
```

Del paquete `qr_flutter`. Genera un QR code a partir del string `data`.

- `version: QrVersions.auto`: elige automáticamente la versión QR (1-40) según la longitud del texto.
- `eyeStyle`: los tres cuadrados grandes de las esquinas del QR.
- `dataModuleStyle`: los módulos de datos (cuadraditos pequeños).
- Ambos con `color: AppColors.textAccent` para mantener la paleta del tema oscuro.

---

## Link de GitHub

```dart
GestureDetector(
  onTap: () => launchUrl(
    Uri.parse('https://github.com/dotdeivid'),
    mode: LaunchMode.externalApplication,
  ),
  child: Text('github.com/dotdeivid', style: ...),
)
```

`launchUrl` del paquete `url_launcher` abre la URL en el navegador externo. `LaunchMode.externalApplication` fuerza el uso del navegador del sistema en lugar de una WebView in-app.
