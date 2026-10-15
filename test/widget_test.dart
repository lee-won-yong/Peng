import 'package:flutter_test/flutter_test.dart';

import 'package:peng/main.dart';

void main() {
  testWidgets('Peng app shows scan entry point', (WidgetTester tester) async {
    await tester.pumpWidget(const PengApp());

    expect(find.text('Peng'), findsOneWidget);
    expect(find.text('책 한 페이지를 찍고 단어를 모아요'), findsOneWidget);
    expect(find.text('사진 찍기'), findsOneWidget);
    expect(find.text('앨범'), findsOneWidget);
  });
}
