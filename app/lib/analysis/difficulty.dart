/// Difficulty of a position for each side and the practical evaluation.
///
/// [авторское] The engine says how big an advantage is, not how hard it is
/// to keep. Classic puzzles have one way to win and every other move draws or
/// loses; ours come from any position of a game, so the same +6 can be easy
/// (many ways) or a long narrow path. The difficulty analysis (a separate,
/// optional pass after the classic one) measures that.
///
/// Outcome classes (side to move): win at +3 or more (a mate counts as +8),
/// loss at −3 or less, otherwise a draw. Only the boundary 3 matters.
///
/// 1. Nodes. Along the best lines of a position the engine looks at every
///    move of the line with a few moves of its own (MultiPV 3). A move is
///    good when it keeps the class of the best move there and, when that is
///    not a win, loses no more than a pawn (more is a mistake). One good
///    move of two or more is an only move; two good moves are a narrow place.
/// 2. Weight of an only move by its distance: the k-th own move of the line
///    weighs 0.15 + 0.085·(k − 1), up to 1: on the 2nd move it is little, on
///    the 10th it is a lot. An obvious only move — a recapture, a piece
///    taken away from an attack — weighs 0.3 of that. A tactical only move (check, capture, promotion)
///    and a positional one (a quiet move) weigh the same; the second is
///    marked so (draws are often a row of positional only moves).
/// 3. A mate line counts as one only move at the distance of the mate: a mate
///    in 2 is easy, a mate in 10 is hard. A mate in one is a positional mate
///    — the lightest only move (and missing it is always a blunder).
/// 4. Difficulty of a line for a side: 1 − Π(1 − narrowness·weight) over its
///    own moves in the line — 0% when every move has several ways on, up to
///    100% with one far tactical only move.
/// 5. Difficulty of the position for the side to move: the mean difficulty
///    of its good lines divided by √(number of good lines) — more ways,
///    easier — with its first move as an only move when there is one good
///    move. For the other side: its moves in the best line.
/// 6. As a percent against the middle standard: the share of positions of
///    reference games that are easier ([difficultyPercent]); 50% is a usual
///    position.
/// 7. Practical evaluation: E′ = E · (1.5 − D), D of the side ahead: +6 at
///    80% → +4.2, at 30% → +7.2. A position under +3 by it is disputed.
library;

import 'dart:math' as math;

import 'package:dartchess/dartchess.dart' show Role;

import 'eval.dart';
import 'pos.dart';

/// The winning boundary in pawns.
const winBoundary = 3.0;

/// A mate in pawns for the classes and the practical evaluation.
const matePawns = 8.0;

/// Moves looked at in each node of a line.
const nodeLines = 3;

/// Plies of a line looked at.
const linePlies = 12;

/// Lines of the side to move looked at (the best ones that keep its class).
const scannedLines = 5;

/// A score for storage: centipawns, or ±(20000 − n) for a mate in n.
int scoreOf(Eval e) => e.mate != null ? (e.mate! > 0 ? 20000 - e.mate! : -20000 - e.mate!) : e.cp!.clamp(-9999, 9999);

double pawnsOfScore(int s) => s.abs() >= 10000 ? (s > 0 ? matePawns : -matePawns) : (s / 100).clamp(-matePawns, matePawns);

double pawnsOfEval(Eval e) => pawnsOfScore(scoreOf(e));

/// 1 win, 0 draw, −1 loss (side to move).
int outcomeOf(double pawns) => pawns >= winBoundary ? 1 : (pawns <= -winBoundary ? -1 : 0);

/// Weight of an only move that is the [k]-th own move of a line.
double onlyWeight(int k) => math.min(1.0, 0.15 + 0.085 * (k - 1));

/// Pawns a good move may lose when the position is not won (the mistake
/// threshold of the analysis).
const goodLoss = 1.0;

/// Good moves among [scores] (best first, side to move): those that keep
/// the class of the best; when it is not a win, also losing no more than
/// [goodLoss] (otherwise the move is a mistake).
int goodCount(List<int> scores) {
  if (scores.isEmpty) return 0;
  final best = pawnsOfScore(scores.first);
  final c = outcomeOf(best);
  return scores.where((s) {
    final p = pawnsOfScore(s);
    if (outcomeOf(p) < c) return false;
    return c == 1 || c == -1 || best - p <= goodLoss;
  }).length;
}

bool _goodLine(double best, double p) {
  final c = outcomeOf(best);
  if (outcomeOf(p) < c) return false;
  return c != 0 || best - p <= goodLoss;
}

