/// Route of a piece to its target for the idea arrow.
///
/// A chain entry names the attacker and its target, but the attacker does not
/// always hit the target from where it stands: a bishop on c8 aims at f3 over
/// two of its own moves. The arrow then follows the shortest route on the
/// current board: through empty squares, other pieces standing still.
library;

import 'package:dartchess/dartchess.dart';

import 'pos.dart';

/// Squares from [from] to [target] (both included): [from, target] when the
/// piece hits the target directly; for a long-range piece (bishop, rook,
/// queen) the shortest route of at most [maxLegs] moves; otherwise null —
/// the attacker is not on its way yet and the arrow is not drawn (a knight
/// three jumps away is outside the idea's line).
List<Square>? piecePath(Pos pos, Square from, Square target, {int maxLegs = 2}) {
  final piece = pos.pieceAt(from);
  if (piece == null) return null;
  final occupied = pos.p.board.occupied.withoutSquare(from);
  if (dartchessAttacks(piece, from, occupied).has(target)) return [from, target];
  if (piece.role != Role.bishop && piece.role != Role.rook && piece.role != Role.queen) return null;
  final own = pos.p.board.bySide(piece.color).withoutSquare(from);

  final parent = <Square, Square>{from: from};
  var frontier = [from];
  for (var leg = 0; leg < maxLegs && frontier.isNotEmpty; leg++) {
    final next = <Square>[];
    for (final sq in frontier) {
      for (final to in dartchessAttacks(piece, sq, occupied).squares) {
        if (parent.containsKey(to) || own.has(to)) continue;
        if (to != target && occupied.has(to)) continue; // по пути ничего не бьём
        parent[to] = sq;
        if (to == target) {
          final path = [target];
          var cur = target;
          while (cur != from) {
            cur = parent[cur]!;
            path.add(cur);
          }
          return path.reversed.toList();
        }
        next.add(to);
      }
    }
    frontier = next;
  }
  return null;
}
