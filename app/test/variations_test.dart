import 'dart:io';

import 'package:chessanalyst/analysis/game.dart';
import 'package:chessanalyst/analysis/pos.dart';
import 'package:chessanalyst/ui/controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final game = GameData.parse(File('assets/games/kasparov_topalov_1999.json').readAsStringSync());

  test('game opens at the start; the game move on the board follows the game', () {
    final c = AnalysisController(game);
    expect(c.atStart, isTrue);
    expect(c.lastMove, isNull);
    c.playMove(c.moves[0]);
    expect(c.inVariation, isFalse);
    expect(c.ply, 0);
  });

  test('resignation is the last pseudo-move, graded by the position', () {
    final c = AnalysisController(game);
    expect(c.end, isNotNull); // Kasparov - Topalov: 1-0, Black resigned
    expect(c.end!.kind, 'resign');
    c.last();
    expect(c.atEnd, isTrue);
    expect(c.end!.step, 'neutral'); // позиция чёрных проиграна
  });

  test('own move outside the lines has no verdict; a best move gets one', () {
    final c = AnalysisController(game);
    c.select(20);
    final lines = c.game.plies[21].lines.map((l) => l.move).toSet();
    final own = c.position.legalMoves.firstWhere((m) => !lines.contains(m.uci) && m != c.moves[21]);
    c.playMove(own);
    expect(c.varMove!.kind, isNull);
    c.exitVariation();
    final best = c.analysis.records[21].bestMoves.first.uci;
    if (best != c.moves[21].uci) {
      c.playAlternative(21, best);
      expect(c.varMove!.record, isNotNull);
    }
  });

  test('another move starts a branch, the next one extends it', () {
    final c = AnalysisController(game);
    c.select(5);
    final alt = c.position.legalMoves.firstWhere((m) => m != c.moves[6]);
    c.playMove(alt);
    expect(c.inVariation, isTrue);
    expect(c.variation!.anchor, 5);
    expect(c.ply, 6); // панели — на заменённом ходе партии
    final reply = c.position.legalMoves.first;
    c.playMove(reply);
    expect(c.variations.length, 1);
    expect(c.variation!.moves.length, 2);
    c.prev();
    c.prev();
    expect(c.inVariation, isFalse);
    expect(c.ply, 5);
  });

  test('best move alternative gets the engine evaluation', () {
    final c = AnalysisController(game);
    final ply = c.analysis.records.indexWhere((r) => r.bestMoves.isNotEmpty && r.bestMoves.first.uci != r.uci);
    final best = c.analysis.records[ply].bestMoves.first;
    c.select(ply);
    c.playAlternative(ply, best.uci);
    expect(c.varMove!.san, best.san);
    expect(c.varMove!.eval, isNotNull);
    expect(c.position.fen, Pos.fromFen(game.plies[ply].fenBefore).push(Pos.move(best.uci)).fen);
  });

  test('next keeps playing the chosen engine line to its end', () {
    final c = AnalysisController(game);
    final ply = c.analysis.records.indexWhere((r) => r.bestMoves.isNotEmpty && r.bestMoves.first.uci != r.uci);
    final line = c.game.plies[ply].lines.first;
    c.select(ply);
    c.playAlternative(ply, line.move);
    for (var i = 1; i < line.pv.length; i++) {
      expect(c.canNext, isTrue);
      c.next();
    }
    expect(c.variation!.moves.length, line.pv.length);
    // ходы линии анализа — синие, без пересчёта
    expect(c.variation!.moves.every((m) => m.inLines && !m.live), isTrue);
    // дальше — продолжение движком на устройстве
    expect(c.canNext, isTrue);
  });

  test('a hand move inside an analysed line forks a new branch; back returns to the old one', () {
    final c = AnalysisController(game);
    final ply = c.analysis.records.indexWhere((r) => r.bestMoves.isNotEmpty && r.bestMoves.first.uci != r.uci);
    final line = c.game.plies[ply].lines.first;
    c.select(ply);
    c.playAlternative(ply, line.move);
    c.next();
    c.next();
    final parent = c.variation!;
    expect(parent.moves.length, 3);
    // назад на первый ход и свой ход, не совпадающий с линией
    c.prev();
    c.prev();
    final pos = c.position;
    final other = pos.legalMoves.firstWhere((m) => m.uci != parent.moves[1].move.uci);
    c.playMove(other);
    final fork = c.variation!;
    expect(identical(fork, parent), isFalse);
    expect(fork.parent, same(parent));
    expect(fork.moves[1].manual, isTrue);
    // старая ветка цела
    expect(parent.moves.length, 3);
    // назад со своего хода — в старую ветку, «далее» идёт по ней
    c.prev();
    expect(c.variation, same(parent));
    c.next();
    expect(c.varMove!.move, parent.moves[1].move);
  });

  test('deleting a branch move removes it, the moves after it and the forks through them', () {
    final c = AnalysisController(game);
    final ply = c.analysis.records.indexWhere((r) => r.bestMoves.isNotEmpty && r.bestMoves.first.uci != r.uci);
    final line = c.game.plies[ply].lines.first;
    c.select(ply);
    c.playAlternative(ply, line.move);
    c.next();
    c.next();
    c.next();
    final v = c.variation!;
    expect(v.moves.length, 4);
    // ответвление с третьего хода
    c.prev();
    final other = c.position.legalMoves.firstWhere((m) => m.uci != v.moves[3].move.uci);
    c.playMove(other);
    final fork = c.variation!;
    expect(fork.parent, same(v));
    c.removeFrom(v, 2);
    expect(v.moves.length, 2);
    expect(c.variations.contains(fork), isFalse);
    // первый ход — вся ветка
    c.removeFrom(v, 0);
    expect(c.variations.contains(v), isFalse);
  });
}
