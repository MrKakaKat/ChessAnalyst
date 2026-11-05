import 'dart:io';

import 'package:chessanalyst/analysis/game.dart';
import 'package:chessanalyst/analysis/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('steps in percent change the grades of a game', () {
    final g = GameData.parse(File('assets/games/kasparov_topalov_1999.json').readAsStringSync());
    final fixed = analyzeGame(g, const Settings(unit: Unit.pawns));
    final percent = analyzeGame(g, const Settings(unit: Unit.pawns, percentSteps: true));
    var changed = 0;
    for (var i = 0; i < fixed.records.length; i++) {
      if (fixed.records[i].step != percent.records[i].step) changed++;
    }
    // ignore: avoid_print
    print('changed $changed of ${fixed.records.length}');
    expect(changed, greaterThan(0));
  });
}
