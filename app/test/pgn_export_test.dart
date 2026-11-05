import 'dart:io';

import 'package:chessanalyst/analysis/game.dart';
import 'package:chessanalyst/analysis/pgn_import.dart';
import 'package:chessanalyst/ui/controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('copied PGN reads back as the same game', () {
    final g = GameData.parse(File('assets/games/kasparov_topalov_1999.json').readAsStringSync());
    final back = importPgn(g.pgn);
    expect(back.ucis, [for (final p in g.plies) p.uci]);
    expect(back.headers['white'] ?? back.headers['White'], g.white);
  });

  test('a range of moves is copied with move numbers', () {
    final g = GameData.parse(File('test/games/mrkakakat_2026_11_04.json').readAsStringSync());
    final c = AnalysisController(g);
    expect(c.movesText(6, 10), '4. Bb5 a6 5. Bxc6+ bxc6 6. O-O');
    expect(c.movesText(7, 7), '4... a6');
  });
}
