import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:srvfiles_mobile/theme/app_theme.dart';
import 'package:srvfiles_mobile/screens/splash_screen.dart';

/// Wraps the SplashScreen but does NOT navigate (avoids HomeScreen load).
/// We intercept routes so the tests stay within the splash.
Widget buildApp() {
  return MaterialApp(
    theme: AppTheme.dark,
    home: const SplashScreen(),
    onGenerateRoute: (settings) {
      // Return a blank page for any navigation so we don't load HomeScreen
      return MaterialPageRoute(builder: (_) => const Scaffold(body: SizedBox()));
    },
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SplashScreen', () {
    testWidgets('shows SrvFiles brand title', (tester) async {
      await tester.pumpWidget(buildApp());
      // Pump once so initState starts
      await tester.pump();

      expect(find.text('SrvFiles'), findsOneWidget);
    });

    testWidgets('shows searching indicator initially', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      // While scanning, should show "Buscando servidores..."
      expect(find.text('Buscando servidores...'), findsOneWidget);
    });

    testWidgets('shows IP input field and Conectar button', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Conectar'), findsOneWidget);
    });

    testWidgets('shows Envío directo and server mode buttons', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      expect(find.text('Envío directo'), findsOneWidget);
      expect(find.text('Usar este dispositivo como servidor'), findsOneWidget);
    });

    testWidgets('Conectar button is disabled while scanning', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      // During scanning, the ElevatedButton should be disabled
      final btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Conectar'),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('renders folder icon', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      expect(find.byIcon(Icons.folder_shared_rounded), findsOneWidget);
    });

    testWidgets('has IP hint text in text field', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      expect(find.text('192.168.1.x:3001'), findsOneWidget);
    });
  });
}
