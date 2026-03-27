import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srvfiles_mobile/theme/app_theme.dart';
import 'package:srvfiles_mobile/widgets/upload_sheet.dart';

Widget wrapWithApp(Widget child) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(body: child),
  );
}

/// Creates a real temporary file with [content] so lengthSync() works.
File _tmpFile(Directory dir, String name, String content) {
  final file = File('${dir.path}/$name');
  file.writeAsStringSync(content);
  return file;
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('upload_sheet_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('UploadSheet', () {
    testWidgets('shows single file count in header', (tester) async {
      final file = _tmpFile(tempDir, 'document.pdf', 'hello');

      await tester.pumpWidget(wrapWithApp(
        UploadSheet(
          files: [file],
          uploading: false,
          uploadProgress: 0,
          onRemove: (_) {},
          onClearAll: () {},
          onUpload: () {},
        ),
      ));

      expect(find.text('1 archivo seleccionado'), findsOneWidget);
    });

    testWidgets('shows plural file count for multiple files', (tester) async {
      final f1 = _tmpFile(tempDir, 'a.txt', 'aa');
      final f2 = _tmpFile(tempDir, 'b.txt', 'bb');

      await tester.pumpWidget(wrapWithApp(
        UploadSheet(
          files: [f1, f2],
          uploading: false,
          uploadProgress: 0,
          onRemove: (_) {},
          onClearAll: () {},
          onUpload: () {},
        ),
      ));

      expect(find.text('2 archivos seleccionados'), findsOneWidget);
    });

    testWidgets('renders filename and size for each file', (tester) async {
      final file = _tmpFile(tempDir, 'photo.jpg', 'x' * 1024);

      await tester.pumpWidget(wrapWithApp(
        UploadSheet(
          files: [file],
          uploading: false,
          uploadProgress: 0,
          onRemove: (_) {},
          onClearAll: () {},
          onUpload: () {},
        ),
      ));

      expect(find.text('photo.jpg'), findsOneWidget);
    });

    testWidgets('shows Limpiar button when not uploading', (tester) async {
      final file = _tmpFile(tempDir, 'test.txt', 'data');

      await tester.pumpWidget(wrapWithApp(
        UploadSheet(
          files: [file],
          uploading: false,
          uploadProgress: 0,
          onRemove: (_) {},
          onClearAll: () {},
          onUpload: () {},
        ),
      ));

      expect(find.text('Limpiar'), findsOneWidget);
    });

    testWidgets('hides Limpiar button while uploading', (tester) async {
      final file = _tmpFile(tempDir, 'test.txt', 'data');

      await tester.pumpWidget(wrapWithApp(
        UploadSheet(
          files: [file],
          uploading: true,
          uploadProgress: 0.5,
          onRemove: (_) {},
          onClearAll: () {},
          onUpload: () {},
        ),
      ));

      expect(find.text('Limpiar'), findsNothing);
    });

    testWidgets('calls onClearAll when Limpiar tapped', (tester) async {
      bool cleared = false;
      final file = _tmpFile(tempDir, 'test.txt', 'x');

      await tester.pumpWidget(wrapWithApp(
        UploadSheet(
          files: [file],
          uploading: false,
          uploadProgress: 0,
          onRemove: (_) {},
          onClearAll: () => cleared = true,
          onUpload: () {},
        ),
      ));

      await tester.tap(find.text('Limpiar'));
      expect(cleared, true);
    });

    testWidgets('shows Subir button when not uploading', (tester) async {
      final file = _tmpFile(tempDir, 'test.txt', 'data');

      await tester.pumpWidget(wrapWithApp(
        UploadSheet(
          files: [file],
          uploading: false,
          uploadProgress: 0,
          onRemove: (_) {},
          onClearAll: () {},
          onUpload: () {},
        ),
      ));

      expect(find.textContaining('Subir'), findsOneWidget);
    });

    testWidgets('calls onUpload when Subir button tapped', (tester) async {
      bool uploaded = false;
      final file = _tmpFile(tempDir, 'upload_me.txt', 'content');

      await tester.pumpWidget(wrapWithApp(
        UploadSheet(
          files: [file],
          uploading: false,
          uploadProgress: 0,
          onRemove: (_) {},
          onClearAll: () {},
          onUpload: () => uploaded = true,
        ),
      ));

      await tester.tap(find.widgetWithText(ElevatedButton, find
          .textContaining('Subir')
          .evaluate()
          .first
          .widget
          .toString()
          .isNotEmpty
          ? (find
              .textContaining('Subir')
              .evaluate()
              .first
              .widget as Text)
              .data!
          : 'Subir archivo (4 B)'));
      expect(uploaded, true);
    });

    testWidgets('calls onUpload via ElevatedButton icon', (tester) async {
      bool uploaded = false;
      final file = _tmpFile(tempDir, 'upload_me.txt', 'content');

      await tester.pumpWidget(wrapWithApp(
        UploadSheet(
          files: [file],
          uploading: false,
          uploadProgress: 0,
          onRemove: (_) {},
          onClearAll: () {},
          onUpload: () => uploaded = true,
        ),
      ));

      await tester.tap(find.byIcon(Icons.upload_rounded));
      expect(uploaded, true);
    });

    testWidgets('shows remove button per file when not uploading', (tester) async {
      final f1 = _tmpFile(tempDir, 'a.txt', 'a');
      final f2 = _tmpFile(tempDir, 'b.txt', 'b');

      await tester.pumpWidget(wrapWithApp(
        UploadSheet(
          files: [f1, f2],
          uploading: false,
          uploadProgress: 0,
          onRemove: (_) {},
          onClearAll: () {},
          onUpload: () {},
        ),
      ));

      expect(find.byIcon(Icons.close), findsNWidgets(2));
    });

    testWidgets('hides remove buttons while uploading', (tester) async {
      final f1 = _tmpFile(tempDir, 'a.txt', 'a');
      final f2 = _tmpFile(tempDir, 'b.txt', 'b');

      await tester.pumpWidget(wrapWithApp(
        UploadSheet(
          files: [f1, f2],
          uploading: true,
          uploadProgress: 0.3,
          onRemove: (_) {},
          onClearAll: () {},
          onUpload: () {},
        ),
      ));

      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('calls onRemove with correct index when close tapped', (tester) async {
      int? removedIndex;
      final f1 = _tmpFile(tempDir, 'first.txt', 'a');
      final f2 = _tmpFile(tempDir, 'second.txt', 'b');

      await tester.pumpWidget(wrapWithApp(
        UploadSheet(
          files: [f1, f2],
          uploading: false,
          uploadProgress: 0,
          onRemove: (i) => removedIndex = i,
          onClearAll: () {},
          onUpload: () {},
        ),
      ));

      // Tap the first close icon
      await tester.tap(find.byIcon(Icons.close).first);
      expect(removedIndex, 0);
    });

    testWidgets('shows progress bar and percentage while uploading', (tester) async {
      final file = _tmpFile(tempDir, 'file.txt', 'data');

      await tester.pumpWidget(wrapWithApp(
        UploadSheet(
          files: [file],
          uploading: true,
          uploadProgress: 0.75,
          onRemove: (_) {},
          onClearAll: () {},
          onUpload: () {},
        ),
      ));

      expect(find.text('75%'), findsOneWidget);
      // Subir button should be hidden
      expect(find.byIcon(Icons.upload_rounded), findsNothing);
    });

    testWidgets('shows 0% when progress is 0', (tester) async {
      final file = _tmpFile(tempDir, 'file.txt', 'data');

      await tester.pumpWidget(wrapWithApp(
        UploadSheet(
          files: [file],
          uploading: true,
          uploadProgress: 0.0,
          onRemove: (_) {},
          onClearAll: () {},
          onUpload: () {},
        ),
      ));

      expect(find.text('0%'), findsOneWidget);
    });

    testWidgets('shows 100% when progress is 1', (tester) async {
      final file = _tmpFile(tempDir, 'file.txt', 'data');

      await tester.pumpWidget(wrapWithApp(
        UploadSheet(
          files: [file],
          uploading: true,
          uploadProgress: 1.0,
          onRemove: (_) {},
          onClearAll: () {},
          onUpload: () {},
        ),
      ));

      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('shows overLimit warning when file exceeds maxFileSizeMb', (tester) async {
      // Create a file whose content makes it > 1 byte limit
      final file = _tmpFile(tempDir, 'large.mp4', 'x' * 100);

      await tester.pumpWidget(wrapWithApp(
        UploadSheet(
          files: [file],
          uploading: false,
          uploadProgress: 0,
          maxFileSizeMb: 0, // 0 MB limit → everything exceeds
          onRemove: (_) {},
          onClearAll: () {},
          onUpload: () {},
        ),
      ));

      expect(find.textContaining('excede el límite'), findsOneWidget);
    });

    testWidgets('no overLimit warning when file is within limit', (tester) async {
      final file = _tmpFile(tempDir, 'small.txt', 'tiny');

      await tester.pumpWidget(wrapWithApp(
        UploadSheet(
          files: [file],
          uploading: false,
          uploadProgress: 0,
          maxFileSizeMb: 100, // 100 MB limit
          onRemove: (_) {},
          onClearAll: () {},
          onUpload: () {},
        ),
      ));

      expect(find.textContaining('excede el límite'), findsNothing);
    });

    testWidgets('Subir label shows archivos (plural) for multiple files', (tester) async {
      final f1 = _tmpFile(tempDir, 'x.txt', 'aa');
      final f2 = _tmpFile(tempDir, 'y.txt', 'bb');

      await tester.pumpWidget(wrapWithApp(
        UploadSheet(
          files: [f1, f2],
          uploading: false,
          uploadProgress: 0,
          onRemove: (_) {},
          onClearAll: () {},
          onUpload: () {},
        ),
      ));

      expect(find.textContaining('2 archivos'), findsAtLeastNWidgets(1));
    });
  });
}
