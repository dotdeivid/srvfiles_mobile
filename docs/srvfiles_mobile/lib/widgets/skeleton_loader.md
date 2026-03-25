# widgets/skeleton_loader.dart

**Archivo:** `lib/widgets/skeleton_loader.dart`
**Rol:** Placeholder visual animado (shimmer) que se muestra mientras cargan los archivos. Reemplaza el spinner genérico con un layout que imita la estructura real de la lista.

---

## ¿Qué es un skeleton loader?

Un skeleton loader muestra la forma aproximada del contenido que va a aparecer (bloques grises donde irá el texto, rectángulos donde irán las imágenes) antes de que lleguen los datos reales. Mejora la percepción de velocidad porque el usuario ve que hay contenido cargando, no una pantalla en blanco.

---

## Animación shimmer

```dart
_animation = Tween<double>(begin: -1, end: 2).animate(
  CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
);
```

El valor animado va de -1 a 2, representando la posición horizontal del "brillo". El rango extendido (no 0-1) hace que el brillo entre y salga suavemente por los bordes del widget.

---

## Clase `_SkeletonBox`

```dart
class _SkeletonBox extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: const [
            AppColors.bgSecondary,
            AppColors.bgCardHover,
            AppColors.bgSecondary,
          ],
          stops: [
            (shimmerValue - 0.3).clamp(0.0, 1.0),
            shimmerValue.clamp(0.0, 1.0),
            (shimmerValue + 0.3).clamp(0.0, 1.0),
          ],
        ),
      ),
    );
  }
}
```

### Cómo funciona el shimmer

El gradiente tiene tres paradas: `bgSecondary`, `bgCardHover` (más claro), `bgSecondary`. Las posiciones de las paradas se calculan con `shimmerValue`:

- Cuando `shimmerValue = -1`: todas las paradas están al inicio → solo se ve el color oscuro.
- Cuando `shimmerValue = 0.5`: las paradas están en `0.2`, `0.5`, `0.8` → el brillo está en el centro.
- Cuando `shimmerValue = 2`: todas las paradas están al final → solo se ve el color oscuro.

Al animar `shimmerValue` de -1 a 2, el brillo "viaja" de izquierda a derecha, creando el efecto shimmer.

---

## Clase `_SkeletonFileRow`

Representa un placeholder de una fila de archivo. Tiene la misma estructura que `FileListItem`:
- Un cuadrado 32×32 (placeholder del emoji).
- Dos rectángulos de texto (nombre y tamaño).
- Dos cuadrados de botones de acción.
