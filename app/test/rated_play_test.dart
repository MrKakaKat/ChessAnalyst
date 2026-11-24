import 'dart:math' as math;

import 'package:chessanalyst/analysis/eval.dart';
import 'package:chessanalyst/analysis/pos.dart';
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

  test('a strong rated engine makes no obvious blunder, a weak one may', () {
    // 1.e4 e5 2.Nf3 Nc6: 3.Bb5, 3.Bc4, 3.d4 — и зевок 3.Ba6?? (слон под пешку b7)
    final pos = Pos.fromFen('r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3');
    Line w(String m, int win, List<String> pv) => Line(move: m, eval: Eval(cp: 0, wdl: (win, 1000 - win, 0)), pv: pv);
    final lines = [
      w('f1b5', 560, ['f1b5']),
      w('f1c4', 550, ['f1c4']),
      w('d2d4', 545, ['d2d4']),
      w('f1a6', 200, ['f1a6', 'b7a6']),
    ];
    final strong = RatedPlay(2000, random: math.Random(3));
    // точность сильно выше цели — движку «нужна» ошибка, но зевок очевиден
    for (var i = 0; i < 30; i++) {
      expect(strong.choose(lines, pos: pos).move, isNot('f1a6'));
    }
    final weak = RatedPlay(600, random: math.Random(3));
    final played = {for (var i = 0; i < 40; i++) weak.choose(lines, pos: pos).move};
    expect(played, contains('f1a6'));
  });

  test('a strong rated engine takes an obvious advantage', () {
    // чёрный конь без защиты на d4: Nxd4 — даровое взятие
    final pos = Pos.fromFen('r1bqkbnr/pppp1ppp/8/8/3nP3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 0 4');
    Line w(String m, int win, int cp) => Line(move: m, eval: Eval(cp: cp, wdl: (win, 1000 - win, 0)), pv: [m]);
    final lines = [w('f3d4', 850, 300), w('b1c3', 600, 20), w('d2d3', 590, 10), w('h2h3', 560, 0)];
    // в узком месте (один хороший ход) упустить можно, но не даровое взятие
    final strong = RatedPlay(2000, random: math.Random(5));
    for (var i = 0; i < 30; i++) {
      expect(strong.choose(lines, pos: pos).move, 'f3d4');
    }
    final weak = RatedPlay(600, random: math.Random(5));
    final played = {for (var i = 0; i < 40; i++) weak.choose(lines, pos: pos).move};
    expect(played.difference({'f3d4'}), isNotEmpty);
  });
}
