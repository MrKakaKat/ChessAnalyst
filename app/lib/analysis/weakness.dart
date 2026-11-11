/// What a mistake says about the player (docs/move_reference.md, 5–6).
///
/// [авторское] For every negative move:
/// - loss kind: deterioration (from an equal position to a worse one) or
///   loss of an advantage — nonfatal (+1 or more is left), bad (down to the
///   middle, not below −0.5), full (below −0.5, the opponent is better);
/// - irreversibility: low (the fall happened in an equal position), mid (in
///   a better one), high (in a winning one);
/// - the facts around it, as tags: colour, stage, type of the missed best
///   move, kinds of the missed move, loss kind, irreversibility.
/// The tags of all mistakes give the weakness profile; puzzles carry the
/// same tags, so a puzzle "like your mistakes" scores high. Mistakes the
/// player underlined (not understood as mistakes) count double.
library;

import 'package:dartchess/dartchess.dart' show Side;

import 'classify.dart';
import 'eval.dart';
import 'kinds.dart';
import 'pos.dart';
import 'settings.dart';

const lossLabels = {
  'deterioration': 'Worse from equal',
  'nonfatal': 'Advantage reduced',
  'bad': 'Advantage lost',
  'full': 'Advantage given away',
};

const irreversibilityLabels = {'low': 'Low', 'mid': 'Medium', 'high': 'High'};

/// Loss kind of a move from the evaluations before and after it (pawns,
/// mover's side); null when there was nothing to lose.
String? lossKind(double before, double after) {
  if (after >= before - 0.1) return null;
  // без перевеса: позиция просто ухудшилась
  if (before < 1.0) return 'deterioration';
  if (after >= 1.0) return 'nonfatal';
  if (after >= -0.5) return 'bad';
  return 'full';
}

/// Irreversibility of a fall: how much there was to lose.
String irreversibilityOf(double before) => before >= 3.0 ? 'high' : (before >= 1.0 ? 'mid' : 'low');

/// The kinds of the punishment of a mistake: in the opponent's best line
/// after it ([after], [reply]), the first of the opponent's moves (up to the
/// fourth) that does something sharp — mate, a fork, a pin, a sacrifice, a
/// tempo attack, a promotion, poisoned material or a barter. Not always the
/// next move: the punishment can come after a quiet preparation.
List<String> punishKinds(Pos after, Line reply, {Settings s = const Settings()}) {
  const sharp = {'mate', 'promotion', 'fork', 'fork_tactical', 'block_escape', 'pin', 'overload', 'sacrifice', 'tempo', 'free', 'barter', 'simplification'};
  var pos = after;
  final pv = reply.pv;
  for (var i = 0; i < pv.length && i < 8; i++) {
    final m = Pos.move(pv[i]);
    if (!pos.isLegal(m)) break;
    if (i.isEven) {
      final kinds = kindsOf(pos, m, pv.sublist(i), reply.eval, s);
      final hit = [for (final k in kinds) if (sharp.contains(k)) k];
      if (hit.isNotEmpty) return hit.take(2).toList();
    }
    pos = pos.push(m);
  }
  return const [];
}

/// The direction tag of a best move: attacking, defensive, counterattacking
/// or a combination ("attacking+defensive").
String? _dirTag(MoveRecord r) {
  if (r.bestMoves.isEmpty || r.bestMoves.first.subtypes.isEmpty) return null;
  return 'dir:${r.bestMoves.first.subtypes.join('+')}';
}

/// Tags of a negative move [r] (for the profile) or of a puzzle's key move.
/// [after] and [reply]: the position after the move and the opponent's best
/// line there, for the kinds of the punishment.
Set<String> mistakeTags(MoveRecord r, Pos board, Line best,
    {Settings s = const Settings(), Pos? after, Line? reply, List<Line>? lines}) {
  final before = r.pawns.e1, afterValue = r.pawns.ep;
  return {
    'colour:${r.side == Side.white ? 'white' : 'black'}',
    'stage:${r.stage}',
    if (r.bestMoves.isNotEmpty) 'type:${r.bestMoves.first.type}',
    ?_dirTag(r),
    for (final k in kindsOf(board, Pos.move(best.move), best.pv, best.eval, s, lines: lines).take(2)) 'kind:$k',
    if (after != null && reply != null)
      for (final k in punishKinds(after, reply, s: s)) 'punish:$k',
    if (lossKind(before, afterValue) case final l?) 'loss:$l',
    'irr:${irreversibilityOf(before)}',
  };
}

/// Tags of a puzzle from its position and key move.
Set<String> puzzleTags(MoveRecord r, Pos board, Line best, {Settings s = const Settings(), List<Line>? lines}) => {
      'colour:${r.side == Side.white ? 'white' : 'black'}',
      'stage:${r.stage}',
      if (r.bestMoves.isNotEmpty) 'type:${r.bestMoves.first.type}',
      ?_dirTag(r),
      for (final k in kindsOf(board, Pos.move(best.move), best.pv, best.eval, s, lines: lines).take(2)) 'kind:$k',
      // задача — это наказание чужой ошибки: её виды подходят и к «чем наказали»
      for (final k in kindsOf(board, Pos.move(best.move), best.pv, best.eval, s).take(2)) 'punish:$k',
      'irr:${irreversibilityOf(r.pawns.e1)}',
    };

const negativeSteps = {'inaccuracy', 'pass', 'laxity', 'mistake', 'blunder'};

/// Weight of a mistake in the profile: the worse, the heavier; underlined
/// ones double.
double mistakeWeight(String step, {bool underlined = false}) =>
    (switch (step) { 'blunder' => 4.0, 'mistake' => 3.0, 'laxity' => 2.0, 'pass' => 1.5, _ => 1.0 }) *
    (underlined ? 2 : 1);

/// How well [tags] match the weakness [profile] (tag → weight). The kinds
/// of the missed best move weigh most, then the kinds of the punishment
/// (what you were answered with), then the rest.
double similarity(Set<String> tags, Map<String, double> profile) {
  var s = 0.0;
  for (final t in tags) {
    final w = t.startsWith('kind:') ? 3.0 : (t.startsWith('punish:') ? 2.0 : 1.0);
    s += w * (profile[t] ?? 0);
  }
  return s;
}
