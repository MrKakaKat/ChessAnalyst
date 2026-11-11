/// The difficulty pass over one position: the engine looks at each node of
/// its best lines (see difficulty.dart). Engine-agnostic: [analyse] gives the
/// root lines of a FEN with a number of moves.
library;

import 'difficulty.dart';
import 'eval.dart';
import 'pos.dart';

typedef Analyse = Future<List<Line>> Function(String fen, int multipv);

/// Depth of the node searches for an analysis at [depth].
int nodeDepth(int depth) => (depth - 4).clamp(8, 10);

/// Scans the lines of the position [fen] ([lines]: its root lines, best
/// first). [cache]: node results by position, shared over a game.
Future<PlyScan> scanPosition(String fen, List<Line> lines, Analyse analyse,
    {required int depth, Map<String, List<int>>? cache, bool Function()? stopped}) async {
  final out = <int, List<List<int>?>>{};
  for (final e in scanPlan(lines).entries) {
    final pv = lines[e.key].pv;
    final last = e.value.isEmpty ? 0 : e.value.last;
    final nodes = List<List<int>?>.filled(last + 1, null, growable: true);
    var pos = Pos.fromFen(fen);
    var wanted = e.value.toSet();
    for (var j = 1; j <= last; j++) {
      if (stopped?.call() ?? false) return PlyScan(depth, out);
      final m = Pos.move(pv[j - 1]);
      if (!pos.isLegal(m)) break;
      pos = pos.push(m);
      if (pos.isGameOver) break;
      if (!wanted.contains(j)) continue;
      final key = pos.fen.split(' ').take(4).join(' ');
      var scores = cache?[key];
      if (scores == null) {
        final ls = await analyse(pos.fen, nodeLines);
        scores = [for (final l in ls) scoreOf(l.eval)];
        cache?[key] = scores;
      }
      nodes[j] = scores;
    }
    out[e.key] = nodes;
  }
  return PlyScan(depth, out);
}
