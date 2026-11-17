// Calibration of our engine rating against the Lichess puzzle ratings (from
// thousands of solvers). Runs only when a sample is there:
//   LICHESS_SAMPLE=<sample.csv> LICHESS_OUT=<result.csv> STOCKFISH=<path> flutter test test/lichess_calibration_test.dart
// The sample comes from tools/lichess_sample.py (the GitHub workflow
// "Lichess calibration" makes it and runs this).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:chessanalyst/analysis/pos.dart';
import 'package:chessanalyst/analysis/settings.dart';
import 'package:chessanalyst/engine/bot.dart';
import 'package:chessanalyst/engine/engine.dart';
import 'package:chessanalyst/engine/puzzle_rater.dart';
import 'package:chessanalyst/ui/lichess_puzzles.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stockfish as a process, for the engine bot.
class ProcessEngine implements UciEngine {
  ProcessEngine(this._p) {
    _lines = _p.stdout.transform(utf8.decoder).transform(const LineSplitter()).asBroadcastStream();
  }

  final Process _p;
  late final Stream<String> _lines;

  @override
  Stream<String> get lines => _lines;

  @override
  void send(String command) => _p.stdin.writeln(command);

  @override
  int get cores => 1;

  @override
  bool get alive => true;

  @override
  Future<void> dispose() async => _p.kill();
}

List<String> _csvRow(String line) {
  final out = <String>[];
  final cur = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      quoted = !quoted;
    } else if (ch == ',' && !quoted) {
      out.add(cur.toString());
      cur.clear();
    } else {
      cur.write(ch);
    }
  }
  out.add(cur.toString());
  return out;
}

void main() {
  final sample = Platform.environment['LICHESS_SAMPLE'];
  test('our rating against Lichess', () async {
    final stockfish = Platform.environment['STOCKFISH'] ?? 'stockfish';
    EngineBot.engineFactory = () async => ProcessEngine(await Process.start(stockfish, []));
    final rows = File(sample!).readAsLinesSync();
    final head = _csvRow(rows.first);
    int col(String n) => head.indexOf(n);
    final out = File(Platform.environment['LICHESS_OUT'] ?? 'lichess_result.csv')
      ..writeAsStringSync('id,lichess,ours,moves,themes\n');
    final bot = await EngineBot.shared();
    const s = Settings();
    final pairs = <(int, int, Set<String>)>[];
    final watch = Stopwatch()..start();
    for (final line in rows.skip(1)) {
      if (line.trim().isEmpty) continue;
      final r = _csvRow(line);
      final moves = r[col('Moves')].split(' ');
      final themes = r[col('Themes')].split(' ').toSet();
      final start = Pos.fromFen(r[col('FEN')]).push(Pos.move(moves.first));
      final lines = await bot.analyse(start.fen, depth: 12, multipv: 1);
      final value = lines.isEmpty ? 0.0 : lines.first.eval.pawns(s);
      final p = fromLichess(r[col('PuzzleId')], r[col('FEN')], moves, themes, value);
      final ours = await estimateRating(p);
      final lichess = int.parse(r[col('Rating')]);
      pairs.add((lichess, ours, themes));
      out.writeAsStringSync('${r[col('PuzzleId')]},$lichess,$ours,${(moves.length) ~/ 2},${themes.join(' ')}\n',
          mode: FileMode.append);
      if (pairs.length % 50 == 0) {
        // ignore: avoid_print
        print('${pairs.length} puzzles, ${(watch.elapsedMilliseconds / pairs.length).round()} ms each');
      }
    }
    // сводка: связь, сдвиг, прямая lichess ≈ a·ours + b, остатки по темам
    final n = pairs.length;
    final mx = pairs.map((e) => e.$2).reduce((a, b) => a + b) / n;
    final my = pairs.map((e) => e.$1).reduce((a, b) => a + b) / n;
    var sxy = 0.0, sxx = 0.0, syy = 0.0;
    for (final (y, x, _) in pairs) {
      sxy += (x - mx) * (y - my);
      sxx += (x - mx) * (x - mx);
      syy += (y - my) * (y - my);
    }
    final a = sxy / sxx, b = my - a * mx, r = sxy / math.sqrt(sxx * syy);
    final byTheme = <String, List<double>>{};
    for (final (y, x, th) in pairs) {
      for (final t in th) {
        byTheme.putIfAbsent(t, () => []).add(y - (a * x + b));
      }
    }
    final themes = byTheme.entries.where((e) => e.value.length >= 25).toList()
      ..sort((p, q) => (q.value.reduce((a, b) => a + b) / q.value.length)
          .compareTo(p.value.reduce((a, b) => a + b) / p.value.length));
    final shift = my - mx;
    final mae = pairs.map((e) => (e.$1 - e.$2 - shift).abs()).reduce((a, b) => a + b) / n;
    // ignore: avoid_print
    print('SUMMARY n=$n mean lichess ${my.round()} ours ${mx.round()} r=${r.toStringAsFixed(3)} '
        'fit lichess = ${a.toStringAsFixed(3)}·ours + ${b.round()} '
        'MAE after the mean shift ${mae.round()}');
    for (final e in themes) {
      // ignore: avoid_print
      print('THEME ${e.key} n=${e.value.length} residual ${(e.value.reduce((a, b) => a + b) / e.value.length).round()}');
    }
    await EngineBot.reset();
  }, timeout: const Timeout(Duration(hours: 2)), skip: sample == null ? 'no Lichess sample' : false);
}
