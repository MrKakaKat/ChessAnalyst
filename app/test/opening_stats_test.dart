import 'dart:io';

import 'package:chessanalyst/analysis/game.dart';
import 'package:chessanalyst/analysis/openings.dart';
import 'package:chessanalyst/analysis/settings.dart';
import 'package:chessanalyst/ui/player_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the opening of a game is the family of its deepest book name', () {
    final book = OpeningBook.parse(File('assets/openings_book.json').readAsStringSync());
    final g = GameData.parse(File('assets/games/kasparov_topalov_1999.json').readAsStringSync());
    final a = analyzeGame(g, const Settings(), book: book);
    final family = openingFamily(a);
    expect(family, isNotNull);
    expect(family, isNot(contains(':')));
    final s = OpeningScore()
      ..wins = 2
      ..draws = 1
      ..losses = 1;
    expect(s.games, 4);
    expect(s.score, closeTo(0.625, 1e-9));
  });
}
