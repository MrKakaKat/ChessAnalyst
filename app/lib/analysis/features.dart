/// Шахматные признаки позиции и хода (chessanalyst/features.py).
library;

import 'package:dartchess/dartchess.dart';

import 'pos.dart';
import 'settings.dart';

const _minorHomes = {
  Side.white: {Square.b1: Role.knight, Square.g1: Role.knight, Square.c1: Role.bishop, Square.f1: Role.bishop},
  Side.black: {Square.b8: Role.knight, Square.g8: Role.knight, Square.c8: Role.bishop, Square.f8: Role.bishop},
};

// --- материал ---

int material(Pos b, Side color) {
  var n = 0;
  for (final (_, piece) in b.pieces) {
    if (piece.color == color) n += pieceValues[piece.role]!;
  }
  return n;
}

int balance(Pos b, Side color) => material(b, color) - material(b, color.opposite);

int nonPawnMaterial(Pos b) {
  var n = 0;
  for (final (_, piece) in b.pieces) {
    if (piece.role != Role.pawn && piece.role != Role.king) n += pieceValues[piece.role]!;
  }
  return n;
}

// --- стадия ---

int undevelopedMinors(Pos b) {
  var n = 0;
  _minorHomes.forEach((color, homes) {
    homes.forEach((sq, role) {
      final p = b.pieceAt(sq);
      if (p != null && p.color == color && p.role == role) n++;
    });
  });
  return n;
}

String stage(Pos b, Settings s) {
  if (nonPawnMaterial(b) <= s.endgameMaterial) return 'endgame';
  if (b.fullmoves <= s.openingMaxMove && undevelopedMinors(b) >= s.openingMinUndeveloped) return 'opening';
  return 'middlegame';
}

// --- форсированность ---

bool _hasMateInOne(Pos b) {
  for (final m in b.legalMoves) {
    if (b.push(m).isCheckmate) return true;
  }
  return false;
}

/// После хода у ходившего появился бы мат в один, если бы ход снова был его.
/// Угроза, которая была и до хода, не считается.
bool createsMateThreat(Pos board, NormalMove move) {
  final b = board.push(move);
  if (b.isCheck || b.isGameOver) return false;
  if (!_hasMateInOne(b.nullMove())) return false;
  return !_hasMateInOne(board);
}

bool isForcing(Pos board, NormalMove move) =>
    board.isCapture(move) || board.givesCheck(move) || createsMateThreat(board, move);

int forcingCount(Pos board, List<String> pv, int window) {
  var b = board;
  var n = 0;
  for (final uci in pv.take(window)) {
    final m = Pos.move(uci);
    if (!b.isLegal(m)) break;
    if (isForcing(b, m)) n++;
    b = b.push(m);
  }
  return n;
}

// --- подтипы positional ---

int kingZonePressure(Pos b, Side color) {
  final k = b.king(color.opposite);
  if (k == null) return 0;
  final zone = kingAttacks(k).withSquare(k);
  return zone.squares.where((sq) => b.isAttackedBy(color, sq)).length;
}

Iterable<(Square, Piece)> ownPieces(Pos b, Side color) =>
    b.pieces.where((e) => e.$2.color == color && e.$2.role != Role.king);

int defendedCount(Pos b, Side color) => ownPieces(b, color).where((e) => b.isAttackedBy(color, e.$1)).length;

int _cheapest(Pos b, SquareSet attackers) {
  var best = 1 << 30;
  for (final a in attackers.squares) {
    final v = pieceValues[b.roleAt(a)]!;
    final val = v == 0 ? 100 : v; // король: python `or 100`
    if (val < best) best = val;
  }
  return best;
}

/// Squares of [color]'s pieces under threat: attacked and undefended, or
/// attacked by a cheaper piece.
Set<Square> threatened(Pos b, Side color) {
  final out = <Square>{};
  for (final (sq, piece) in ownPieces(b, color)) {
    final attackers = b.attackers(color.opposite, sq);
    if (attackers.isEmpty) continue;
    final cheapest = _cheapest(b, attackers);
    if (!b.isAttackedBy(color, sq) || cheapest < pieceValues[piece.role]!) out.add(sq);
  }
  return out;
}

int threatsCount(Pos b, Side color) => threatened(b, color).length;

/// A capture of a piece (not a pawn) that wins material at once: the piece
/// taken is not cheaper than the taker, or it is undefended.
bool obviousCapture(Pos board, NormalMove move) {
  if (!board.isCapture(move) || board.isEnPassant(move)) return false;
  final taken = board.roleAt(move.to);
  final mover = board.roleAt(move.from);
  if (taken == null || mover == null || pieceValues[taken]! < 3) return false;
  final defended = board.isAttackedBy(board.turn.opposite, move.to);
  final moverValue = pieceValues[mover] == 0 ? 100 : pieceValues[mover]!;
  return pieceValues[taken]! >= moverValue || !defended;
}

