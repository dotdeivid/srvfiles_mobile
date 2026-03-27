import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:srvfiles_mobile/theme/app_theme.dart';
import 'package:srvfiles_mobile/screens/home_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'srvfiles-device-name': 'Mi Celular',
    });
  });

  Widget buildApp({String? serverUrl, bool autoServerMode = false}) {
    return MaterialApp(
      theme: AppTheme.dark,
      home: HomeScreen(serverUrl: serverUrl, autoServerMode: autoServerMode),
      onGenerateRoute: (settings) {
        // Intercept any navigation away from HomeScreen
        return MaterialPageRoute(
          builder: (_) => const Scaffold(body: SizedBox()),
        );
      },
    );
  }

  group('HomeScreen (null server — direct mode)', () {
    testWidgets('renders without crashing in direct mode', (tester) async {
      await tester.pumpWidget(buildApp(serverUrl: null));
      // Let initState run one frame
      await tester.pump();

      // Should still be alive — no crash
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('shows SrvFiles app bar title', (tester) async {
      await tester.pumpWidget(buildApp(serverUrl: null));
      await tester.pump();

      // The AppBar or header should contain SrvFiles
      expect(find.text('SrvFiles'), findsAtLeastNWidgets(1));
    });
  });
}
