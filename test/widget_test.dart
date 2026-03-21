import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srvfiles_mobile/main.dart';

void main() {
  testWidgets('App renders SplashScreen with SrvFiles title', (WidgetTester tester) async {
    // Mock SharedPreferences
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getAll') {
          return <String, dynamic>{};
        }
        return null;
      },
    );

    await tester.pumpWidget(const SrvFilesApp());
    await tester.pump();

    expect(find.text('SrvFiles'), findsOneWidget);

    // Avanzar los timers pendientes (Future.delayed 3s del splash)
    await tester.pump(const Duration(seconds: 4));
    // Drenar cualquier frame restante
    await tester.pump(const Duration(seconds: 1));
  });
}
