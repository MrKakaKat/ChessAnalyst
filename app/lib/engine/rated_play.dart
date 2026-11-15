/// [авторское] An engine that plays at a chosen rating: not by weakening its
/// search (Skill Level), but by the accuracy of its moves. Before each move
/// it looks at its best moves (full strength) and works out, for each, what
/// its running accuracy would become; a move that would drop it below the
/// target accuracy of the rating is left out, and of the rest it plays the
/// one that keeps the accuracy closest to the target (a little above).
library;

import 'dart:math' as math;

import '../analysis/eval.dart';

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

  /// Chooses among [lines] (best first) and counts the chosen move.
  Line choose(List<Line> lines) {
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
    final allowed = [
      for (final l in lines)
        if (after(l) >= t - 1.5 && (!opening || acc(l) >= 95)) l,
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
