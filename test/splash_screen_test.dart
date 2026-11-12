import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:srvfiles_mobile/main.dart';

/// Prueba de humo de arranque: la app abre el splash y la entrada manual
/// valida la dirección sin bloquearse mientras escanea la red.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('app starts on the splash; manual input validates while scanning', (tester) async {
    await tester.pumpWidget(const SrvFilesApp());
    await tester.pump();

    expect(find.text('SrvFiles'), findsOneWidget);
    final connect = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Conectar'));
    expect(connect.onPressed, isNotNull); // el escaneo no bloquea

    await tester.enterText(find.byType(TextField), 'ftp://nada');
    await tester.tap(find.text('Conectar'));
    await tester.pump();
    expect(find.textContaining('Dirección inválida'), findsOneWidget);
  });
}
