# widgets/gradient_text.dart

**Archivo:** `lib/widgets/gradient_text.dart`
**Rol:** Widget que renderiza texto con gradiente de color. Usado en el título "SrvFiles" de la AppBar.

---

## Props

```dart
class GradientText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final Gradient? gradient;  // null = AppColors.accentGradient
}
```

---

## Implementación con `ShaderMask`

```dart
ShaderMask(
  blendMode: BlendMode.srcIn,
  shaderCallback: (bounds) => (gradient ?? AppColors.accentGradient)
      .createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
  child: Text(text, style: style),
)
```

### ¿Cómo funciona `ShaderMask`?

`ShaderMask` es una técnica de composición de imagen:

1. Renderiza el widget hijo (`Text`) normalmente.
2. Aplica el shader (gradiente) usando el modo de mezcla especificado.

`BlendMode.srcIn` significa "tomar el color del shader donde el hijo es opaco". En el texto, los píxeles del texto son opacos y los del fondo son transparentes. El resultado: el gradiente solo aparece dentro de los píxeles del texto.

### `createShader(Rect)`

`Gradient.createShader` necesita los límites para posicionar el gradiente. `bounds` en `shaderCallback` son los límites del widget actual. El gradiente se extiende de izquierda a derecha sobre el ancho completo del texto.

### Alternativa CSS equivalente

```css
background: linear-gradient(135deg, #6c63ff, #4ecdc4);
-webkit-background-clip: text;
-webkit-text-fill-color: transparent;
```

`ShaderMask` + `BlendMode.srcIn` es la forma Flutter de hacer exactamente esto.
