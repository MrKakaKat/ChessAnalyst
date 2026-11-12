import 'dart:convert';
import 'dart:io';

import 'package:chessanalyst/analysis/eval.dart';
import 'package:chessanalyst/analysis/game.dart';
import 'package:chessanalyst/analysis/pos.dart';
import 'package:chessanalyst/analysis/settings.dart';
import 'package:chessanalyst/ui/board_session.dart';
import 'package:chessanalyst/ui/puzzles.dart';
import 'package:dartchess/dartchess.dart' show Chess, NormalMove;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('analysed games give puzzles with legal solutions of odd length', () {
    var total = 0;
    for (final f in Directory('assets/games').listSync()) {
      final g = GameData.parse(File(f.path).readAsStringSync());
      final ps = puzzlesFrom(analyzeGame(g, const Settings(unit: Unit.pawns)));
      total += ps.length;
      for (final p in ps) {
        expect(p.solution.length.isOdd, isTrue);
        var pos = Pos.fromFen(p.fen);
        for (final uci in p.solution) {
          final m = NormalMove.fromUci(uci);
          expect(pos.isLegal(m), isTrue, reason: '${p.id} $uci');
          pos = pos.push(m);
        }
      }
    }
    expect(total, greaterThan(5));
  });

  test('a tactic line goes on while the moves are forcing', () {
    // Scholar's mate set-up: Qxf7# ends it; a quiet follow-up is cut off
    final start = Pos.fromFen('r1bqkbnr/pppp1ppp/2n5/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 2 3');
    expect(tacticLine(start, ['h5f7']), ['h5f7']);
    final open = Pos(Chess.initial);
    // first move always counts, the quiet second one does not
    expect(tacticLine(open, ['e2e4', 'e7e5', 'g1f3', 'b8c6']), ['e2e4']);
    // a capture after the reply continues the line
    final trade = Pos.fromFen('rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2');
    expect(tacticLine(trade, ['e4d5', 'd8d5', 'b1c3', 'd5a5']), ['e4d5', 'd8d5', 'b1c3']);
  });

  test('a board session with branches survives saving', () {
    final s = BoardSession(id: 's', name: 'Test', startFen: Chess.initial.fen);
    MoveNode add(MoveNode at, String uci) {
      final m = NormalMove.fromUci(uci);
      final n = MoveNode(move: m, san: at.pos.san(m), pos: at.pos.push(m), parent: at);
      at.children.add(n);
      return n;
    }

    final e4 = add(s.root, 'e2e4');
    add(e4, 'e7e5');
    add(e4, 'c7c5'); // ветка
    add(s.root, 'd2d4');
    final back = BoardSession.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
    expect(back.moveCount, 4);
    expect(back.root.children.first.children.map((n) => n.san), ['e5', 'c5']);
    expect(back.isOpening, isTrue);
  });

  test('a board session keeps its place and colour, and copies PGN with all branches', () {
    final s = BoardSession(id: 's', name: 'Test', startFen: Chess.initial.fen);
    MoveNode add(MoveNode at, String uci) {
      final m = NormalMove.fromUci(uci);
      final n = MoveNode(move: m, san: at.pos.san(m), pos: at.pos.push(m), parent: at);
      at.children.add(n);
      return n;
    }

    final e4 = add(s.root, 'e2e4');
    final e5 = add(e4, 'e7e5');
    final c5 = add(e4, 'c7c5');
    add(e5, 'g1f3');
    add(c5, 'g1f3');
    add(s.root, 'd2d4');
    expect(s.pgn(), '1. e4 (1. d4) 1... e5 (1... c5 2. Nf3) 2. Nf3 *');
    s
      ..lastPath = BoardSession.pathOf(c5)
      ..flipped = true
      ..pinned = true;
    final back = BoardSession.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
    expect(back.lastNode.san, 'c5');
    expect(back.flipped, isTrue);
    expect(back.pinned, isTrue);
    // позиция из задачи — позиционная сессия
    expect(BoardSession(id: 'p', name: 'P', startFen: e4.pos.fen).isOpening, isFalse);
  });

  test('an attack that leads straight into a needed defence becomes one combined puzzle', () {
    final g = GameData.parse(File('assets/games/kasparov_topalov_1999.json').readAsStringSync());
    Puzzle at(int ply, int len, PuzzleGoal goal) => Puzzle(
        id: '${g.id}:$ply',
        fen: g.plies[ply].fenBefore,
        solution: [for (var i = 0; i < len; i++) g.plies[ply + i].uci],
        source: '',
        gap: 2,
        goal: goal,
        value: goal == PuzzleGoal.defend ? -0.3 : 4.5);
    final list = combine([at(20, 3, PuzzleGoal.win), at(24, 1, PuzzleGoal.defend), at(40, 1, PuzzleGoal.win)], g);
    expect(list.length, 2);
    final c = list.first;
    expect(c.combined, isTrue);
    expect(c.solution.length, 5);
    expect(c.switchAt, 4);
    expect(c.goalAt(0), PuzzleGoal.win);
    expect(c.goalAt(4), PuzzleGoal.defend);
    // в защитной части годится только ход, что держит
    expect(c.keepsGoal(Eval(cp: 25, wdl: (100, 800, 100)), step: 4), isTrue);
    expect(c.keepsGoal(Eval(cp: 300, wdl: (700, 280, 20)), step: 4), isFalse);
    final back = Puzzle.fromJson(jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>);
    expect(back.goal2, PuzzleGoal.defend);
    expect(back.switchAt, 4);
  });

  test('a puzzle does not stop where the next one starts: same goals in a row are one puzzle', () {
    final g = GameData.parse(File('assets/games/kasparov_topalov_1999.json').readAsStringSync());
    Puzzle at(int ply, int len, PuzzleGoal goal) => Puzzle(
        id: '${g.id}:$ply',
        fen: g.plies[ply].fenBefore,
        solution: [for (var i = 0; i < len; i++) g.plies[ply + i].uci],
        source: '',
        gap: 2,
        goal: goal,
        value: 4.5);
    // 20–22, ответ 23, 24, ответ 25, 26 — три атаки подряд
    final list = combine([at(20, 3, PuzzleGoal.win), at(24, 1, PuzzleGoal.win), at(26, 1, PuzzleGoal.advantage)], g);
    expect(list.length, 1);
    final p = list.single;
    expect(p.combined, isFalse);
    expect(p.solution, [for (var i = 20; i <= 26; i++) g.plies[i].uci]);
    expect(p.goal, PuzzleGoal.win);
  });
}
