import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peng/character_puzzle.dart';

void main() {
  test('atlas maps all 100 characters, excluding blank cells and margins', () {
    expect(characterRegions.length, 100);
    expect(characterRegions.map((region) => region.name).toSet().length, 100);
    for (final region in characterRegions) {
      final rect = region.sourceRect;
      expect(rect.left, greaterThanOrEqualTo(144));
      expect(rect.right, lessThanOrEqualTo(918));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(1557));
      expect(rect.width, greaterThan(0));
      expect(rect.height, greaterThan(0));
    }
    final last = characterRegions.last;
    expect(last.name, 'LUMI');
    expect(last.sourceRect.bottom, 1557);
    expect(characterRegions.where((region) => region.row == 1).length, 3);
    expect(characterRegions.where((region) => region.row == 12).length, 1);
  });

  testWidgets('puzzle exposes progress without naming hidden characters', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: CharacterPuzzle(
            character: characterRegions.first,
            revealedPieces: const {1, 4, 8},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('캐릭터 퍼즐 3 / 10 조각 공개'), findsOneWidget);
    final opacity = tester.widgetList<Opacity>(find.byType(Opacity)).toList();
    expect(opacity.where((tile) => tile.opacity == 0).length, 3);
    expect(opacity.where((tile) => tile.opacity == 1).length, 7);
    semantics.dispose();
  });
}
