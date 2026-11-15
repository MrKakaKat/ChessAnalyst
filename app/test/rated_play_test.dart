import 'dart:math' as math;

import 'package:chessanalyst/analysis/eval.dart';
import 'package:chessanalyst/engine/rated_play.dart';
import 'package:flutter_test/flutter_test.dart';

Line l(String m, int win) => Line(move: m, eval: Eval(cp: 0, wdl: (win, 1000 - win, 0)), pv: [m]);

void main() {
  test('accuracy of a rating: weak players are less accurate', () {
    expect(accuracyForRating(400), closeTo(55, 0.01));
    expect(accuracyForRating(2700), closeTo(97, 0.01));
    expect(accuracyForRating(1500), lessThan(accuracyForRating(2200)));
  });

  test('the rated engine leaves out moves that drop its accuracy below the rating', () {
    // лучший, неточный, ошибка, зевок (ожидаемый результат в промилле)
    final lines = [l('a', 700), l('b', 660), l('c', 560), l('d', 300)];
    final strong = RatedPlay(2700, random: math.Random(1));
    for (var i = 0; i < 20; i++) {
      final m = strong.choose(lines).move;
      expect(m, isNot('d'));
      expect(m, isNot('c'));
    }
    expect(strong.accuracy, greaterThanOrEqualTo(strong.target - 1.5));
    final weak = RatedPlay(800, random: math.Random(1));
    final played = {for (var i = 0; i < 20; i++) weak.choose(lines).move};
    // слабый движок ошибается, но точность держит у своей
    expect(played.difference({'a'}), isNotEmpty);
    expect(weak.accuracy, closeTo(weak.target, 6));
    // снятый ход забывается
    final n = weak.accuracy;
    weak.undo();
    expect(weak.accuracy, isNot(n));
  });
}
