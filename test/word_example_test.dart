import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peng/main.dart';

void main() {
  testWidgets('word opens example dialog and reads the complete sentence', (
    tester,
  ) async {
    final spoken = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WordListPage(
            words: const [
              VocabWord(
                word: 'bird',
                meaning: '새',
                example: 'The bird is in a tree.',
              ),
            ],
            onSpeak: spoken.add,
          ),
        ),
      ),
    );
    expect(find.text('The bird is in a tree.'), findsNothing);
    await tester.tap(find.text('bird'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('The bird is in a tree.'), findsOneWidget);
    await tester.tap(find.text('예문 듣기'));
    expect(spoken, ['The bird is in a tree.']);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
    'missing example disables speech instead of reading a placeholder',
    (tester) async {
      final spoken = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WordListPage(
              words: const [VocabWord(word: 'bird')],
              onSpeak: spoken.add,
            ),
          ),
        ),
      );
      await tester.tap(find.text('bird'));
      await tester.pumpAndSettle();
      expect(find.text('예문을 준비하고 있어요.'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '예문 듣기'))
            .onPressed,
        isNull,
      );
      expect(spoken, isEmpty);
    },
  );
}
