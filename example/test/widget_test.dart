import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_incall_manager_example/main.dart';

void main() {
  testWidgets('Verify InCall Manager Demo app title', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const InCallManagerDemoApp());

    // Verify that the title is present.
    expect(find.text('InCall Manager Demo'), findsAtLeastNWidgets(1));
  });
}