/// How narrow a place is: 1 for an only move, 0.35 for two good moves, 0 for
/// more (or for a forced move: nothing to choose).
double narrowness(int good, int moves) {
  if (moves < 2) return 0;
  if (good == 1) return 1;
  if (good == 2 && moves >= 3) return 0.35;
  return 0;
}

/// What the difficulty pass keeps for one position: for each scanned line
/// (index in the position's lines) the scores of the best moves at each node
/// of it (node j = after j moves of the line; null when not looked at).
class PlyScan {
  const PlyScan(this.depth, this.lines);

  final int depth;
  final Map<int, List<List<int>?>> lines;

  Map<String, dynamic> toJson() => {
        'd': depth,
        'l': {for (final e in lines.entries) '${e.key}': e.value},
      };

  factory PlyScan.fromJson(Map<String, dynamic> j) => PlyScan(j['d'] as int, {
        for (final e in (j['l'] as Map).entries)
          int.parse(e.key as String): [
            for (final n in e.value as List) n == null ? null : (n as List).cast<int>(),
          ],
      });
}

/// Which lines of a position to scan and which of their nodes: the best line
/// fully (both sides), the other good lines of the side to move at its own
/// moves. Mate lines are not scanned (their difficulty is the mate's length).
Map<int, List<int>> scanPlan(List<Line> lines) {
  if (lines.isEmpty) return const {};
  final best = pawnsOfEval(lines.first.eval);
  final out = <int, List<int>>{};
  var taken = 0;
  for (var i = 0; i < lines.length && taken < scannedLines; i++) {
    final l = lines[i];
    if (!_goodLine(best, pawnsOfEval(l.eval))) continue;
    taken++;
    if (l.eval.mate != null) continue;
    final last = math.min(linePlies, l.pv.length - 1);
    out[i] = [for (var j = 1; j <= last; j++) if (i == 0 || j.isEven) j];
  }
  return out;
}

/// An only move found in a line: its index in the line, whose (true: the
/// side to move at the root), tactical or positional, and its weight.
class OnlyMove {
  const OnlyMove(this.index, this.root, this.tactical, this.weight);
  final int index;
  final bool root;
  final bool tactical;
  final double weight;
}

/// Only moves of [line] from its scan [nodes] (the root counts when
/// [rootOnly]); obvious ones (recaptures, escapes) are left out.
List<OnlyMove> onlyMoves(String fen, Line line, List<List<int>?>? nodes, {bool rootOnly = false}) {
  final out = <OnlyMove>[];
  final at = _along(fen, line.pv, nodes?.length ?? 1);
  if (rootOnly && !_obvious(at, line.pv, 0)) out.add(OnlyMove(0, true, _forcing(fen, line.pv, 0), onlyWeight(1)));
  if (nodes == null) return out;
  for (var j = 1; j < nodes.length; j++) {
    final n = nodes[j];
    if (n == null || n.length < 2 || j >= line.pv.length) continue;
    if (goodCount(n) == 1 && pawnsOfScore(n.first) > -winBoundary && !_obvious(at, line.pv, j)) {
      out.add(OnlyMove(j, j.isEven, _forcing(fen, line.pv, j), onlyWeight(j ~/ 2 + 1)));
    }
  }
  return out;
}

bool _forcing(String fen, List<String> pv, int j) {
  try {
    var p = Pos.fromFen(fen);
    for (var i = 0; i < j; i++) {
      p = p.push(Pos.move(pv[i]));
    }
    final m = Pos.move(pv[j]);
    return p.givesCheck(m) || p.isCapture(m) || pv[j].length == 5;
  } catch (_) {
    return false;
  }
}

/// Positions along [pv] from [fen]: [0] is [fen], [j] after j moves (stops
/// at an illegal move).
List<Pos> _along(String fen, List<String> pv, int n) {
  final out = <Pos>[];
  try {
    var p = Pos.fromFen(fen);
    out.add(p);
    for (var i = 0; i < n && i < pv.length; i++) {
      final m = Pos.move(pv[i]);
      if (!p.isLegal(m)) break;
      p = p.push(m);
      out.add(p);
    }
  } catch (_) {}
  return out;
}

/// An obvious only move weighs this share: a recapture, or a piece taken
/// away from an attack (by a cheaper piece, or when it is not defended).
const obviousShare = 0.3;

/// Whether move [j] of [pv] (positions [at]) is obvious.
bool _obvious(List<Pos> at, List<String> pv, int j) {
  try {
    return _isObvious(at, pv, j);
  } catch (_) {
    return false;
  }
}

