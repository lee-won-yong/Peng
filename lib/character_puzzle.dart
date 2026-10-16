import 'dart:math';

import 'package:flutter/material.dart';

/// Character cells in character.png, measured in the original 1010×1557 image.
/// The sheet has eight columns and incomplete rows; white margins are excluded.
class CharacterRegion {
  const CharacterRegion(this.row, this.column, this.name);

  final int row;
  final int column;
  final String name;

  Rect get sourceRect => Rect.fromLTWH(
    144 + column * 96.75,
    row == 15 ? 1464 : row * 98,
    96.75,
    row == 15 ? 93 : min(98, 1557 - row * 98).toDouble(),
  );
}

const _characterRows = [
  ['SIRIUS', 'BO', 'PIERCE', 'RICO', 'EMZ', 'BIBI', 'COLONEL RUFFS', 'OTIS'],
  ['SPIKE', 'AMBER', 'FRANK'],
  ['CROW', 'CHESTER', 'CARL', 'POCO', 'SHELLY', 'LEON', 'R-T', 'FINX'],
  ['BYRON', 'GLOWBERT', 'GUS', 'MEEPLE', 'LILY', 'PEARL', 'BROCK', 'CORDELIUS'],
  ['KIT', 'BULL'],
  ['NITA', 'GRAY', 'NANI', 'BELLE', 'TARA', 'SQUEAK', 'MINA', 'JANET'],
  ['MOE', 'JAE-YONG', 'ANGELO', 'TRUNK', 'GENE', 'WILLOW', 'BUSTER', 'BARLEY'],
  ['PAM', 'SANDY', 'CHARLIE', 'PENNY', 'KENJI'],
  ['COLT', 'TWINS', 'JUJU', 'GALE', 'GRIFF', 'MAX', 'DARRYL', 'LOU'],
  ['BEA', 'MORTIS', 'MEG', 'HANK', 'DRACO', 'ASH', 'MICO', 'OLLIE'],
  ['LOLA', '8-BIT', 'SPROUT', 'EVE', 'JACKY', 'BERRY', 'BUZZ', 'EL PRIMO'],
  ['COLETTE', 'ROSA', 'STU', 'PIPER', 'MANDY', 'DYNAMIKE', 'CHUCK', 'DOUG'],
  ['BONNIE'],
  ['MAISIE', 'JESSIE', 'GROM', 'FANG', 'EDGAR', 'MISTER P', 'CLANCY', 'SURGE'],
  ['TICK', 'SAM', 'SHADE', 'KAZE', 'ALLI', 'GIGI', 'ZIGGY', 'MELODIE'],
  ['LUMI'],
];

final characterRegions = List<CharacterRegion>.unmodifiable([
  for (var row = 0; row < _characterRows.length; row++)
    for (var column = 0; column < _characterRows[row].length; column++)
      CharacterRegion(row, column, _characterRows[row][column]),
]);

/// One cropped character, covered by ten independently revealed tiles.
class CharacterPuzzle extends StatelessWidget {
  const CharacterPuzzle({
    required this.character,
    required this.revealedPieces,
    this.newlyRevealedPiece,
    this.size = 200,
    super.key,
  });

  static const pieceCount = 10;
  final CharacterRegion character;
  final Set<int> revealedPieces;
  final int? newlyRevealedPiece;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final source = character.sourceRect;
    return Semantics(
      label: revealedPieces.length == pieceCount
          ? '${character.name} 캐릭터 완성'
          : '캐릭터 퍼즐 ${revealedPieces.length} / $pieceCount 조각 공개',
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox.square(
            dimension: size,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Color(0xff11120e)),
                // Scale the selected source cell, never the full character sheet.
                FittedBox(
                  fit: BoxFit.fill,
                  child: SizedBox(
                    width: source.width,
                    height: source.height,
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        minWidth: 1010,
                        maxWidth: 1010,
                        minHeight: 1557,
                        maxHeight: 1557,
                        child: Transform.translate(
                          offset: Offset(-source.left, -source.top),
                          child: Image.asset(
                            'assets/characters/character.png',
                            width: 1010,
                            height: 1557,
                            fit: BoxFit.fill,
                            excludeFromSemantics: true,
                            errorBuilder: (_, _, _) => const Center(
                              child: Icon(Icons.star, color: Colors.amber),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                for (var piece = 0; piece < pieceCount; piece++)
                  Positioned(
                    left: (piece % 2) * size / 2,
                    top: (piece ~/ 2) * size / 5,
                    width: size / 2,
                    height: size / 5,
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey('${character.name}-piece-$piece'),
                      duration: reducedMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 650),
                      curve: Curves.easeOutCubic,
                      tween: Tween(
                        begin: piece == newlyRevealedPiece
                            ? 1
                            : (revealedPieces.contains(piece) ? 0 : 1),
                        end: revealedPieces.contains(piece) ? 0 : 1,
                      ),
                      builder: (context, opacity, child) =>
                          Opacity(opacity: opacity, child: child),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          border: Border.all(color: colors.surface, width: 1),
                        ),
                        child: Center(
                          child: Text(
                            '?',
                            style: TextStyle(
                              color: colors.onPrimaryContainer.withValues(
                                alpha: 0.5,
                              ),
                              fontWeight: FontWeight.w800,
                              fontSize: size / 10,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
