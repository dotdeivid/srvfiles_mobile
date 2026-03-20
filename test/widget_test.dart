import 'package:flutter_test/flutter_test.dart';

import 'package:srvfiles_mobile/main.dart';

void main() {
  testWidgets('App renders SrvFiles text', (WidgetTester tester) async {
    await tester.pumpWidget(const SrvFilesApp());
    expect(find.text('SrvFiles'), findsOneWidget);
  });
}