bool _isObvious(List<Pos> at, List<String> pv, int j) {
  if (j >= at.length || j >= pv.length) return false;
  final p = at[j];
  final m = Pos.move(pv[j]);
  // взятие в ответ на том же поле
  if (j > 0 && j - 1 < at.length) {
    final prev = Pos.move(pv[j - 1]);
    if (at[j - 1].isCapture(prev) && m.to == prev.to && p.isCapture(m)) return true;
  }
  // уход атакованной фигуры: бьёт более дешёвая или она без защиты
  final piece = p.pieceAt(m.from);
  if (piece == null || piece.role == Role.king) return false;
  final enemy = piece.color.opposite;
  final attackers = p.attackers(enemy, m.from);
  if (attackers.isEmpty) return false;
  final value = pieceValues[piece.role]!;
  final cheapest = [for (final a in attackers.squares) pieceValues[p.roleAt(a)]!].reduce(math.min);
  return cheapest < value || p.attackers(piece.color, m.from).isEmpty;
}

/// Weight of an only move at index [j] of a line ([at]: positions along it):
/// by its distance, less when it is obvious.
double _onlyAt(List<Pos> at, List<String> pv, int j) =>
    onlyWeight(j ~/ 2 + 1) * (_obvious(at, pv, j) ? obviousShare : 1);

/// Difficulty of [line] from [fen] for the side to move at the root
/// ([root]) or the other side, from its scan [nodes].
double lineDifficulty(String fen, Line line, List<List<int>?>? nodes, {required bool root}) {
  final m = line.eval.mate;
  if (m != null) {
    // мат — одно only move на расстоянии мата; у проигрывающей стороны
    // выбора нет
    if ((m > 0) == root) return onlyWeight(m.abs());
    return 0;
  }
  if (nodes == null) return 0;
  final at = _along(fen, line.pv, nodes.length);
  var keep = 1.0;
  for (var j = root ? 2 : 1; j < nodes.length; j += 2) {
    final n = nodes[j];
    if (n == null || n.isEmpty) continue;
    final narrow = narrowness(goodCount(n), n.length);
    if (narrow == 0) continue;
    keep *= 1 - narrow * _onlyAt(at, line.pv, j);
  }
  return 1 - keep;
}

/// Raw difficulty of a position (0..1) for the side to move and for the
/// other side.
class Difficulty {
  const Difficulty(this.mover, this.other);
  final double mover, other;
}

Difficulty rawDifficulty(String fen, List<Line> lines, PlyScan scan) {
  if (lines.isEmpty) return const Difficulty(0, 0);
  final best = pawnsOfEval(lines.first.eval);
  final good = [for (var i = 0; i < lines.length; i++) if (_goodLine(best, pawnsOfEval(lines[i].eval))) i];
  // средняя трудность хороших линий, и чем их больше, тем легче (÷√n);
  // непросмотренные хорошие линии только добавляют путей
  var sum = 0.0, seen = 0;
  for (final i in good) {
    if (!scan.lines.containsKey(i) && lines[i].eval.mate == null) continue;
    sum += lineDifficulty(fen, lines[i], scan.lines[i], root: true);
    seen++;
  }
  final all = seen == 0 ? 0.0 : sum / seen / math.sqrt(good.length);
  final first = narrowness(good.length, lines.length) * _onlyAt(_along(fen, lines.first.pv, 1), lines.first.pv, 0);
  final mover = 1 - (1 - first) * (1 - all);
  final other = lineDifficulty(fen, lines.first, scan.lines[0], root: false);
  return Difficulty(mover, other);
}

/// Raw difficulty → percent against the middle standard: the share of
/// positions of the reference games that are easier (ties count half).
/// [_reference]: quantiles of the raw difficulty in those games (0%, 5%, …
/// 100%), measured with the same pass (tool/calibrate_difficulty.dart).
double difficultyPercent(double raw, {bool other = false}) {
  final q = other ? _referenceOther : _reference;
  if (raw < q.first) return 0;
  if (raw >= q.last) return 1;
  // доля позиций легче и половина равных
  var below = 0, equal = 0;
  for (final x in q) {
    if ((x - raw).abs() < 1e-9) {
      equal++;
    } else if (x < raw) {
      below++;
    }
  }
  if (equal > 0) return ((below + equal / 2) - 0.5) / (q.length - 1);
  // между соседними квантилями — линейно
  final i = below - 1;
  final t = (raw - q[i]) / (q[i + 1] - q[i]);
  return (i + t) / (q.length - 1);
}

