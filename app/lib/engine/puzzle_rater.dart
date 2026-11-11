/// Computer estimate of a puzzle's rating.
///
/// [авторское] A rating system like Bayeselo needs many solvers' results; at
/// the start there are none, so the engine's effort stands in for them:
/// Every solver move of the solution is rated as a step (up to three):
/// - the depth from which the engine keeps choosing the step's move (or an
///   accepted alternative) at every deeper search up to 12 — a move seen at
///   once is easy, one that needs a deep search is hard;
/// - traps: other moves that look as good at a shallow depth (2), up to 3;
/// - a quiet move (no capture or check) is harder to see;
/// - the opponent's counter-resources after the move: replies that check or
///   capture and keep the opponent within a pawn of their best — each has
///   to be calculated through (a discovered check, a counter-sacrifice…);
/// - the length of the forcing line after the move, beyond two plies.
/// step = 75·(depth − 1) + 80·traps + 120 (quiet) + 70·resources (up to 3)
/// + 25·forcing plies beyond 2 (up to 8), then two discounts:
/// - a check that leaves the opponent one or two replies: the depth and the
///   forcing length count 40% — a long mate by checks alone is found by
///   just giving checks (a queen mating a bare king in ten moves is not
///   hard either);
/// - in an attack, several moves reach the goal at this step (a second or third line of
///   a depth-12 search keeps it): ×0.6 with two, ×0.45 with three — the
///   step is not a single narrow path.
/// rating = 700 + the hardest step + 0.35·(the other steps) + 90·(moves − 1)
/// + 100 (a defence or a defensive part) + 150 (a combined puzzle: the goal
/// changes on the way), within 400…3000.
/// The first version looked only at the main line and rated a four-move
/// tactic with a discovered check in the defence at about 1200; the second
/// rated only the first move, so a defence that starts with a plain
/// recapture and needs a deep quiet move after it came out at about 1000.
/// The game analysis rates its puzzles when it ends (and again when it is
/// sent deeper); the puzzle screen rates any that are still unrated.
library;

import 'dart:math' as math;

import 'package:dartchess/dartchess.dart' show NormalMove;

import '../analysis/eval.dart' show Line;
import '../analysis/features.dart' as features;
import '../analysis/pos.dart';
import '../analysis/settings.dart';
import '../ui/puzzles.dart';
import 'bot.dart';

const _maxDepth = 12;

Future<int> estimateRating(Puzzle p, {bool Function()? cancelled}) async {
  final bot = await EngineBot.shared();
  void check() {
    if (cancelled?.call() ?? false) throw StateError('cancelled');
  }

  /// The difficulty of the solver move at [step] of the solution.
  Future<int> stepScore(Pos pos, int step) async {
    final prefix = p.solution.take(step).toList();
    final keys = <String>{
      for (final sol in p.solutions)
        if (sol.length > step && _startsWith(sol, prefix)) sol[step]
    };
    // глубина, начиная с которой движок держится за ход решения
    int? since;
    for (var d = 1; d <= _maxDepth; d++) {
      check();
      final lines = await bot.analyse(pos.fen, depth: d, multipv: 1);
      final hit = lines.isNotEmpty && keys.contains(lines.first.move);
      if (hit) {
        since ??= d;
      } else {
        since = null;
      }
    }
    final found = since ?? _maxDepth + 1;
    check();
    const s = Settings();
    // сколько ходов на этом шаге ведут к цели
    final wide = p.goalAt(step) == PuzzleGoal.defend
        ? const <Line>[]
        : await bot.analyse(pos.fen, depth: _maxDepth, multipv: 3);
    // в защите не применяется: второй держащий ход не делает точный легче
    final winners = math.max(1, wide.where((l) => p.keepsGoal(l.eval.negate(), step: step)).length);
    final shallow = await bot.analyse(pos.fen, depth: 2, multipv: 5);
    final key = shallow.where((l) => keys.contains(l.move)).firstOrNull;
    final keyValue = key?.eval.pawns(s) ?? (shallow.isEmpty ? 0.0 : shallow.first.eval.pawns(s));
    final traps =
        math.min(3, shallow.where((l) => !keys.contains(l.move) && l.eval.pawns(s) >= keyValue - 0.3).length);
    final m = NormalMove.fromUci(p.solution[step]);
    final quiet = !pos.isCapture(m) && !pos.givesCheck(m) && m.promotion == null;
    // шах, после которого у соперника 1–2 ответа, находится и без счёта
    final narrowCheck = pos.givesCheck(m) && pos.push(m).legalCount <= 2;
    // контрудары соперника после хода, которые надо просчитать
    var resources = 0;
    var forcing = 0;
    final after = pos.push(m);
    check();
    // после мата или пата отвечать нечем
    final replies = after.p.isGameOver ? const <Line>[] : await bot.analyse(after.fen, depth: 10, multipv: 5);
    if (replies.isNotEmpty) {
      final best = replies.first.eval.pawns(s);
      for (final l in replies) {
        final r = Pos.move(l.move);
        if (!after.isLegal(r)) continue;
        final sharp = after.givesCheck(r) || after.isCapture(r);
        if (sharp && best - l.eval.pawns(s) <= 1.0) resources++;
      }
      forcing = features.forcingCount(after, replies.first.pv, 12);
    }
    final calc = (75 * (found - 1) + 25 * math.min(8, math.max(0, forcing - 2))) * (narrowCheck ? 0.4 : 1.0);
    final score = (calc + 80 * traps + (quiet ? 120 : 0) + 70 * math.min(3, resources)) *
        (winners >= 3 ? 0.45 : (winners == 2 ? 0.6 : 1.0));
    return score.round();
  }

  final steps = <int>[];
  var pos = Pos.fromFen(p.fen);
  for (var i = 0; i < p.solution.length && steps.length < 3; i++) {
    final m = NormalMove.fromUci(p.solution[i]);
    if (!pos.isLegal(m)) break;
    if (i.isEven) steps.add(await stepScore(pos, i));
    pos = pos.push(m);
  }
  final hardest = steps.isEmpty ? 0 : steps.reduce(math.max);
  final others = steps.fold(0, (a, b) => a + b) - hardest;
  final rating = 700 +
      hardest +
      (0.35 * others).round() +
      90 * (p.solverMoves - 1) +
      (p.defends ? 100 : 0) +
      // комбинированная: цель меняется по ходу решения
      (p.combined ? 150 : 0);
  return rating.clamp(400, 3000).toInt();
}

bool _startsWith(List<String> a, List<String> prefix) {
  if (a.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (a[i] != prefix[i]) return false;
  }
  return true;
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
