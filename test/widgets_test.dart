import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:srvfiles_mobile/features/files/files_controller.dart' show StagedFile;
import 'package:srvfiles_mobile/models/active_transfer.dart';
import 'package:srvfiles_mobile/models/app_config.dart';
import 'package:srvfiles_mobile/models/transfer_client.dart';
import 'package:srvfiles_mobile/models/transfer_request.dart';
import 'package:srvfiles_mobile/theme/app_theme.dart';
import 'package:srvfiles_mobile/widgets/incoming_transfer_dialog.dart';
import 'package:srvfiles_mobile/widgets/online_clients.dart';
import 'package:srvfiles_mobile/widgets/pin_entry_dialog.dart';
import 'package:srvfiles_mobile/widgets/qr_footer.dart';
import 'package:srvfiles_mobile/widgets/server_mode_warning_dialog.dart';
import 'package:srvfiles_mobile/widgets/upload_sheet.dart';

/// Comportamiento de los widgets con lógica propia. Los puramente visuales
/// (gradientes, skeletons, animaciones) no se prueban.

Widget app(Widget child) =>
    MaterialApp(theme: AppTheme.dark, home: Scaffold(body: child));

/// Abre un diálogo desde un botón y guarda lo que devuelve en [onResult].
Widget dialogHost<T>(Future<T?> Function(BuildContext) open, void Function(T?) onResult) =>
    MaterialApp(
      theme: AppTheme.dark,
      home: Builder(
        builder: (ctx) => Scaffold(
          body: ElevatedButton(
            onPressed: () async => onResult(await open(ctx)),
            child: const Text('Abrir'),
          ),
        ),
      ),
    );

