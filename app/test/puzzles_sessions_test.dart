import 'dart:convert';
import 'dart:io';

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
  });
}
