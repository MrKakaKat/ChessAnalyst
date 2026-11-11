// Measures the raw difficulty of every position of reference games with the
// same pass as the app, and prints its quantiles (0%, 5%, … 100%) for
// difficulty.dart (_reference).
//
// dart run tool/calibrate_difficulty.dart <stockfish> <game.json>...
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chessanalyst/analysis/difficulty.dart';
import 'package:chessanalyst/analysis/difficulty_scan.dart';
import 'package:chessanalyst/analysis/eval.dart';
import 'package:chessanalyst/analysis/game.dart';

class Uci {
  Uci(this.p) {
    p.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((l) {
      if (l.startsWith('info ') && l.contains(' pv ')) _info.add(l);
      if (_wait != null && l.startsWith(_waitFor!)) {
        final c = _wait!;
        _wait = null;
        c.complete(l);
      }
    });
  }
  final Process p;
  final _info = <String>[];
  Completer<String>? _wait;
  String? _waitFor;

  Future<String> ask(String cmd, String reply) {
    _waitFor = reply;
    final c = _wait = Completer<String>();
    p.stdin.writeln(cmd);
    return c.future;
  }

  Future<List<Line>> analyse(String fen, int multipv, int depth) async {
    p.stdin.writeln('setoption name MultiPV value $multipv');
    p.stdin.writeln('position fen $fen');
    _info.clear();
    await ask('go depth $depth', 'bestmove');
    final by = <int, Line>{};
    for (final i in _info) {
      final t = i.split(' ');
      final s = t.indexOf('score'), pv = t.indexOf('pv'), mp = t.indexOf('multipv');
      if (s < 0 || pv < 0) continue;
      final v = int.parse(t[s + 2]);
      final cp = t[s + 1] == 'cp' ? v : null;
      final mate = t[s + 1] == 'mate' && v != 0 ? v : null;
      if (cp == null && mate == null) continue;
      final moves = t.sublist(pv + 1).where((x) => x.isNotEmpty).toList();
      by[mp < 0 ? 1 : int.parse(t[mp + 1])] =
          Line(move: moves.first, eval: Eval(cp: cp, mate: mate, wdl: (0, 1000, 0)), pv: moves);
    }
    return [for (final k in by.keys.toList()..sort()) by[k]!];
  }
}

Future<void> main(List<String> args) async {
  final raws = <double>[], others = <double>[];
  await Future.wait([
    for (final path in args.skip(1))
      () async {
        final g = GameData.parse(File(path).readAsStringSync());
        final uci = Uci(await Process.start(args.first, []));
        await uci.ask('uci', 'uciok');
        uci.p.stdin.writeln('setoption name Threads value 1');
        final cache = <String, List<int>>{};
        final depth = (g.engine['depth'] as num).toInt();
        for (final p in g.plies) {
          final scan = await scanPosition(p.fenBefore, p.lines, (f, n) => uci.analyse(f, n, nodeDepth(depth)),
              depth: depth, cache: cache);
          final d = rawDifficulty(p.fenBefore, p.lines, scan);
          raws.add(d.mover);
          others.add(d.other);
        }
        uci.p.stdin.writeln('quit');
        stderr.writeln('$path: ${g.plies.length} plies');
      }(),
  ]);
  stdout.writeln('positions: ${raws.length}');
  for (final (name, xs) in [('mover', raws), ('other', others)]) {
    xs.sort();
    final q = [for (var i = 0; i <= 20; i++) xs[((xs.length - 1) * i / 20).round()]];
    stdout.writeln('$name quantiles: ${q.map((x) => x.toStringAsFixed(3)).join(', ')}');
    stdout.writeln('$name zero share: ${(xs.where((x) => x == 0).length / xs.length).toStringAsFixed(3)}');
  }
}
