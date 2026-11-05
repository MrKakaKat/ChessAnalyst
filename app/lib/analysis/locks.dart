/// Lines and locks (logic taken from the earlier Idea Chain project, BUILD.md).
///
/// A *line* is a slider (bishop, rook, queen) aimed along its ray at a target:
/// the enemy king, an enemy piece worth more than the slider, or an undefended
/// enemy piece. The pieces standing between them are *locks*:
///   * no locks      — the line is open: a direct threat;
///   * 1–2 locks     — the line is sleeping (closed);
///   * a lock of the slider's own side can open with a discovered attack,
///     a lock of the defending side is a pinned or shielding piece.
/// Over the game a line is followed move by move: its locks close and open,
/// and the move that opens the last lock is where the line fires.
library;

import 'package:dartchess/dartchess.dart';

import 'pos.dart';

const maxLocks = 2;

enum LineState { closed, open, none }

class Lock {
  const Lock(this.square, this.side);

  final Square square;
  final Side side;
}

class LineOfAttack {
  const LineOfAttack({
    required this.slider,
    required this.sliderRole,
    required this.side,
    required this.target,
    required this.targetRole,
    required this.locks,
  });

  final Square slider;
  final Role sliderRole;
  final Side side;
  final Square target;
  final Role targetRole;
  final List<Lock> locks;

  bool get open => locks.isEmpty;
  LineState get state => open ? LineState.open : LineState.closed;

  /// Locks of the attacking side: moving one away fires a discovered attack.
  bool get discovered => locks.any((l) => l.side == side);
}

const _rookDirs = [(1, 0), (-1, 0), (0, 1), (0, -1)];
const _bishopDirs = [(1, 1), (1, -1), (-1, 1), (-1, -1)];

List<(int, int)> _dirs(Role r) => switch (r) {
      Role.rook => _rookDirs,
      Role.bishop => _bishopDirs,
      Role.queen => [..._rookDirs, ..._bishopDirs],
      _ => const [],
    };

bool _isTarget(Pos b, Square sq, Piece target, Role sliderRole) {
  if (target.role == Role.king) return true;
  if (pieceValues[target.role]! > pieceValues[sliderRole]!) return true;
  return !b.isAttackedBy(target.color, sq);
}

/// All lines of [side] in the position: open threats and sleeping lines.
List<LineOfAttack> findLines(Pos b, Side side) {
  final out = <LineOfAttack>[];
  for (final (sq, piece) in b.pieces) {
    if (piece.color != side) continue;
    for (final (df, dr) in _dirs(piece.role)) {
      final locks = <Lock>[];
      var f = sq.file + df, r = sq.rank + dr;
      while (f >= 0 && f < 8 && r >= 0 && r < 8) {
        final at = Square.fromCoords(File(f), Rank(r));
        final p = b.pieceAt(at);
        if (p != null) {
          if (p.color != side && _isTarget(b, at, p, piece.role)) {
            out.add(LineOfAttack(
                slider: sq, sliderRole: piece.role, side: side, target: at, targetRole: p.role, locks: [...locks]));
            break;
          }
          locks.add(Lock(at, p.color));
          if (locks.length > maxLocks) break;
        }
        f += df;
        r += dr;
      }
    }
  }
  out.sort((a, b) {
    final k = (a.targetRole == Role.king ? 0 : 1).compareTo(b.targetRole == Role.king ? 0 : 1);
    if (k != 0) return k;
    return a.locks.length.compareTo(b.locks.length);
  });
  return out;
}

/// The line from [slider] to [target] in position [b], if they are still aligned.
LineOfAttack? lineBetween(Pos b, Square slider, Square target) {
  final piece = b.pieceAt(slider);
  final victim = b.pieceAt(target);
  if (piece == null || victim == null || piece.color == victim.color) return null;
  final df = (target.file - slider.file).sign, dr = (target.rank - slider.rank).sign;
  final straight = target.file == slider.file || target.rank == slider.rank;
  final diagonal = (target.file - slider.file).abs() == (target.rank - slider.rank).abs();
  if (!(straight || diagonal)) return null;
  if (!_dirs(piece.role).contains((df, dr))) return null;
  final locks = <Lock>[];
  var f = slider.file + df, r = slider.rank + dr;
  while (f != target.file || r != target.rank) {
    final at = Square.fromCoords(File(f), Rank(r));
    final p = b.pieceAt(at);
    if (p != null) locks.add(Lock(at, p.color));
    f += df;
    r += dr;
  }
  if (locks.length > maxLocks) return null;
  return LineOfAttack(
      slider: slider, sliderRole: piece.role, side: piece.color, target: target, targetRole: victim.role, locks: locks);
}

class LockPoint {
  const LockPoint(this.ply, this.state, this.line);

  final int ply;
  final LineState state;
  final LineOfAttack? line;
}

Square? _forward(Pos b, NormalMove m, Square? sq) {
  if (sq == null) return null;
  if (m.from == sq) return m.to;
  if (b.isCastling(m)) {
    final rank = m.from.rank;
    final ks = b.isKingsideCastling(m);
    final from = Square.fromCoords(ks ? File.h : File.a, rank);
    if (from == sq) return Square.fromCoords(ks ? File.f : File.d, rank);
  }
  if (m.to == sq) return null;
  return sq;
}

Square? _backward(Pos before, NormalMove m, Square? sq) {
  if (sq == null) return null;
  if (m.to == sq) return m.from;
  if (before.isCastling(m)) {
    final rank = m.from.rank;
    final ks = before.isKingsideCastling(m);
    if (Square.fromCoords(ks ? File.f : File.d, rank) == sq) return Square.fromCoords(ks ? File.h : File.a, rank);
  }
  return sq;
}

/// Follows a line through the game. [after] holds the position after each ply,
/// [before] the position before it, [moves] the played moves. The line is
/// anchored at [anchor] (position after that ply) and followed [span] plies
/// both ways; each point is the lock state after that ply.
List<LockPoint> lockTimeline(List<Pos> before, List<Pos> after, List<NormalMove> moves, int anchor,
    Square slider, Square target, {int span = 8}) {
  final points = <int, LockPoint>{};
  // назад от якоря
  Square? s = slider, t = target;
  for (var ply = anchor; ply >= 0 && ply >= anchor - span; ply--) {
    final line = (s != null && t != null) ? lineBetween(after[ply], s, t) : null;
    points[ply] = LockPoint(ply, line?.state ?? LineState.none, line);
    s = _backward(before[ply], moves[ply], s);
    t = _backward(before[ply], moves[ply], t);
  }
  // вперёд от якоря
  s = slider;
  t = target;
  for (var ply = anchor + 1; ply < after.length && ply <= anchor + span; ply++) {
    s = _forward(before[ply], moves[ply], s);
    t = _forward(before[ply], moves[ply], t);
    final line = (s != null && t != null) ? lineBetween(after[ply], s, t) : null;
    points[ply] = LockPoint(ply, line?.state ?? LineState.none, line);
  }
  return [for (final k in points.keys.toList()..sort()) points[k]!];
}
