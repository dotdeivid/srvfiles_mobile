# widgets/search_bar.dart

**Archivo:** `lib/widgets/search_bar.dart`
**Rol:** Barra de búsqueda con botón para limpiar. Replica el input de búsqueda del `FileList.tsx` web.

---

## Props

```dart
class FileSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;
}
```

`ValueChanged<String>` es un typedef para `void Function(String value)`. Se llama cada vez que el texto del campo cambia.

Recibir el `controller` como prop (en lugar de crearlo internamente) permite que el padre controle el estado del texto. En `HomeScreen`:

```dart
_searchController = TextEditingController();
// ...
FileSearchBar(
  controller: _searchController,
  onChanged: (v) => setState(() => _searchQuery = v),
  onClear: () => setState(() => _searchQuery = ''),
)
```

---

## `suffixIcon` condicional

```dart
suffixIcon: controller.text.isNotEmpty
    ? IconButton(
        icon: const Icon(Icons.close, ...),
        onPressed: () {
          controller.clear();
          onClear?.call();
        },
      )
    : null,
```

El botón "X" solo aparece cuando hay texto. `controller.clear()` vacía el campo y `onClear?.call()` notifica al padre para actualizar `_searchQuery`.

El operador `?.call()` llama la función solo si no es `null` (es opcional).

---

## `isDense: true`

```dart
decoration: InputDecoration(
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
),
```

`isDense: true` reduce el padding interno del `TextField` para que sea más compacto. Sin esto, el campo ocupa más altura de lo necesario.