/// Opponent pieces the move put under threat: a new threat, or one more
/// attacker on a piece now attacked more times than it is defended.
int pressured(Pos board, Pos after, Side me) {
  final before = threatened(board, me.opposite);
  final now = threatened(after, me.opposite);
  var n = 0;
  for (final (sq, _) in ownPieces(after, me.opposite)) {
    final attackers = after.attackers(me, sq).size;
    if (attackers == 0) continue;
    if (now.contains(sq) && !before.contains(sq)) {
      n++;
    } else if (attackers > board.attackers(me, sq).size && attackers > after.attackers(me.opposite, sq).size) {
      n++;
    }
  }
  return n;
}

/// Directions of a move: attack, counterattack, defense (or neutral); see
/// chessanalyst/features.py positional_subtypes.
List<String> positionalSubtypes(Pos board, NormalMove move, Settings s) {
  final me = board.turn;
  final after = board.push(move);
  final capture = board.isCapture(move);
  final newThreats = pressured(board, after, me);
  final attack = after.isCheck ||
      newThreats >= 1 ||
      (!capture && kingZonePressure(after, me) - kingZonePressure(board, me) >= s.attackThreshold);
  final mineBefore = threatsCount(board, me);
  // уход самой фигуры из-под удара — отступление, а не защита
  final othersBefore = threatened(board, me).where((sq) => sq != move.from).length;
  final othersAfter = threatened(after, me).where((sq) => sq != move.to).length;
  final removed = capture ? 0 : othersBefore - othersAfter;
  // защита: атакованной своей фигуре добавлен защитник, а их было не больше,
  // чем нападающих
  var guarded = 0;
  for (final (sq, piece) in ownPieces(board, me)) {
    if (sq == move.from || after.pieceAt(sq) != piece || !board.isAttackedBy(me.opposite, sq)) continue;
    final beforeDef = board.attackers(me, sq).size;
    if (after.attackers(me, sq).size > beforeDef && beforeDef <= board.attackers(me.opposite, sq).size) guarded++;
  }
  final defense = board.isCheck || removed >= s.threatsRemovedThreshold || guarded >= s.defenseThreshold;
  final out = <String>[];
  if (attack) {
    final still = mineBefore > 0 && threatsCount(after, me) > 0 && !board.isCheck;
    out.add(still ? 'counterattack' : 'attack');
  }
  if (defense) out.add('defense');
  return out.isEmpty ? ['neutral'] : out;
}

// --- brilliant ---

bool leavesPieceEnPrise(Pos board, NormalMove move) {
  final me = board.turn;
  var captured = board.pieceAt(move.to);
  if (board.isEnPassant(move)) captured = Piece(color: me.opposite, role: Role.pawn);
  final after = board.push(move);
  final piece = after.pieceAt(move.to);
  if (piece == null || piece.role == Role.pawn || piece.role == Role.king) return false;
  final attackers = after.attackers(me.opposite, move.to);
  if (attackers.isEmpty) return false;
  final value = pieceValues[piece.role]!;
  if (captured != null && pieceValues[captured.role]! < value) return true;
  final cheapest = _cheapest(after, attackers);
  return !after.isAttackedBy(me, move.to) || cheapest < value;
}

bool leavesMaterialEnPrise(Pos board, NormalMove move) {
  if (leavesPieceEnPrise(board, move)) return true;
  if (board.isCheck) return false; // защита от шаха: выбора не было
  final me = board.turn;
  final after = board.push(move);
  for (final (sq, piece) in ownPieces(after, me)) {
    if (piece.role == Role.pawn || sq == move.to) continue;
    final attackers = after.attackers(me.opposite, sq);
    if (attackers.isEmpty) continue;
    if (!after.isAttackedBy(me, sq) || _cheapest(after, attackers) < pieceValues[piece.role]!) return true;
  }
  return false;
}

bool isSacrificeLine(Pos board, List<String> pv, Settings s) {
  final me = board.turn;
  final start = balance(board, me);
  var b = board;
  var checked = 0;
  for (var i = 0; i < pv.length; i++) {
    final m = Pos.move(pv[i]);
    if (!b.isLegal(m)) break;
    b = b.push(m);
    if (i % 2 == 1) {
      if (start - balance(b, me) < s.brilliantMaterial) return false;
      checked++;
      if (checked >= s.brilliantHoldReplies) break;
    }
  }
  return checked > 0;
}
