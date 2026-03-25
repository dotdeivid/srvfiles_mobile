import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srvfiles_mobile/theme/app_theme.dart';
import 'package:srvfiles_mobile/widgets/gradient_text.dart';
import 'package:srvfiles_mobile/widgets/glass_card.dart';
import 'package:srvfiles_mobile/widgets/search_bar.dart';
import 'package:srvfiles_mobile/widgets/disk_stats_bar.dart';
import 'package:srvfiles_mobile/widgets/file_list_item.dart';
import 'package:srvfiles_mobile/widgets/file_grid_item.dart';
import 'package:srvfiles_mobile/widgets/pulsing_dot.dart';
import 'package:srvfiles_mobile/widgets/skeleton_loader.dart';
import 'package:srvfiles_mobile/models/file_info.dart';
import 'package:srvfiles_mobile/models/disk_stats.dart';
import 'package:srvfiles_mobile/models/transfer_client.dart';
import 'package:srvfiles_mobile/widgets/online_clients.dart';

/// Helper para envolver widgets en MaterialApp con el tema de SrvFiles.
Widget wrapWithApp(Widget child) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(body: child),
  );
}

void main() {
  group('GradientText', () {
    testWidgets('renders text', (tester) async {
      await tester.pumpWidget(wrapWithApp(
        const GradientText('SrvFiles'),
      ));

      expect(find.text('SrvFiles'), findsOneWidget);
    });

    testWidgets('uses ShaderMask', (tester) async {
      await tester.pumpWidget(wrapWithApp(
        const GradientText('Test'),
      ));

      expect(find.byType(ShaderMask), findsOneWidget);
    });
  });

  group('GlassCard', () {
    testWidgets('renders child', (tester) async {
      await tester.pumpWidget(wrapWithApp(
        const GlassCard(child: Text('Card content')),
      ));

      expect(find.text('Card content'), findsOneWidget);
    });

    testWidgets('uses BackdropFilter', (tester) async {
      await tester.pumpWidget(wrapWithApp(
        const GlassCard(child: Text('Test')),
      ));

      expect(find.byType(BackdropFilter), findsOneWidget);
    });
  });

  group('FileSearchBar', () {
    testWidgets('renders with hint text', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(wrapWithApp(
        FileSearchBar(
          controller: controller,
          onChanged: (_) {},
        ),
      ));

      expect(find.text('Buscar archivos...'), findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('calls onChanged when typing', (tester) async {
      final controller = TextEditingController();
      String? lastValue;
      await tester.pumpWidget(wrapWithApp(
        FileSearchBar(
          controller: controller,
          onChanged: (v) => lastValue = v,
        ),
      ));

      await tester.enterText(find.byType(TextField), 'test');
      expect(lastValue, 'test');
    });
  });

  group('DiskStatsBar', () {
    testWidgets('renders nothing when stats is null', (tester) async {
      await tester.pumpWidget(wrapWithApp(
        const DiskStatsBar(stats: null),
      ));

      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets('renders stats text when provided', (tester) async {
      const stats = DiskStats(total: 1073741824, used: 536870912, free: 536870912);
      await tester.pumpWidget(wrapWithApp(
        const DiskStatsBar(stats: stats),
      ));

      // Should show "512 MB / 1 GB"
      expect(find.textContaining('512 MB'), findsOneWidget);
      expect(find.textContaining('1 GB'), findsOneWidget);
    });
  });

  group('FileListItem', () {
    testWidgets('renders file name and size', (tester) async {
      const file = FileInfo(
        name: 'documento.pdf',
        size: 5242880,
        createdAt: '2026-03-20T10:00:00Z',
        downloadUrl: '/api/files/download/documento.pdf',
      );

      await tester.pumpWidget(wrapWithApp(
        FileListItem(
          file: file,
          onDownload: () {},
          onShare: () {},
        ),
      ));

      expect(find.text('documento.pdf'), findsOneWidget);
      expect(find.text('5 MB'), findsOneWidget);
      expect(find.text('📄'), findsOneWidget); // PDF icon
    });

    testWidgets('calls onDownload when tapped', (tester) async {
      bool downloadTapped = false;
      const file = FileInfo(
        name: 'test.txt',
        size: 100,
        createdAt: '2026-03-20T10:00:00Z',
        downloadUrl: '/test',
      );

      await tester.pumpWidget(wrapWithApp(
        FileListItem(
          file: file,
          onDownload: () => downloadTapped = true,
          onShare: () {},
        ),
      ));

      await tester.tap(find.byIcon(Icons.download_rounded));
      expect(downloadTapped, true);
    });

    testWidgets('calls onShare when tapped', (tester) async {
      bool shareTapped = false;
      const file = FileInfo(
        name: 'test.txt',
        size: 100,
        createdAt: '2026-03-20T10:00:00Z',
        downloadUrl: '/test',
      );

      await tester.pumpWidget(wrapWithApp(
        FileListItem(
          file: file,
          onDownload: () {},
          onShare: () => shareTapped = true,
        ),
      ));

      await tester.tap(find.byIcon(Icons.share_rounded));
      expect(shareTapped, true);
    });
  });

  group('FileGridItem', () {
    testWidgets('renders file name, size and icon', (tester) async {
      const file = FileInfo(
        name: 'imagen.png',
        size: 1048576,
        createdAt: '2026-03-20T10:00:00Z',
        downloadUrl: '/test',
      );

      await tester.pumpWidget(wrapWithApp(
        SizedBox(
          width: 200,
          height: 200,
          child: FileGridItem(
            file: file,
            onDownload: () {},
            onShare: () {},
          ),
        ),
      ));

      expect(find.text('imagen.png'), findsOneWidget);
      expect(find.text('1 MB'), findsOneWidget);
      expect(find.text('🖼️'), findsOneWidget);
    });
  });

  group('PulsingDot', () {
    testWidgets('renders and animates', (tester) async {
      await tester.pumpWidget(wrapWithApp(
        const PulsingDot(size: 10),
      ));

      expect(find.byType(PulsingDot), findsOneWidget);

      // Advance animation
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
    });
  });

  group('SkeletonLoader', () {
    testWidgets('renders skeleton elements', (tester) async {
      await tester.pumpWidget(wrapWithApp(
        const SkeletonLoader(),
      ));

      expect(find.byType(SkeletonLoader), findsOneWidget);

      // Advance animation
      await tester.pump(const Duration(milliseconds: 500));
    });
  });

  group('OnlineClients', () {
    testWidgets('shows nothing when no other clients', (tester) async {
      await tester.pumpWidget(wrapWithApp(
        OnlineClients(
          clients: const [
            TransferClient(
              clientId: 'me',
              appName: 'Mi Celular',
              receiving: true,
              ip: '192.168.1.10',
            ),
          ],
          myClientId: 'me',
          activeTransfer: null,
          onSendFile: (a, b) {},
          onCancelTransfer: () {},
        ),
      ));

      // Should render SizedBox.shrink (nothing visible)
      expect(find.text('Dispositivos conectados'), findsNothing);
    });

    testWidgets('shows desktop icon for desktop client', (tester) async {
      await tester.pumpWidget(wrapWithApp(
        OnlineClients(
          clients: const [
            TransferClient(
              clientId: 'me',
              appName: 'Mi Celular',
              receiving: true,
              ip: '192.168.1.10',
              deviceType: 'mobile',
            ),
            TransferClient(
              clientId: 'other',
              appName: 'MacBook Air',
              receiving: true,
              ip: '192.168.1.20',
              deviceType: 'desktop',
            ),
          ],
          myClientId: 'me',
          activeTransfer: null,
          onSendFile: (a, b) {},
          onCancelTransfer: () {},
        ),
      ));

      expect(find.text('MacBook Air'), findsOneWidget);
      expect(find.byIcon(Icons.language), findsOneWidget);
    });

    testWidgets('shows mobile icon for mobile client', (tester) async {
      await tester.pumpWidget(wrapWithApp(
        OnlineClients(
          clients: const [
            TransferClient(
              clientId: 'me',
              appName: 'PC',
              receiving: true,
              ip: '192.168.1.10',
            ),
            TransferClient(
              clientId: 'other',
              appName: 'Galaxy S23',
              receiving: true,
              ip: '192.168.1.30',
              deviceType: 'mobile',
            ),
          ],
          myClientId: 'me',
          activeTransfer: null,
          onSendFile: (a, b) {},
          onCancelTransfer: () {},
        ),
      ));

      expect(find.text('Galaxy S23'), findsOneWidget);
      expect(find.byIcon(Icons.phone_android), findsOneWidget);
    });

    testWidgets('shows multiple peers with correct icons', (tester) async {
      await tester.pumpWidget(wrapWithApp(
        OnlineClients(
          clients: const [
            TransferClient(
              clientId: 'me',
              appName: 'Me',
              receiving: true,
              ip: '192.168.1.1',
            ),
            TransferClient(
              clientId: 'pc1',
              appName: 'Desktop',
              receiving: true,
              ip: '192.168.1.2',
              deviceType: 'desktop',
            ),
            TransferClient(
              clientId: 'phone1',
              appName: 'Phone',
              receiving: true,
              ip: '192.168.1.3',
              deviceType: 'mobile',
            ),
          ],
          myClientId: 'me',
          activeTransfer: null,
          onSendFile: (a, b) {},
          onCancelTransfer: () {},
        ),
      ));

      expect(find.text('Desktop'), findsOneWidget);
      expect(find.text('Phone'), findsOneWidget);
      expect(find.byIcon(Icons.language), findsOneWidget);
      expect(find.byIcon(Icons.phone_android), findsOneWidget);
    });
  });

  group('FileListItem with onDelete', () {
    testWidgets('shows delete option in context menu', (tester) async {
      bool deleteCalled = false;
      const file = FileInfo(
        name: 'received.pdf',
        size: 1024,
        createdAt: '2026-03-20T10:00:00Z',
        downloadUrl: '/test/received.pdf',
      );

      await tester.pumpWidget(wrapWithApp(
        FileListItem(
          file: file,
          onDownload: () {},
          onShare: () {},
          onDelete: () => deleteCalled = true,
        ),
      ));

      // Long-press to open context menu
      await tester.longPress(find.text('received.pdf'));
      await tester.pumpAndSettle();

      expect(find.text('Eliminar'), findsOneWidget);

      // Tap delete
      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();

      expect(deleteCalled, true);
    });

    testWidgets('does not show delete option when onDelete is null', (tester) async {
      const file = FileInfo(
        name: 'server_file.pdf',
        size: 1024,
        createdAt: '2026-03-20T10:00:00Z',
        downloadUrl: '/test/server_file.pdf',
      );

      await tester.pumpWidget(wrapWithApp(
        FileListItem(
          file: file,
          onDownload: () {},
          onShare: () {},
        ),
      ));

      // Long-press to open context menu
      await tester.longPress(find.text('server_file.pdf'));
      await tester.pumpAndSettle();

      expect(find.text('Eliminar'), findsNothing);
    });
  });
}
