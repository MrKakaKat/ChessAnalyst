/// How a move looks to a human: how hard it was to see the punishment of a
/// mistake (its weight), whether the same best move was missed again, and
/// how intuitive the best move of a position is.
///
/// [авторское] All three come from the stored engine lines, without new
/// engine work, and are first estimates to be calibrated on real games.
///
/// **Weight of a mistake (0…100)** — how hard it was to see what the
/// opponent could do after it. The opponent's best line after the mistake is
/// followed until it wins material for good (two pawns or more, the reply
/// included) or mates; the number of the opponent's moves until then is the
/// depth of the punishment:
/// - a piece simply left hanging (the first move takes it for free) — 0;
/// - a one-move tactic (fork, pin, overload…) — 20;
/// - two moves — 35, three — 50, four or five — 60, six or more — 70;
/// - no material won within eight moves (a positional punishment) — 40;
/// - +10 when the punishing first move is quiet (no capture or check), +10
///   when the opponent had a single good reply there (an only move).
///
/// **Missed again** — the same best move was there on the player's previous
/// move as well and was not played either: the chance stayed on the board
/// and still went unseen. The count of such moves in a row raises the weight
/// of the mistake in the weakness profile.
///
/// **Intuitiveness of the best move (0…100)** — how likely a human is to
/// find it. From 70: a capture +15 (taking back +10 more), a check +10; a
/// sacrifice −35, a quiet move in a tactical position −20, a retreat −15,
/// each forcing ply of its line beyond two −4, a hard only move −10, an
/// obvious one +5. Within one game, best moves found that score under 30 hint
/// at unusual precision (a first step towards spotting engine help; no
/// verdict from a single game).
///
/// **Significance of a mistake (0…100)** — three equal parts:
/// - D, the drop of the evaluation: the pawns lost over 6 (6 pawns or an
///   allowed mate = 100);
/// - I, how intuitive the best move was (above): a natural move missed is
///   worse;
/// - C, how complex the position was: a mistake in a simple position is
///   worse. C = 60% narrowness (how few lines stay within half a pawn of the
///   best) + 40% the forcing length of the best line (six plies = full).
/// Significance = (D + I + (100 − C)) / 3.
///
/// **Rational aim (WDL)** — where it is more sensible to go from a
/// position, for the side to move, from the WDL of the best line:
/// - win: the chance to win is at least 30% and at least twice the chance
///   to lose — play for the win;
/// - draw: the chance to lose is at least 30% and at least twice the chance
///   to win — save the game, aim for a draw;
/// - balance: otherwise — keep the balance.
/// The human move is the engine line that serves the aim best, not always
/// the engine's first: for a win the most winning chances with little risk
/// (W − 1.5·L), for a draw the fewest losing chances (W + D), in balance
/// the best expected score. A first step towards the human path to a win or
/// a draw instead of the engine's risky single road.
library;

import 'dart:math' as math;

import 'package:dartchess/dartchess.dart' show Side;

import 'eval.dart';
import 'features.dart' as features;
import 'game.dart';
import 'kinds.dart';
import 'pos.dart';
import 'settings.dart';

class MoveWeight {
  const MoveWeight(this.value, this.moves, this.why);

  /// 0…100.
  final int value;

  /// The opponent's moves until the punishment won material (0: none).
  final int moves;
  final String why;
}

int _material(Pos b, Side side) => features.material(b, side) - features.material(b, side.opposite);

/// The weight of the mistake at [ply] (see the library comment); null when
/// there is no line after it.
MoveWeight? moveWeight(GameData g, int ply) {
  if (ply + 1 >= g.plies.length) return null;
  final next = g.plies[ply + 1];
  if (next.lines.isEmpty || next.lines.first.pv.isEmpty) return null;
  final start = Pos.fromFen(next.fenBefore);
  final punisher = start.turn;
  final pv = next.lines.first.pv;
  final m0 = _material(start, punisher);
  var pos = start;
  int? found;
  for (var i = 0; i < pv.length && i < 16; i++) {
    final m = Pos.move(pv[i]);
    if (!pos.isLegal(m)) break;
    pos = pos.push(m);
    if (pos.p.isCheckmate) {
      found = i;
      break;
    }
    // выигрыш засчитывается после ответа соперника (или в конце линии)
    if (i.isOdd || i == pv.length - 1) {
      if (_material(pos, punisher) - m0 >= 2) {
        found = i.isOdd ? i - 1 : i;
        break;
      }
    }
  }
  final first = Pos.move(pv.first);
  final quiet = !start.isCapture(first) && !start.givesCheck(first);
  const s = Settings();
  int value;
  String why;
  final moves = found == null ? 0 : found ~/ 2 + 1;
  if (found == null) {
    value = 40;
    why = 'a positional punishment';
  } else if (moves == 1 && kindsOf(start, first, pv, next.lines.first.eval, s).contains('free')) {
    return const MoveWeight(0, 1, 'a piece left hanging');
  } else {
    value = switch (moves) { 1 => 20, 2 => 35, 3 => 50, 4 || 5 => 60, _ => 70 };
    why = moves == 1 ? 'a one-move tactic' : 'a tactic of $moves moves';
  }
  if (quiet) value += 10;
  // у наказывающего был единственный хороший ответ
  final lines = next.lines;
  if (lines.length >= 2) {
    final best = lines.first.eval.pawns(s);
    final good = lines.where((l) => best - l.eval.pawns(s) <= 0.3).length;
    if (good == 1) value += 10;
  }
  return MoveWeight(math.min(100, value), moves, why);
}

