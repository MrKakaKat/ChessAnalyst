import 'package:chessanalyst/analysis/classify.dart';
import 'package:chessanalyst/analysis/difficulty.dart';
import 'package:chessanalyst/analysis/eval.dart';
import 'package:chessanalyst/analysis/pos.dart';
import 'package:chessanalyst/analysis/settings.dart';
import 'package:flutter_test/flutter_test.dart';

Line line(String move, {int? cp, int? mate, List<String>? pv}) =>
    Line(move: move, eval: Eval(cp: cp, mate: mate, wdl: (0, 1000, 0)), pv: pv ?? [move]);

const fen0 = '4k3/8/8/8/8/8/8/4K3 w - - 0 1';

void main() {
  test('only move weight grows with its distance', () {
    expect(onlyWeight(1), closeTo(0.15, 1e-9));
    expect(onlyWeight(2), closeTo(0.235, 1e-9));
    expect(onlyWeight(10), closeTo(0.915, 1e-9));
    expect(onlyWeight(20), 1.0);
  });

  test('good moves keep the class; not won — lose at most a pawn', () {
    // выигрыш: держат +3
    expect(goodCount([500, 320, 250]), 2);
    // не выигрыш: потеря больше пешки — уже ошибка
    expect(goodCount([150, 100, 20]), 2);
    expect(goodCount([150, -20, -50]), 1);
    // мат — +8
    expect(goodCount([20000 - 3, 450, 100]), 2);
    expect(narrowness(1, 3), 1);
    expect(narrowness(2, 3), 0.35);
    expect(narrowness(3, 3), 0);
    expect(narrowness(1, 1), 0, reason: 'a forced move is not a choice');
  });

  test('a mate line is one only move at the distance of the mate', () {
    expect(lineDifficulty(fen0, line('a', mate: 1), null, root: true), closeTo(0.15, 1e-9));
    expect(lineDifficulty(fen0, line('a', mate: 10), null, root: true), closeTo(0.915, 1e-9));
    // у того, кого матуют, выбора нет
    expect(lineDifficulty(fen0, line('a', mate: 3), null, root: false), 0);
  });

  test('line difficulty from the narrow places of a side', () {
    final l = line('a', cp: 400, pv: ['a', 'b', 'c', 'd', 'e', 'f', 'g']);
    final nodes = <List<int>?>[
      null,
      [-400, -900, -900], // ответ соперника: единственный
      [400, 380, 350], // свой 2-й ход: путей много
      null,
      [400, 100, 50], // свой 3-й ход: only move
    ];
    expect(lineDifficulty(fen0, l, nodes, root: true), closeTo(onlyWeight(3), 1e-9));
    expect(lineDifficulty(fen0, l, nodes, root: false), 0, reason: 'losing side: nothing to keep');
  });

  test('position difficulty: one good line is hard, several are easy', () {
    final pv = ['a', 'b', 'c', 'd', 'e'];
    final only = [
      line('a', cp: 400, pv: pv),
      line('x', cp: 50),
      line('y', cp: 0),
    ];
    final scan = PlyScan(10, {
      0: [null, null, null, null, [400, 0, -10]],
    });
    final one = rawDifficulty(fen0, only, scan);
    // первый ход — only (0.15), третий свой ход — only (0.32)
    expect(one.mover, closeTo(1 - (1 - 0.15) * (1 - onlyWeight(3)), 1e-9));
    final many = rawDifficulty(fen0, [
      line('a', cp: 400, pv: pv),
      line('x', cp: 390),
      line('y', cp: 380),
      line('z', cp: 370),
    ], scan);
    expect(many.mover, lessThan(one.mover));
  });

  test('percent against the middle standard', () {
    expect(difficultyPercent(0), closeTo(0.075, 1e-9));
    expect(difficultyPercent(0.057), closeTo(0.5, 1e-9));
    expect(difficultyPercent(0, other: true), closeTo(0.2, 1e-9));
    expect(difficultyPercent(1), 1);
    expect(difficultyPercent(0.3), greaterThan(difficultyPercent(0.2)));
  });

  test('practical evaluation: +6 at 80% → +4.2, at 30% → +7.2', () {
    expect(practicalPawns(6, moverPercent: 0.8, otherPercent: 0), closeTo(4.2, 1e-9));
    expect(practicalPawns(6, moverPercent: 0.3, otherPercent: 0), closeTo(7.2, 1e-9));
    // за проигрывающую сторону — по трудности соперника
    expect(practicalPawns(-6, moverPercent: 0, otherPercent: 0.8), closeTo(-4.2, 1e-9));
    // мат — как +8
    expect(practicalPawns(100, moverPercent: 0.5, otherPercent: 0), closeTo(8, 1e-9));
    expect(accuracyWithDifficulty(80, 1), 90);
    expect(accuracyWithDifficulty(80, 0), 70);
  });

  test('scan survives JSON', () {
    final s = PlyScan(10, {
      0: [null, [10, 5, -3]],
      2: [null, null, [20000 - 2, 300]],
    });
    final back = PlyScan.fromJson(s.toJson());
    expect(back.depth, 10);
    expect(back.lines[2]![2], [19998, 300]);
    expect(back.lines[0]![0], isNull);
  });

  test('blue line: its first move is the one good move', () {
    const fen = '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1';
    expect(lineHasOnly(fen, [line('a1a8', mate: 1), line('h2h3', cp: 20)], 0, null), isTrue);
    expect(lineHasOnly(fen, [line('a1a8', mate: 1), line('h2h3', cp: 20)], 1, null), isFalse);
    expect(lineHasOnly(fen, [line('h2h3', cp: 20), line('g2g3', cp: 10)], 0, null), isFalse);
  });

  test('a missed mate in one is a blunder', () {
    const fen = '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1';
    final lines = [line('a1a8', mate: 1), line('a1a7', cp: 600), line('h2h3', cp: 550)];
    final r = classify(Pos.fromFen(fen), lines, lines[1], null, const Settings(), ply: 0);
    expect(r.step, 'blunder');
  });

  test('an obvious only move (recapture, escape) weighs less and is not blue', () {
    // 1.e4 d5 2.exd5 Qxd5: взятие в ответ на d5 — очевидное
    const fen = 'rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2';
    final l = line('e4d5', cp: 0, pv: ['e4d5', 'd8d5', 'b1c3']);
    final nodes = <List<int>?>[null, [0, -200, -300]];
    expect(lineDifficulty(fen, l, nodes, root: false), closeTo(onlyWeight(1) * obviousShare, 1e-9));
    expect(onlyMoves(fen, l, nodes), isEmpty);
  });

  test('Diff grades a move by its own mechanism', () {
    const fen = '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1';
    final lines = [line('a1a8', cp: 400), line('a1a7', cp: 100), line('h2h3', cp: 50)];
    // единственный хороший ход: в трудной позиции — brilliant, иначе only move
    expect(diffStep('best', fen, lines, lines[0], 0.9), 'brilliant');
    expect(diffStep('best', fen, lines, lines[0], 0.3), 'only_move');
    // ход уронил класс (выигрыш → не выигрыш) — зевок
    expect(diffStep('mistake', fen, lines, lines[1], 0.3), 'blunder');
    // промах в той же категории — по трудности позиции
    final calm = [line('a1a8', cp: 150), line('a1a7', cp: 120), line('h2h3', cp: -20)];
    expect(diffStep('mistake', fen, calm, calm[2], 0.3), 'mistake');
    expect(diffStep('mistake', fen, calm, calm[2], 0.6), 'laxity');
    expect(diffStep('mistake', fen, calm, calm[2], 0.9), 'inaccuracy');
    expect(diffStep('good', fen, calm, calm[1], 0.5), 'good');
    expect(diffStep('book', fen, calm, calm[2], 0.5), 'book');
  });
}

