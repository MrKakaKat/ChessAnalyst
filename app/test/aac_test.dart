import 'dart:io';

import 'package:chessanalyst/analysis/aac.dart';
import 'package:chessanalyst/analysis/game.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AAC: one point per ply, values within -1..1, the winner ahead at the end', () {
    final g = GameData.parse(File('assets/games/kasparov_topalov_1999.json').readAsStringSync());
    final watch = Stopwatch()..start();
    final aac = aacOf(g);
    // ignore: avoid_print
    print('AAC of ${aac.length} plies in ${watch.elapsedMilliseconds} ms; last ${aac.last.value.toStringAsFixed(2)}');
    expect(aac.length, g.plies.length);
    expect(aac.every((p) => p.value >= -1 && p.value <= 1), isTrue);
    // белые выиграли: в конце партии контригра на их стороне
    final tail = aac.sublist(aac.length - 10).map((p) => p.value).reduce((a, b) => a + b) / 10;
    expect(tail, greaterThan(0));
  });
}
