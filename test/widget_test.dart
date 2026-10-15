import 'package:flutter_test/flutter_test.dart';

import 'package:peng/main.dart';

void main() {
  testWidgets('Peng app shows quiz entry point', (WidgetTester tester) async {
    await tester.pumpWidget(const PengApp());

    expect(find.text('Peng'), findsOneWidget);
    expect(find.byType(StudyDatesPage), findsOneWidget);
  });
}
