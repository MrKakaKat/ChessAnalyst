/// AAC — evaluation by counterplay instead of engine score
/// (docs/move_reference.md, section 8).
///
/// [авторское] Three parts for each side:
/// - Abilities: own possibilities — opponent pieces under threat and checks
///   one could give;
/// - Activity: how much the pieces do — the free squares they control;
/// - Complication: how hard the position is for the opponent after one's
///   move — how much the opponent's other good-looking replies (lines 2–5)
///   lose against the best one: tanh(mean loss / 1.5), averaged with the
///   previous value (the count of positive replies was tried first: it is 1
///   in most positions, so the line sat at its ceiling).
/// Two-sided AAC (the graph and bar) compares the parts of both sides in
/// every position: (tanh(ΔAbilities/4) + tanh(ΔActivity/12) + ΔComplication)/3,
/// −1…+1 from White's side, averaged over two neighbouring plies (right
/// after a move the mover always has more threats, so raw values zigzag).
///
/// [простое решение] The weights and scales are first guesses, to be checked
/// against how the games really went.
library;

import 'dart:math' as math;

import 'package:dartchess/dartchess.dart' show NormalMove, Role, Side;

import 'character.dart' show positiveLoss;

import 'features.dart' show threatened;
import 'eval.dart';
import 'game.dart';
import 'pos.dart';
import 'settings.dart';

class AacPoint {
  const AacPoint({
    required this.abilities,
    required this.activity,
    required this.complication,
    required this.value,
  });

  final Map<Side, double> abilities, activity, complication;

  /// −1…+1 from White's side.
  final double value;
}

double _tanh(double x) => (math.exp(2 * x) - 1) / (math.exp(2 * x) + 1);

/// Abilities of [side] in [b]: 2 per threatened opponent piece, 1 per
/// positive check. For the side to move with engine lines ([lines]: the
/// lines of [b], all legal moves when known) a check is positive when it
/// keeps the category of the best line and loses at most 0.3 pawns to it
/// (as in character.dart); otherwise (no lines, or the side not to move) a
/// check is counted when the checking piece is not simply lost: its square
/// is not attacked, or it is defended and no cheaper piece attacks it.
double abilitiesOf(Pos b, Side side, {List<Line>? lines}) {
  final threats = threatened(b, side.opposite).length;
  Pos? asMover = b.turn == side ? b : (b.isCheck ? null : b.nullMove());
  var checks = 0;
  if (asMover != null) {
    const s = Settings();
    final byMove = {for (final l in (lines ?? const <Line>[]).reversed) l.move: l};
    final engine = asMover == b && byMove.isNotEmpty;
    final best = engine ? lines!.first.eval.pawns(s) : 0.0;
    for (final m in asMover.legalMoves) {
      if (!asMover.givesCheck(m)) continue;
      final l = engine ? byMove[m.uci] : null;
      if (l != null) {
        final v = l.eval.pawns(s);
        if (category(v, s.pawns) >= category(best, s.pawns) && best - v <= positiveLoss) checks++;
      } else if (_safeCheck(asMover, m)) {
        checks++;
      }
    }
  }
  return 2.0 * threats + checks;
}

bool _safeCheck(Pos b, NormalMove m) {
  final me = b.turn;
  final after = b.push(m);
  final to = m.to;
  if (!after.isAttackedBy(me.opposite, to)) return true;
  if (!after.isAttackedBy(me, to)) return false;
  final mine = _worth(after.roleAt(to));
  for (final sq in after.attackers(me.opposite, to).squares) {
    if (_worth(after.roleAt(sq)) < mine) return false;
  }
  return true;
}

int _worth(Role? r) => switch (r) {
      Role.pawn => 1,
      Role.knight || Role.bishop => 3,
      Role.rook => 5,
      Role.queen => 9,
      Role.king => 100,
      _ => 0,
    };

/// Activity of [side] in [b]: the squares its pieces (not pawns or the
/// king) control that are not occupied by own pieces. Pins and defensive
/// duties were counted at first; they barely moved the line and were
/// dropped.
double activityOf(Pos b, Side side) {
  var mobility = 0;
  for (final (sq, p) in b.pieces) {
    if (p.color != side || p.role == Role.king || p.role == Role.pawn) continue;
    mobility += b.attacks(sq).squares.where((t) => b.pieceAt(t)?.color != side).length;
  }
  return mobility.toDouble();
}

