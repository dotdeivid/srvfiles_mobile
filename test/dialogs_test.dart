import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:srvfiles_mobile/theme/app_theme.dart';
import 'package:srvfiles_mobile/widgets/name_dialog.dart';
import 'package:srvfiles_mobile/widgets/pin_entry_dialog.dart';
import 'package:srvfiles_mobile/widgets/server_mode_warning_dialog.dart';
import 'package:srvfiles_mobile/widgets/incoming_transfer_dialog.dart';
import 'package:srvfiles_mobile/widgets/qr_footer.dart';
import 'package:srvfiles_mobile/models/transfer_request.dart';
import 'package:srvfiles_mobile/models/app_config.dart';

Widget wrapWithApp(Widget child) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(body: child),
  );
}

/// Helper that opens a dialog via showDialog from a tap on a button.
Widget dialogTrigger(Widget Function(BuildContext) builder) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Builder(
      builder: (ctx) => Scaffold(
        body: ElevatedButton(
          onPressed: () => showDialog(
            context: ctx,
            barrierDismissible: false,
            builder: builder,
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  );
}

void main() {
  // ─── NameDialog ──────────────────────────────────────────────────────────────

  group('NameDialog', () {
    testWidgets('renders with default name in text field', (tester) async {
      await tester.pumpWidget(
        dialogTrigger((_) => const NameDialog(defaultName: 'Rápido Zorro')),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('¿Cómo querés que te vean?'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Rápido Zorro'), findsOneWidget);
      expect(find.text('Guardar'), findsOneWidget);
      expect(find.text('Omitir'), findsOneWidget);
    });

    testWidgets('Guardar button pops with the current name', (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await showDialog<String>(
                    context: ctx,
                    builder: (_) => const NameDialog(defaultName: 'Mi Celular'),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(result, 'Mi Celular');
    });

    testWidgets('Omitir button pops with null', (tester) async {
      bool dialogClosed = false;
      String? result = 'sentinel';

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await showDialog<String>(
                    context: ctx,
                    builder: (_) => const NameDialog(defaultName: 'Test'),
                  );
                  dialogClosed = true;
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Omitir'));
      await tester.pumpAndSettle();

      expect(dialogClosed, true);
      expect(result, isNull);
    });

    testWidgets('can edit the text before saving', (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await showDialog<String>(
                    context: ctx,
                    builder: (_) => const NameDialog(defaultName: 'Antiguo'),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Nuevo Nombre');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(result, 'Nuevo Nombre');
    });
  });

  // ─── PinEntryDialog ──────────────────────────────────────────────────────────

  group('PinEntryDialog', () {
    testWidgets('renders with title and PIN input', (tester) async {
      await tester.pumpWidget(
        dialogTrigger((_) => const PinEntryDialog()),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Servidor protegido'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
      expect(find.text('Conectar'), findsOneWidget);
    });

    testWidgets('shows error when submitting short PIN', (tester) async {
      await tester.pumpWidget(
        dialogTrigger((_) => const PinEntryDialog()),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Enter only 4 digits — button stays disabled, but let's try submitting via keyboard
      await tester.enterText(find.byType(TextField), '1234');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('El PIN debe tener 6 dígitos'), findsOneWidget);
    });

    testWidgets('Conectar button is disabled when fewer than 6 digits', (tester) async {
      await tester.pumpWidget(
        dialogTrigger((_) => const PinEntryDialog()),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '123');
      await tester.pump();

      final btn = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Conectar'));
      expect(btn.onPressed, isNull);
    });

    testWidgets('Conectar button is enabled with 6 digits', (tester) async {
      await tester.pumpWidget(
        dialogTrigger((_) => const PinEntryDialog()),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();

      final btn = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Conectar'));
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('Cancelar pops with null', (tester) async {
      String? result = 'sentinel';
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await showDialog<String>(
                    context: ctx,
                    builder: (_) => const PinEntryDialog(),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });

    testWidgets('correct 6-digit PIN submits and pops with PIN', (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await showDialog<String>(
                    context: ctx,
                    builder: (_) => const PinEntryDialog(),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '654321');
      await tester.pump();
      await tester.tap(find.text('Conectar'));
      await tester.pumpAndSettle();

      expect(result, '654321');
    });

    testWidgets('onValidate returning error keeps dialog open with message',
        (tester) async {
      await tester.pumpWidget(
        dialogTrigger(
          (_) => PinEntryDialog(
            onValidate: (pin) async => 'PIN incorrecto',
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '000000');
      await tester.pump();
      await tester.tap(find.text('Conectar'));
      await tester.pumpAndSettle();

      expect(find.text('PIN incorrecto'), findsOneWidget);
      // Dialog still open
      expect(find.text('Conectar'), findsOneWidget);
    });

    testWidgets('onValidate returning null closes dialog with PIN', (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await showDialog<String>(
                    context: ctx,
                    builder: (_) => PinEntryDialog(
                      onValidate: (pin) async => null, // success
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      await tester.tap(find.text('Conectar'));
      await tester.pumpAndSettle();

      expect(result, '123456');
    });

    testWidgets('initial error message is shown when passed via constructor',
        (tester) async {
      await tester.pumpWidget(
        dialogTrigger(
          (_) => const PinEntryDialog(error: 'PIN expirado'),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('PIN expirado'), findsOneWidget);
    });

    testWidgets('error message clears when user starts typing', (tester) async {
      await tester.pumpWidget(
        dialogTrigger(
          (_) => const PinEntryDialog(error: 'PIN incorrecto'),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('PIN incorrecto'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '1');
      await tester.pump();

      expect(find.text('PIN incorrecto'), findsNothing);
    });
  });

  // ─── ServerModeWarningDialog ──────────────────────────────────────────────────

  group('ServerModeWarningDialog', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('renders title and bullet points', (tester) async {
      await tester.pumpWidget(
        dialogTrigger((_) => const ServerModeWarningDialog()),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Activar modo servidor'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
      expect(find.text('Encender'), findsOneWidget);
      expect(find.text('No volver a mostrar este aviso'), findsOneWidget);
    });

    testWidgets('Cancelar pops with null', (tester) async {
      bool? result = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await showDialog<bool>(
                    context: ctx,
                    builder: (_) => const ServerModeWarningDialog(),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });

    testWidgets('Encender pops with true', (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await showDialog<bool>(
                    context: ctx,
                    builder: (_) => const ServerModeWarningDialog(),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Encender'));
      await tester.pumpAndSettle();

      expect(result, true);
    });

    testWidgets('checkbox toggles dontShowAgain state', (tester) async {
      await tester.pumpWidget(
        dialogTrigger((_) => const ServerModeWarningDialog()),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Initial state: unchecked
      final checkboxBefore = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkboxBefore.value, false);

      // Tap the InkWell containing the checkbox
      await tester.tap(find.text('No volver a mostrar este aviso'));
      await tester.pumpAndSettle();

      final checkboxAfter = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkboxAfter.value, true);
    });

    testWidgets('Encender with dontShowAgain saves preference', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showDialog<bool>(
                  context: ctx,
                  builder: (_) => const ServerModeWarningDialog(),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Check "no mostrar" and confirm
      await tester.tap(find.text('No volver a mostrar este aviso'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Encender'));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('server_mode_warning_dismissed'), true);
    });
  });

  // ─── IncomingTransferDialog ──────────────────────────────────────────────────

  group('IncomingTransferDialog', () {
    const request = IncomingTransferRequest(
      transferId: 'txfr-001',
      from: 'client-abc',
      fromName: 'PC Escritorio',
      fileName: 'video.mp4',
      fileSize: 52428800, // 50 MB
      mimeType: 'video/mp4',
    );

    testWidgets('renders sender name and file info', (tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          IncomingTransferDialog(
            request: request,
            onAccept: () {},
            onReject: () {},
          ),
        ),
      );

      expect(find.text('Archivo entrante'), findsOneWidget);
      expect(find.text('PC Escritorio'), findsOneWidget);
      expect(find.text('video.mp4'), findsOneWidget);
      expect(find.text('Aceptar'), findsOneWidget);
      expect(find.text('Rechazar'), findsOneWidget);
    });

    testWidgets('Aceptar button calls onAccept', (tester) async {
      bool accepted = false;
      await tester.pumpWidget(
        wrapWithApp(
          IncomingTransferDialog(
            request: request,
            onAccept: () => accepted = true,
            onReject: () {},
          ),
        ),
      );

      await tester.tap(find.text('Aceptar'));
      await tester.pump();

      expect(accepted, true);
    });

    testWidgets('Rechazar button calls onReject', (tester) async {
      bool rejected = false;
      await tester.pumpWidget(
        wrapWithApp(
          IncomingTransferDialog(
            request: request,
            onAccept: () {},
            onReject: () => rejected = true,
          ),
        ),
      );

      await tester.tap(find.text('Rechazar'));
      await tester.pump();

      expect(rejected, true);
    });

    testWidgets('shows file size formatted', (tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          IncomingTransferDialog(
            request: request,
            onAccept: () {},
            onReject: () {},
          ),
        ),
      );

      // 52428800 bytes = 50 MB
      expect(find.textContaining('50 MB'), findsOneWidget);
    });

    testWidgets('show static method returns true on accept', (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await IncomingTransferDialog.show(ctx, request);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();

      expect(result, true);
    });

    testWidgets('show static method returns false on reject', (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await IncomingTransferDialog.show(ctx, request);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rechazar'));
      await tester.pumpAndSettle();

      expect(result, false);
    });
  });

  // ─── QrFooter ────────────────────────────────────────────────────────────────

  group('QrFooter', () {
    testWidgets('renders SizedBox.shrink when config is null', (tester) async {
      await tester.pumpWidget(wrapWithApp(const QrFooter(config: null)));

      // No URL title should be visible
      expect(find.text('Accedé desde otro dispositivo'), findsNothing);
      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets('renders QR and URL title with valid config', (tester) async {
      const config = AppConfig(
        appName: 'SrvFiles',
        lanIp: '192.168.1.50',
        port: 3001,
        frontendPort: 5173,
        maxFileSizeMb: 50,
        lanUrl: 'http://192.168.1.50:3001',
      );

      await tester.pumpWidget(wrapWithApp(const QrFooter(config: config)));

      expect(find.text('Accedé desde otro dispositivo'), findsOneWidget);
    });

    testWidgets('renders copyright text with valid config', (tester) async {
      const config = AppConfig(
        appName: 'SrvFiles',
        lanIp: '192.168.1.1',
        port: 3001,
        frontendPort: 5173,
        maxFileSizeMb: 100,
        lanUrl: 'http://192.168.1.1:3001',
      );

      await tester.pumpWidget(wrapWithApp(const QrFooter(config: config)));

      expect(find.textContaining('Carlos David Sandoval'), findsOneWidget);
      expect(find.textContaining('github.com/dotdeivid'), findsOneWidget);
    });
  });
}
