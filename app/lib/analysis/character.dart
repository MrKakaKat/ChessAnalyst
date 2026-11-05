/// Character of a position (docs/move_reference.md, 3.1–3.2).
///
/// [авторское] Trivial — sharp — middle: how many positive continuations the
/// position has. Over all legal moves, P positive and N negative:
/// - sharp: at most two positive moves;
/// - trivial: the side to move has an advantage (better or winning) and at
///   least 10% of the legal moves are positive — the advantage is easy to
///   keep; an equal position with many fine moves is not trivial;
/// - middle: in between (not marked).
/// The thresholds split the observed distribution into thirds (on the test
/// games a median position has ~5% positive moves), not the share itself.
/// A move is positive when it keeps the category of the best line (equal,
/// better, win…) and loses at most [positiveLoss] pawns to it; otherwise
/// negative. (The step scale was tried first: it marks almost every second
/// move an inaccuracy, so nearly all positions came out sharp.)
/// Quiet: no forcing move (check, capture, mate threat) in the first four
/// plies of the best line, and at least two positive moves.
///
/// [простое решение] Judged in pawns, on the low-depth pass over all legal
/// moves (a line that is also in MultiPV keeps its deeper evaluation).
/// Without that pass only MultiPV is known: the rest is worse than the last
/// line, so if that line is negative, all the rest are too; otherwise the
/// rest stays unknown and the character is given only when it holds either
/// way.
library;

import 'eval.dart';
import 'features.dart' as features;
import 'pos.dart';
import 'settings.dart';

enum Sharpness { trivial, middle, sharp }

class PositionCharacter {
  const PositionCharacter({required this.sharpness, required this.quiet, required this.positive, required this.negative});

  /// Null when the known moves cannot decide it.
  final Sharpness? sharpness;
  final bool quiet;
  final int positive, negative;
}

/// Largest loss to the best line that still counts as positive (pawns).
const positiveLoss = 0.3;

/// Sharp: at most this many positive moves.
const sharpMaxPositive = 2;

/// Trivial: at least this share of the legal moves is positive.
const trivialShare = 0.10;

PositionCharacter characterOf(Pos board, List<Line> lines, List<Line>? allLines, Settings s) {
  final n = board.legalCount;
  final deep = {for (final l in lines) l.move: l};
  final full = allLines != null && allLines.length >= n;
  final judged = full ? [for (final l in allLines) deep[l.move] ?? l] : lines;
  final pawns = s.pawns;
  final best = lines.isEmpty ? 0.0 : lines.first.eval.pawns(s);
  final cat = category(best, pawns);
  bool positive(Line l) {
    final v = l.eval.pawns(s);
    return category(v, pawns) >= cat && best - v <= positiveLoss;
  }

  var p = 0, neg = 0;
  bool? lastPositive;
  for (final l in judged) {
    lastPositive = positive(l);
    lastPositive ? p++ : neg++;
  }
  // неизвестный остаток: хуже последней линии
  var rest = full ? 0 : n - judged.length;
  if (rest > 0 && lastPositive == false) {
    neg += rest;
    rest = 0;
  }
  Sharpness? sharpness;
  final total = p + neg + rest;
  if (total > 0) {
    // [авторское] трети по распределению, а не по доле: острая — не больше
    // двух позитивных ходов, тривиальная — от 10 % легальных ходов
    if (p + rest <= sharpMaxPositive) {
      sharpness = Sharpness.sharp;
    } else if (p / total >= trivialShare && cat >= 3) {
      // тривиальная — только при перевесе ходящего: он реализуется легко
      sharpness = Sharpness.trivial;
    } else if (rest == 0 || (p + rest) / total < trivialShare) {
      sharpness = Sharpness.middle;
    }
  }
  var quiet = p >= 2 && lines.isNotEmpty;
  if (quiet) {
    var b = board;
    for (final uci in lines.first.pv.take(4)) {
      final m = Pos.move(uci);
      if (!b.isLegal(m) || features.isForcing(b, m)) {
        quiet = false;
        break;
      }
      b = b.push(m);
    }
  }
  return PositionCharacter(sharpness: sharpness, quiet: quiet, positive: p, negative: neg);
}
