import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peng/main.dart';
import 'package:peng/character_puzzle.dart';

void main() {
  final words = List.generate(
    12,
    (i) => VocabWord(word: 'word$i', meaning: '뜻$i', example: 'Example $i.'),
  );

  Future<void> closePraise(WidgetTester tester) async {
    if (find.text('계속하기').evaluate().isNotEmpty) {
      await tester.tap(find.text('계속하기'));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('ten answers keep their number and complete exactly once', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var saves = 0;
    var completions = 0;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return QuizPage(
                words: words,
                onSpeak: (_) {},
                onAnswered: (_) async {
                  saves++;
                  return true;
                },
                hasParentPhone: false,
                onSendResult: (_, _) async {},
                onCompleted: () => completions++,
              );
            },
          ),
        ),
      ),
    );
    final character = tester
        .widget<CharacterPuzzle>(find.byType(CharacterPuzzle))
        .character;
    final revealed = <int>{};
    for (var number = 1; number <= 10; number++) {
      expect(find.text('$number / 10'), findsOneWidget);
      final prompt = tester
          .widget<Text>(
            find
                .descendant(of: find.byType(Card), matching: find.byType(Text))
                .first,
          )
          .data!;
      final target = words.firstWhere(
        (word) => word.word == prompt || word.meaning == prompt,
      );
      final answer = find.widgetWithText(
        OutlinedButton,
        prompt == target.word ? target.meaning : target.word,
      );
      await tester.ensureVisible(answer);
      await tester.tap(answer);
      await tester.pumpAndSettle();
      await closePraise(tester);
      final puzzle = tester.widget<CharacterPuzzle>(
        find.byType(CharacterPuzzle),
      );
      expect(puzzle.character, same(character));
      expect(puzzle.revealedPieces.length, number);
      expect(puzzle.revealedPieces.containsAll(revealed), isTrue);
      expect(puzzle.revealedPieces.difference(revealed).length, 1);
      revealed.addAll(puzzle.revealedPieces);
      // Answering must not advance the visible question number.
      expect(find.text('$number / 10'), findsOneWidget);
      expect(find.text('11 / 10'), findsNothing);
      expect(saves, number);
      expect(completions, 0);
      final next = find.text(number == 10 ? '결과 보기' : '다음 문제');
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
    }
    expect(find.text('학습 완료!'), findsOneWidget);
    expect(
      tester
          .widget<CharacterPuzzle>(find.byType(CharacterPuzzle))
          .revealedPieces,
      Set.of(List.generate(10, (index) => index)),
    );
    expect(saves, 10);
    expect(completions, 1);
    // Saving the completion badge rebuilds the parent in the real app.
    rebuild(() {});
    await tester.pumpAndSettle();
    expect(completions, 1);
    expect(find.text('다음 문제'), findsNothing);
    expect(find.text('결과 보기'), findsNothing);
    expect(find.text('11 / 10'), findsNothing);
    await tester.tap(find.text('다시 도전'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CharacterPuzzle>(find.byType(CharacterPuzzle))
          .revealedPieces,
      isEmpty,
    );
    expect(find.text('1 / 10'), findsOneWidget);
  });

  testWidgets(
    'failed answer save stays on the same question and permits retry',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var saves = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuizPage(
              words: words,
              onSpeak: (_) {},
              onAnswered: (_) async => ++saves > 1,
              hasParentPhone: false,
              onSendResult: (_, _) async {},
              onCompleted: () {},
            ),
          ),
        ),
      );
      final prompt = tester
          .widget<Text>(
            find
                .descendant(of: find.byType(Card), matching: find.byType(Text))
                .first,
          )
          .data!;
      final target = words.firstWhere(
        (word) => word.word == prompt || word.meaning == prompt,
      );
      // Choose a visible incorrect choice from the generated options instead.
      final choice = find
          .byType(OutlinedButton)
          .evaluate()
          .map((element) => element.widget as OutlinedButton)
          .firstWhere(
            (button) =>
                (button.child as Text).data !=
                (prompt == target.word ? target.meaning : target.word),
          );
      final wrongAnswer = find.byWidget(choice);
      await tester.ensureVisible(wrongAnswer);
      await tester.tap(wrongAnswer);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CharacterPuzzle>(find.byType(CharacterPuzzle))
            .revealedPieces,
        isEmpty,
      );
      expect(find.text('1 / 10'), findsOneWidget);
      expect(find.text('다음 문제'), findsNothing);
      await tester.tap(
        find.widgetWithText(OutlinedButton, (choice.child as Text).data!),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CharacterPuzzle>(find.byType(CharacterPuzzle))
            .revealedPieces,
        isEmpty,
      );
      await closePraise(tester);
      expect(saves, 2);
      expect(find.text('1 / 10'), findsOneWidget);
      expect(find.text('다음 문제'), findsOneWidget);
    },
  );
}
