import 'dart:convert';
import 'dart:io';

import 'package:chessanalyst/analysis/game.dart';
import 'package:chessanalyst/analysis/pgn_import.dart';
import 'package:chessanalyst/engine/game_job.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a job with engine data survives the history store round trip and snapshots a game', () {
    final opera = GameData.parse(File('assets/games/morphy_opera_1858.json').readAsStringSync());
    final src = importPgn(File('../examples/opera_game.pgn').readAsStringSync());
    final job = AnalysisJob(id: 'x', source: src, targetDepth: 14);
    expect(job.ready, isFalse);
    // данные движка встроенной партии вместо расчёта
    for (var i = 0; i < job.length; i++) {
      job.plies[i] = opera.plies[i];
      job.depthAt[i] = 14;
    }
    expect(job.ready, isTrue);
    expect(job.done, isTrue);
    final back = AnalysisJob.fromJson(jsonDecode(jsonEncode(job.toJson())) as Map<String, dynamic>);
    final g = back.snapshot();
    expect(g.plies.length, 33);
    expect(g.plies[5].lines.first.eval.cp, opera.plies[5].lines.first.eval.cp);
    expect(back.depth, 14);
    back.targetDepth = 14;
    expect(back.progress, 1);
  });
}