/// A trick: in a lost position, the chances that the winner goes wrong into
/// a draw — stalemate, perpetual check or another drawing line.
class Trick {
  const Trick({required this.traps, required this.stalemates, required this.perpetuals, required this.legal});

  /// Winner's moves that let the game slip to a draw (|eval| ≤ 0.3).
  final int traps;

  /// Of them: moves that stalemate at once, and those after which the
  /// loser's line starts with a check (perpetual).
  final int stalemates, perpetuals;
  final int legal;

  /// 0…1: tanh(traps / 3).
  double get value => _tanh(traps / 3);
}

/// The trick of the move that led to the position [next] (the winner to
/// move): only when that position is winning for the winner (+2 or more).
/// [авторское] Counted over all the winner's moves known (all legal moves at
/// a small depth when the analysis has them, else the deep lines).
Trick? trickOf(GamePly next) {
  const s = Settings();
  if (next.lines.isEmpty) return null;
  final best = next.lines.first.eval.pawns(s);
  if (best < s.pawns.b2) return null;
  final board = Pos.fromFen(next.fenBefore);
  final deep = {for (final l in next.lines) l.move: l};
  final all = next.allLines ?? next.lines;
  var traps = 0, stalemates = 0, perpetuals = 0;
  for (final l0 in all) {
    final l = deep[l0.move] ?? l0;
    if (l.eval.mate != null || l.eval.pawns(s).abs() > 0.3) continue;
    traps++;
    final m = Pos.move(l.move);
    if (!board.isLegal(m)) continue;
    final after = board.push(m);
    if (after.p.isStalemate) {
      stalemates++;
    } else if (l.pv.length >= 2 && after.isLegal(Pos.move(l.pv[1])) && after.givesCheck(Pos.move(l.pv[1]))) {
      perpetuals++;
    }
  }
  if (traps == 0) return null;
  return Trick(traps: traps, stalemates: stalemates, perpetuals: perpetuals, legal: board.legalCount);
}

/// Complication of a position for the side to move: the mean loss of its
/// second to fifth lines against the best (pawns, each capped at 3).
double _complication(List<Line> lines, Settings s) {
  if (lines.length < 2) return 1.0;
  final best = lines.first.eval.pawns(s);
  final rest = lines.skip(1).take(4).map((l) => math.min(3.0, math.max(0.0, best - l.eval.pawns(s)))).toList();
  return _tanh(rest.reduce((a, b) => a + b) / rest.length / 1.5);
}

/// AAC after every ply of the game (index = ply, as the move records).
List<AacPoint> aacOf(GameData game) {
  const s = Settings();
  final out = <AacPoint>[];
  final complication = {Side.white: 0.0, Side.black: 0.0};
  for (var i = 0; i < game.plies.length; i++) {
    final p = game.plies[i];
    final b = Pos.fromFen(p.fenBefore).push(Pos.move(p.uci));
    final mover = Pos.fromFen(p.fenBefore).turn;
    // сложность, которую ход создал сопернику: его позитивные ответы
    if (i + 1 < game.plies.length) {
      final next = game.plies[i + 1];
      // сглаживание: половина — прошлое значение
      complication[mover] = 0.5 * complication[mover]! + 0.5 * _complication(next.lines, s);
    }
    // линии позиции после хода — у следующего полухода
    final next = i + 1 < game.plies.length ? game.plies[i + 1] : null;
    final known = next == null ? null : [...next.lines, ...?next.allLines];
    final ab = {for (final side in Side.values) side: abilitiesOf(b, side, lines: known)};
    final act = {for (final side in Side.values) side: activityOf(b, side)};
    final value = (_tanh((ab[Side.white]! - ab[Side.black]!) / 4) +
            _tanh((act[Side.white]! - act[Side.black]!) / 12) +
            (complication[Side.white]! - complication[Side.black]!)) /
        3;
    out.add(AacPoint(
        abilities: ab, activity: act, complication: Map.of(complication), value: value));
  }
  // после своего хода у ходившего всегда больше угроз — значения скачут
  // через полуход; оценка — среднее двух соседних полуходов
  return [
    for (var i = 0; i < out.length; i++)
      i == 0
          ? out[i]
          : AacPoint(
              abilities: out[i].abilities,
              activity: out[i].activity,
              complication: out[i].complication,
              value: (out[i].value + out[i - 1].value) / 2),
  ];
}
