/// Computer estimate of a puzzle's rating.
///
/// [авторское] A rating system like Bayeselo needs many solvers' results; at
/// the start there are none, so the engine's effort stands in for them:
/// - the depth from which the engine keeps choosing a solution move (one of
///   the accepted first moves) at every deeper search up to 12 — a move seen
///   at once is easy, one that needs a deep search is hard;
/// - traps: other moves that look as good at a shallow depth (2), up to 3;
/// - a quiet key move (no capture or check) is harder to see;
/// - the length of the solution and a defensive goal add difficulty.
/// rating = 700 + 75·(depth − 1) + 80·traps + 120 (quiet) + 90·(moves − 1)
/// + 100 (defence), within 400…3000.
/// The game analysis rates its puzzles when it ends (and again when it is
/// sent deeper); the puzzle screen rates any that are still unrated.
library;

import 'dart:math' as math;

import 'package:dartchess/dartchess.dart' show NormalMove;

import '../analysis/pos.dart';
import '../analysis/settings.dart';
import '../ui/puzzles.dart';
import 'bot.dart';

const _maxDepth = 12;

Future<int> estimateRating(Puzzle p, {bool Function()? cancelled}) async {
  final bot = await EngineBot.shared();
  final keys = {for (final s in p.solutions) if (s.isNotEmpty) s.first};
  // глубина, начиная с которой движок держится за решение
  int? since;
  for (var d = 1; d <= _maxDepth; d++) {
    if (cancelled?.call() ?? false) throw StateError('cancelled');
    final lines = await bot.analyse(p.fen, depth: d, multipv: 1);
    final hit = lines.isNotEmpty && keys.contains(lines.first.move);
    if (hit) {
      since ??= d;
    } else {
      since = null;
    }
  }
  final found = since ?? _maxDepth + 1;
  if (cancelled?.call() ?? false) throw StateError('cancelled');
  const s = Settings();
  final shallow = await bot.analyse(p.fen, depth: 2, multipv: 5);
  final key = shallow.where((l) => keys.contains(l.move)).firstOrNull;
  final keyValue = key?.eval.pawns(s) ?? (shallow.isEmpty ? 0.0 : shallow.first.eval.pawns(s));
  final traps = math.min(3, shallow.where((l) => !keys.contains(l.move) && l.eval.pawns(s) >= keyValue - 0.3).length);
  final pos = Pos.fromFen(p.fen);
  final m = NormalMove.fromUci(p.solution.first);
  final quiet = !pos.isCapture(m) && !pos.givesCheck(m) && m.promotion == null;
  final rating = 700 +
      75 * (found - 1) +
      80 * traps +
      (quiet ? 120 : 0) +
      90 * (p.solverMoves - 1) +
      (p.goal == PuzzleGoal.defend ? 100 : 0);
  return rating.clamp(400, 3000);
}

/// Rates [puzzles] one by one ([again]: also the rated ones, after a deeper
/// analysis), saving each rating and updating the recorded attempts. Stops
/// when [cancelled] says so.
Future<void> ratePuzzles(List<Puzzle> puzzles, {bool again = false, bool Function()? cancelled}) async {
  final known = await PuzzleRatings.load();
  for (final p in puzzles) {
    if (cancelled?.call() ?? false) return;
    if (!again && known.containsKey(p.id)) continue;
    try {
      final r = await estimateRating(p, cancelled: cancelled);
      await PuzzleRatings.save(p.id, r);
      await PuzzleHistory.updateRating(p.id, r);
    } catch (_) {
      return;
    }
  }
}