void main() {
  group('UploadSheet', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('upload_sheet_'));
    tearDown(() => dir.deleteSync(recursive: true));

    StagedFile staged(String name, int size) =>
        StagedFile(File('${dir.path}/$name')..writeAsStringSync('x'), name, size);

    Widget sheet(List<StagedFile> files, {int? maxMb, bool uploading = false, VoidCallback? onCancel,
        void Function(int)? onRemove}) {
      return app(UploadSheet(
        files: files,
        uploading: uploading,
        uploadProgress: 0.4,
        maxFileSizeMb: maxMb,
        onRemove: onRemove ?? (_) {},
        onClearAll: () {},
        onUpload: () {},
        onCancel: onCancel,
      ));
    }

    ElevatedButton uploadButton(WidgetTester tester) => tester.widget<ElevatedButton>(
          find.ancestor(of: find.byIcon(Icons.upload_rounded), matching: find.byType(ElevatedButton)),
        );

    testWidgets('a file over the limit is flagged and blocks the upload', (tester) async {
      await tester.pumpWidget(sheet([staged('video.mp4', 2 * 1024 * 1024)], maxMb: 1));
      expect(find.textContaining('excede el límite'), findsOneWidget);
      expect(uploadButton(tester).onPressed, isNull);
    });

    testWidgets('maxFileSizeMb 0 means no limit', (tester) async {
      await tester.pumpWidget(sheet([staged('video.mp4', 2 * 1024 * 1024)], maxMb: 0));
      expect(find.textContaining('excede el límite'), findsNothing);
      expect(uploadButton(tester).onPressed, isNotNull);
    });

    testWidgets('remove passes the right index', (tester) async {
      int? removed;
      await tester.pumpWidget(sheet([staged('a.txt', 1), staged('b.txt', 1)], onRemove: (i) => removed = i));
      await tester.tap(find.byIcon(Icons.close).last);
      expect(removed, 1);
    });

    testWidgets('while uploading: progress and cancel, no editing', (tester) async {
      var cancelled = false;
      await tester.pumpWidget(sheet([staged('a.txt', 1)], uploading: true, onCancel: () => cancelled = true));
      expect(find.text('40%'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.text('Limpiar'), findsNothing);
      await tester.tap(find.text('Cancelar'));
      expect(cancelled, true);
    });
  });

  group('IncomingTransferDialog', () {
    const request = IncomingTransferRequest(
      transferId: 't1', from: 'c1', fromName: 'PC Escritorio',
      fileName: 'video.mp4', fileSize: 52428800, mimeType: 'video/mp4',
    );

    testWidgets('returns true on accept and false on reject', (tester) async {
      final results = <bool?>[];
      await tester.pumpWidget(dialogHost<bool>(
        (ctx) => IncomingTransferDialog.show(ctx, request),
        results.add,
      ));
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(find.text('PC Escritorio'), findsOneWidget);
      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rechazar'));
      await tester.pumpAndSettle();

      expect(results, [true, false]);
    });

    testWidgets('closes itself with null when the sender cancels', (tester) async {
      final dismissed = Completer<void>();
      final results = <bool?>[];
      await tester.pumpWidget(dialogHost<bool>(
        (ctx) => IncomingTransferDialog.show(ctx, request, dismissed: dismissed.future),
        results.add,
      ));
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      dismissed.complete();
      await tester.pumpAndSettle();

      expect(find.text('Aceptar'), findsNothing);
      expect(results, [null]);
    });
  });

  group('PinEntryDialog', () {
    testWidgets('validation error keeps it open; success returns the PIN', (tester) async {
      final attempts = <String>[];
      String? result;
      await tester.pumpWidget(dialogHost<String>(
        (ctx) => PinEntryDialog.show(ctx, onValidate: (pin) async {
          attempts.add(pin);
          return pin == '123456' ? null : 'PIN incorrecto';
        }),
        (r) => result = r,
      ));
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '123');
      await tester.tap(find.text('Conectar'));
      await tester.pumpAndSettle();
      expect(attempts, isEmpty); // menos de 6 dígitos no se envía

      await tester.enterText(find.byType(TextField), '000000');
      await tester.tap(find.text('Conectar'));
      await tester.pumpAndSettle();
      expect(find.text('PIN incorrecto'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('Conectar'));
      await tester.pumpAndSettle();
      expect(result, '123456');
      expect(attempts, ['000000', '123456']);
    });
  });

  testWidgets('ServerModeWarningDialog remembers "no volver a mostrar"', (tester) async {
    SharedPreferences.setMockInitialValues({});
    bool? result;
    await tester.pumpWidget(dialogHost<bool>(
      (ctx) => showDialog<bool>(context: ctx, builder: (_) => const ServerModeWarningDialog()),
      (r) => result = r,
    ));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No volver a mostrar este aviso'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Encender'));
    await tester.pumpAndSettle();

    expect(result, true);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('server_mode_warning_dismissed'), true);
  });

  group('QrFooter', () {
    AppConfig config(String ip) => AppConfig(
          appName: 'SrvFiles', lanIp: ip, port: 3001, frontendPort: 5173,
          maxFileSizeMb: 0, lanUrl: '',
        );

    testWidgets('encodes the frontend port', (tester) async {
      await tester.pumpWidget(app(SingleChildScrollView(child: QrFooter(config: config('192.168.1.50')))));
      expect(find.text('http://192.168.1.50:5173'), findsOneWidget);
    });

    testWidgets('is hidden without a LAN IP', (tester) async {
      await tester.pumpWidget(app(QrFooter(config: config(''))));
      expect(find.text('Accedé desde otro dispositivo'), findsNothing);
    });
  });

  group('OnlineClients', () {
    const me = TransferClient(clientId: 'me', appName: 'Yo', receiving: true, ip: '1');
    const peer = TransferClient(clientId: 'p1', appName: 'Laptop', receiving: true, ip: '2');

    testWidgets('hides itself when I am the only client', (tester) async {
      await tester.pumpWidget(app(OnlineClients(
        clients: const [me], myClientId: 'me', activeTransfer: null,
        onSendFile: (_, _) {}, onCancelTransfer: () {},
      )));
      expect(find.text('Dispositivos conectados'), findsNothing);
    });

    testWidgets('send targets the peer; an active transfer offers cancel', (tester) async {
      String? target;
      var cancelled = false;
      await tester.pumpWidget(app(OnlineClients(
        clients: const [me, peer], myClientId: 'me', activeTransfer: null,
        onSendFile: (id, _) => target = id, onCancelTransfer: () => cancelled = true,
      )));
      await tester.tap(find.text('Enviar'));
      expect(target, 'p1');

      await tester.pumpWidget(app(OnlineClients(
        clients: const [me, peer], myClientId: 'me',
        activeTransfer: const ActiveTransfer(
          transferId: 't', fileName: 'a.bin', fileSize: 10, progress: 30,
          direction: TransferDirection.sending, peerName: 'Laptop', peerId: 'p1', waiting: false,
        ),
        onSendFile: (_, _) {}, onCancelTransfer: () => cancelled = true,
      )));
      expect(find.text('30%'), findsOneWidget);
      await tester.tap(find.byTooltip('Cancelar transferencia'));
      expect(cancelled, true);
    });
  });
}
