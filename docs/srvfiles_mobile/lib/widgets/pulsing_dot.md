# widgets/pulsing_dot.dart

**Archivo:** `lib/widgets/pulsing_dot.dart`
**Rol:** Punto circular con animación de pulso (glow pulsante). Indica dispositivos conectados en tiempo real. Replica el efecto CSS del frontend web.

---

## Estructura

```
PulsingDot (StatefulWidget)
└── _PulsingDotState (with SingleTickerProviderStateMixin)
    ├── AnimationController
    └── Animation<double>
```

Es un `StatefulWidget` porque la animación requiere estado mutable (el controlador de animación).

---

## `SingleTickerProviderStateMixin`

```dart
class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
```

Las animaciones en Flutter necesitan un "ticker": un objeto que emite un evento por cada frame (60 veces por segundo). El mixin `SingleTickerProviderStateMixin` convierte el `State` en un proveedor de tickers, que luego se pasa al `AnimationController` con `vsync: this`.

`Single` porque este widget solo tiene una animación. Si hubiera dos, se usaría `TickerProviderStateMixin`.

---

## AnimationController

```dart
_controller = AnimationController(
  duration: const Duration(milliseconds: 1500),
  vsync: this,
)..repeat(reverse: true);
```

- `duration`: duración de un ciclo completo de animación (1.5 segundos).
- `vsync: this`: sincroniza la animación con el frame rate de la pantalla, evitando frames innecesarios cuando la pantalla no está visible.
- `..repeat(reverse: true)`: la animación va hacia adelante, luego al revés, en bucle infinito.

---

## Tween y CurvedAnimation

```dart
_animation = Tween<double>(begin: 0.3, end: 0.8).animate(
  CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
);
```

- `Tween<double>(0.3, 0.8)`: interpola el valor entre 0.3 y 0.8 (el alpha del glow).
- `CurvedAnimation` con `Curves.easeInOut`: hace que la animación acelere al inicio y desacelere al final, en lugar de ser lineal.

---

## `AnimatedBuilder`

```dart
AnimatedBuilder(
  animation: _animation,
  builder: (context, child) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: _animation.value),
            blurRadius: 5,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  },
);
```

`AnimatedBuilder` reconstruye solo su `builder` cuando cambia la animación, sin reconstruir el árbol completo. Cada frame, `_animation.value` tiene un valor diferente (entre 0.3 y 0.8), lo que hace que el glow pulse.

---

## `dispose`

```dart
@override
void dispose() {
  _controller.dispose();
  super.dispose();
}
```

Liberar el `AnimationController` en `dispose` es obligatorio. Sin esto, el controller sigue emitiendo frames aunque el widget ya no exista, causando una excepción.
