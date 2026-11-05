import 'dart:io';

import 'package:chessanalyst/analysis/game.dart';
import 'package:chessanalyst/analysis/metrics.dart';
import 'package:chessanalyst/analysis/settings.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter_test/flutter_test.dart';

GameAnalysis load(String name) =>
    analyzeGame(GameData.parse(File('assets/games/$name.json').readAsStringSync()), const Settings());

void main() {
  test('accuracy is a percentage for both sides', () {
    final s = summarize(load('kasparov_topalov_1999'));
    for (final side in Side.values) {
      expect(s.accuracy[side]!.overall, inInclusiveRange(0, 100));
    }
  });

  test('a deep tactical game is harder than a short one', () {
    final kasparov = summarize(load('kasparov_topalov_1999'));
    final fischer = summarize(load('byrne_fischer_1956'));
    expect(kasparov.difficulty, greaterThan(35));
    expect(fischer.difficulty, greaterThan(35));
    expect(kasparov.parts.length, 5);
  });
}