// 12 games (masters, engines and one of ours), 1103 positions, depth 18 →
// nodes at depth 10
const _reference = [
  0.0, 0.0, 0.0, 0.0, 0.004, 0.012, 0.019, 0.027, 0.035, 0.046, 0.057, //
  0.068, 0.083, 0.101, 0.121, 0.150, 0.185, 0.232, 0.324, 0.506, 0.954,
];

// the same for the other side (its moves in the best line)
const _referenceOther = [
  0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.016, 0.045, //
  0.076, 0.121, 0.150, 0.200, 0.248, 0.314, 0.450, 0.589, 0.712, 0.926,
];

/// Practical evaluation in pawns (side to move): the engine's [pawns]
/// changed by the difficulty (percent) of the side ahead.
double practicalPawns(double pawns, {required double moverPercent, required double otherPercent}) {
  final p = pawns.clamp(-matePawns, matePawns).toDouble();
  final d = p >= 0 ? moverPercent : otherPercent;
  return p * (1.5 - d);
}

/// Accuracy of a move changed by the difficulty of its position: a miss in
/// a hard position costs less, in an easy one more.
double accuracyWithDifficulty(double accuracy, double percent) =>
    (100 - (100 - accuracy) * (1.5 - percent)).clamp(0, 100).toDouble();

/// Difficulty of a position of a game in percent, with its practical
/// evaluation (side to move).
class PositionDifficulty {
  const PositionDifficulty(this.mover, this.other, this.engine, this.practical);

  /// Difficulty for the side to move and for the other side, 0..1.
  final double mover, other;

  /// The engine's evaluation and the practical one, pawns, side to move.
  final double engine, practical;

  /// The practical evaluation says the position is clear (a side is ahead
  /// by [winBoundary] or more).
  bool get clear => practical.abs() >= winBoundary;
}

PositionDifficulty positionDifficulty(String fen, List<Line> lines, PlyScan scan) {
  final raw = rawDifficulty(fen, lines, scan);
  final m = difficultyPercent(raw.mover), o = difficultyPercent(raw.other, other: true);
  final e = lines.isEmpty ? 0.0 : pawnsOfEval(lines.first.eval);
  return PositionDifficulty(m, o, e, practicalPawns(e, moverPercent: m, otherPercent: o));
}

/// [авторское] Practical evaluation for the side to move once its key move
/// is found: the best line's evaluation with the difficulty of keeping it —
/// its own moves in the best line after the first (a single line, so
/// against the other side's reference). The difficulty before the move is
/// the puzzle's difficulty, not a doubt about the result.
double practicalAfterKey(String fen, List<Line> lines, PlyScan scan) {
  if (lines.isEmpty) return 0;
  final e = pawnsOfEval(lines.first.eval);
  final m = lines.first.eval.mate;
  // мат: трудность — длина мата без первого хода
  final raw = m != null && m > 0
      ? (m > 1 ? onlyWeight(m - 1) : 0.0)
      : lineDifficulty(fen, lines.first, scan.lines[0], root: true);
  return practicalPawns(e, moverPercent: difficultyPercent(raw, other: true), otherPercent: 0.5);
}

/// Mean difficulty of the positions where a side moved (white: true), 0..1;
/// null without the difficulty analysis.
double? sideDifficulty(List<PositionDifficulty?> positions, {required bool white, required bool whiteFirst}) {
  var sum = 0.0, n = 0;
  for (var i = 0; i < positions.length; i++) {
    final p = positions[i];
    if (p == null || (i.isEven == whiteFirst) != white) continue;
    sum += p.mover;
    n++;
  }
  return n == 0 ? null : sum / n;
}

/// The good lines of a position (indices), see [goodCount].
List<int> goodLines(List<Line> lines) {
  if (lines.isEmpty) return const [];
  final best = pawnsOfEval(lines.first.eval);
  return [for (var i = 0; i < lines.length; i++) if (_goodLine(best, pawnsOfEval(lines[i].eval))) i];
}

/// Line [i] of a position needs an only move of the side to move: its first
/// move is the one good move (known from the classic analysis), or the
/// difficulty pass found one further on ([scan]).
bool lineHasOnly(String fen, List<Line> lines, int i, PlyScan? scan) {
  if (i == 0 &&
      lines.length >= 2 &&
      goodLines(lines).length == 1 &&
      pawnsOfEval(lines.first.eval) > -winBoundary &&
      !_obvious(_along(fen, lines.first.pv, 1), lines.first.pv, 0)) {
    return true;
  }
  final nodes = scan?.lines[i];
  if (nodes == null) return false;
  return onlyMoves(fen, lines[i], nodes).any((o) => o.root);
}