/// How many of the player's moves in a row, ending at [ply], left the same
/// best move unplayed (0 when the best move at [ply] was new or played).
int missedAgain(GameAnalysis a, int ply) {
  String? best(int p) {
    final r = a.records[p];
    return r.bestMoves.isEmpty ? null : r.bestMoves.first.uci;
  }

  final b = best(ply);
  if (b == null || a.records[ply].uci == b) return 0;
  var n = 0;
  for (var p = ply - 2; p >= 0; p -= 2) {
    if (best(p) != b || a.records[p].uci == b) break;
    n++;
  }
  return n;
}

/// Intuitiveness of the best move at [ply] (see the library comment).
int intuitiveness(GameAnalysis a, int ply) {
  final r = a.records[ply];
  final p = a.game.plies[ply];
  if (p.lines.isEmpty) return 50;
  final line = p.lines.first;
  final board = Pos.fromFen(p.fenBefore);
  final m = Pos.move(line.move);
  const s = Settings();
  var v = 70;
  final capture = board.isCapture(m);
  if (capture) {
    v += 15;
    // взятие обратно — на поле, где только что брал соперник
    if (ply > 0) {
      final prev = Pos.fromFen(a.game.plies[ply - 1].fenBefore);
      final pm = Pos.move(a.game.plies[ply - 1].uci);
      if (prev.isCapture(pm) && pm.to == m.to) v += 10;
    }
  }
  if (board.givesCheck(m)) v += 10;
  final kinds = kindsOf(board, m, line.pv, line.eval, s);
  if (kinds.contains('sacrifice')) v -= 35;
  if (kinds.contains('retreat')) v -= 15;
  final tactical = r.bestMoves.isNotEmpty && r.bestMoves.first.type == 'tactical';
  if (tactical && !capture && !board.givesCheck(m) && !kinds.contains('fork') && !kinds.contains('fork_tactical') && !kinds.contains('tempo')) v -= 20;
  v -= 4 * math.max(0, features.forcingCount(board, line.pv, 10) - 2);
  if (r.bestMoves.isNotEmpty && r.bestMoves.first.onlyMove) {
    v += features.obviousCapture(board, m) ? 5 : -10;
  }
  return v.clamp(0, 100);
}

/// Hard best moves of [side] in the game: (found, chances) — positions
/// whose best move scores under 30, and how many of them the side played.
(int, int) hardMovesFound(GameAnalysis a, Side side) {
  var found = 0, chances = 0;
  for (final r in a.records) {
    if (r.side != side || r.step == 'book' || r.step == 'forced' || r.bestMoves.isEmpty) continue;
    if (intuitiveness(a, r.ply) >= 30) continue;
    chances++;
    if (r.bestMoves.any((b) => b.uci == r.uci)) found++;
  }
  return (found, chances);
}


/// Complexity of the position at [ply] (0…100), see the library comment.
int positionComplexity(GameData g, int ply) {
  final p = g.plies[ply];
  if (p.lines.isEmpty) return 50;
  const s = Settings();
  final best = p.lines.first.eval.pawns(s);
  final near = p.lines.where((l) => best - l.eval.pawns(s) <= 0.5).length;
  final narrow = p.lines.length < 2 ? 1.0 : 1 - (near - 1) / (p.lines.length - 1);
  final forcing = features.forcingCount(Pos.fromFen(p.fenBefore), p.lines.first.pv, 10);
  return (100 * (0.6 * narrow + 0.4 * math.min(1.0, forcing / 6))).round().clamp(0, 100);
}

class Significance {
  const Significance(this.drop, this.intuitive, this.complexity);

  /// D, I and C, each 0…100.
  final int drop, intuitive, complexity;

  int get value => ((drop + intuitive + (100 - complexity)) / 3).round();
}

/// Significance of the move at [ply] (see the library comment).
Significance significance(GameAnalysis a, int ply) {
  final r = a.records[ply];
  final mated = r.ep.mate != null && r.ep.mate! < 0 && !(r.e1.mate != null && r.e1.mate! < 0);
  final lost = math.max(0.0, r.pawns.e1 - r.pawns.ep);
  final drop = mated ? 100 : (lost / 6 * 100).round().clamp(0, 100);
  return Significance(drop, intuitiveness(a, ply), positionComplexity(a.game, ply));
}

class HumanAim {
  const HumanAim(this.aim, this.uci, this.wdl, {required this.engineBest});

  /// 'win', 'draw' or 'balance'.
  final String aim;

  /// The human move (UCI) and its WDL (per mille, side to move).
  final String uci;
  final (int, int, int) wdl;

  /// The human move is the engine's first line.
  final bool engineBest;
}

/// The rational aim and the human move at [ply] (see the library comment);
/// null without engine lines.
HumanAim? humanAim(GameData g, int ply) {
  final lines = g.plies[ply].lines;
  if (lines.isEmpty) return null;
  final (w, _, l) = lines.first.eval.wdl;
  final aim = w >= 300 && w >= 2 * l ? 'win' : (l >= 300 && l >= 2 * w ? 'draw' : 'balance');
  double score(Line x) {
    final (lw, ld, ll) = x.eval.wdl;
    return switch (aim) { 'win' => lw - 1.5 * ll, 'draw' => (lw + ld).toDouble(), _ => lw + ld / 2 };
  }

  var best = lines.first;
  for (final x in lines.skip(1)) {
    if (score(x) > score(best) + 1e-9) best = x;
  }
  return HumanAim(aim, best.move, best.eval.wdl, engineBest: identical(best, lines.first));
}
