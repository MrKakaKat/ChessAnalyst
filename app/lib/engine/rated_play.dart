/// [авторское] An engine that plays at a chosen rating: not by weakening its
/// search (Skill Level), but by the accuracy of its moves. Before each move
/// it looks at its best moves (full strength) and works out, for each, what
/// its running accuracy would become; a move that would drop it below the
/// target accuracy of the rating is left out, and of the rest it plays the
/// one that keeps the accuracy closest to the target (a little above).
library;

import 'dart:math' as math;

import 'package:dartchess/dartchess.dart' show NormalMove;

import '../analysis/difficulty.dart' show goodCount, narrowness, scoreOf;
import '../analysis/eval.dart';
import '../analysis/features.dart' as features;
import '../analysis/pos.dart';

/// The accuracy a player of [rating] has on average (the inverse of the
/// rating estimate of the game summary, for a usual game).
double accuracyForRating(int rating) {
  final x = ((rating - 400) / 2300).clamp(0.0, 1.0);
  return (55 + 42 * math.pow(x, 1 / 1.3)).toDouble();
}

/// Accuracy of a move that loses [dropPercent] of the expected result (as
/// in the game analysis).
double accuracyOfDrop(double dropPercent) =>
    (103.1668 * math.exp(-0.04354 * math.max(0, dropPercent)) - 3.1669).clamp(0.0, 100.0);

/// [авторское] The biggest loss of one move (percent of the expected
/// result) a player of [rating] makes in a hard place: 60 at 400, 29 at
/// 2000, 15 at 2700. In an easy place (many good moves) only 0.4 of it —
/// a strong player errs where the position is narrow, not where it is easy.
double maxDropForRating(int rating) {
  final x = ((rating - 400) / 2300).clamp(0.0, 1.0);
  return 60 - 45 * x;
}

/// Share of [maxDropForRating] left for an obvious error (a piece left to
/// be taken, a free capture or a mate let in or missed): all of it up to
/// 1000, none from 1800.
double obviousShareForRating(int rating) => (1 - (rating - 1000) / 800).clamp(0.0, 1.0);

/// Whether playing [l] instead of [best] in [pos] is an obvious error: the
/// move leaves material to be taken, the reply takes a free or bigger
/// piece or mates soon, or the best move was such a capture or a mate, or a
/// recapture on the square of the opponent's last move ([last]).
bool obviousError(Pos pos, Line best, Line l, {NormalMove? last}) {
  try {
    final m = NormalMove.fromUci(l.move);
    if (features.leavesMaterialEnPrise(pos, m)) return true;
    final mate = l.eval.mate;
    if (mate != null && mate < 0 && -mate <= 2) return true;
    if (l.pv.length >= 2) {
      final after = pos.push(m);
      final reply = NormalMove.fromUci(l.pv[1]);
      if (after.isLegal(reply) && features.obviousCapture(after, reply)) return true;
    }
    final b = NormalMove.fromUci(best.move);
    if (best.eval.mate != null && best.eval.mate! > 0 && best.eval.mate! <= 2) return true;
    if (features.obviousCapture(pos, b)) return true;
    if (last != null && pos.isCapture(b) && b.to == last.to) return true;
  } catch (_) {}
  return false;
}

/// Expected result of a line for the side to move, 0..1.
double expectedOf(Line l) => (l.eval.wdl.$1 + l.eval.wdl.$2 / 2) / 1000;

/// Running accuracy of the rated engine.
class RatedPlay {
  RatedPlay(this.rating, {math.Random? random}) : _rng = random ?? math.Random();

  final int rating;
  final math.Random _rng;
  final _accs = <double>[];
  double get _sum => _accs.fold(0.0, (a, b) => a + b);
  int get _moves => _accs.length;

  double get target => accuracyForRating(rating);

  /// The engine's accuracy so far (100 before its first move).
  double get accuracy => _moves == 0 ? 100 : _sum / _moves;

  /// Chooses among [lines] (best first) in [pos] (after the opponent's
  /// [last] move) and counts the chosen move.
  Line choose(List<Line> lines, {Pos? pos, NormalMove? last}) {
    if (lines.length < 2) return _take(lines.first, lines.first);
    final best = lines.first;
    // мат в один-два хода не упускается: на любом уровне это видно
    if (best.eval.mate != null && best.eval.mate! > 0 && best.eval.mate! <= 2) return _take(best, best);
    double acc(Line l) => accuracyOfDrop((expectedOf(best) - expectedOf(l)) * 100);
    double after(Line l) => (_sum + acc(l)) / (_moves + 1);
    final t = target;
    // дебют — почти лучшими ходами (как играют по теории); точность
    // подстраивается дальше
    final opening = _moves < 5;
    // [авторское] тяжесть ошибки — по рейтингу и по трудности места:
    // единственный ход можно упустить, лёгкую позицию испортить — меньше,
    // очевидный зевок (фигура под боем, даровое взятие, мат) сильный
    // игрок не делает вовсе
    final narrow = narrowness(goodCount([for (final l in lines) scoreOf(l.eval)]), lines.length);
    final cap = maxDropForRating(rating) * (0.4 + 0.6 * narrow);
    final obviousCap = cap * obviousShareForRating(rating);
    double drop(Line l) => (expectedOf(best) - expectedOf(l)) * 100;
    bool fits(Line l) {
      final d = drop(l);
      if (d <= 3) return true;
      if (d > cap) return false;
      return pos == null || d <= obviousCap || !obviousError(pos, best, l, last: last);
    }

    final allowed = [
      for (final l in lines)
        if (after(l) >= t - 1.5 && (!opening || acc(l) >= 95) && fits(l)) l,
    ];
    if (allowed.isEmpty) return _take(best, best);
    // ближе всего к цели, чуть выше неё; среди равных — случайно
    allowed.sort((a, b) => (after(a) - t).abs().compareTo((after(b) - t).abs()));
    final near = [for (final l in allowed) if ((after(l) - after(allowed.first)).abs() <= 1.0) l];
    return _take(near[_rng.nextInt(near.length)], best);
  }

  Line _take(Line chosen, Line best) {
    _accs.add(accuracyOfDrop((expectedOf(best) - expectedOf(chosen)) * 100));
    return chosen;
  }

  /// A move of the engine was taken back.
  void undo() {
    if (_accs.isNotEmpty) _accs.removeLast();
  }

  void reset() => _accs.clear();
}
