/// Kinds of moves: what a move does on the board (docs/analysis_guide.md,
/// "Kinds of moves"). Used for the move played and for the best move a weak
/// move missed: a mistake is described by what the player did not see.
///
/// [простое решение] Each kind is a rule on the position before the move, the
/// position after it and the engine line that follows; a move can have
/// several kinds, the first is the main one:
/// - mate, promotion;
/// - fork: the moved piece attacks two pieces worth a knight or more (or the
///   king and such a piece);
/// - pin: after the move a piece of the opponent is pinned that was not;
/// - sacrifice: the moved piece can be taken and the line keeps the material
///   down for a while (as for brilliant);
/// - tempo attack: the moved piece attacks a piece worth more than itself, or
///   an undefended one;
/// - exchange: an equal capture of a defended piece; barter: an unequal one
///   (pieces of different value, not pawns); simplification: an exchange or
///   barter when winning (+3);
/// - pawn break: a pawn moves into contact with an enemy pawn;
///   undermining: such a pawn attacks an enemy pawn defended by a pawn (the
///   chain);
/// - pawn push: any other pawn move forward; in the opening and the
///   middlegame split into a centre push (files c–f) and a flank push
///   (a, b, g, h); in the endgame the difference is small;
/// - overload: after the move an enemy piece is the only defender of two
///   attacked pieces (taking one loses the other), or the move takes a
///   piece whose only defender also guards another attacked piece;
/// - exchange offer / barter offer: a quiet move that puts the piece face to
///   face with an enemy piece (each attacks the other, the enemy one is not a
///   pawn), the moved piece defended — equal pieces offer an exchange,
///   different ones a barter;
/// - free material: a capture of a piece no one defends;
/// - discovered attack: the move uncovers a line of another own piece (a
///   bishop, rook or queen) onto an enemy piece it did not attack — on the
///   king (discovered check), on the queen, or on another piece (not a
///   pawn);
/// - escape from check: the move gets out of check (taking the checking
///   piece, moving the king, or blocking the line);
/// - retreat: a quiet move of a piece that could be taken for free (attacked
///   and undefended, or attacked by a cheaper piece) to a square where it is
///   safe — it steps away from the attack instead of defending;
/// - choice of trade: the move trades (exchange or barter), two or more
///   trades are possible, and every other trade loses at least half a pawn
///   against it (needs the lines of the position);
/// - wrong piece: (for a played move only) the best move took on the same
///   square with another piece;
/// - development: a knight or bishop leaves its first square in the opening;
///   king safety: castling;
/// - open file: a rook or queen goes to a file without own pawns;
/// - outpost: a knight to the opponent's half, defended by a pawn, where no
///   enemy pawn can attack it;
/// - reroute: the same piece moves again within the next two own moves of
///   the line (a manoeuvre);
/// - poisoned: (for a played move only) a capture where the best move was not
///   one, and the capture lost.
/// Every kind carries the stage of the game.
library;

import 'package:dartchess/dartchess.dart';

import 'eval.dart';
import 'features.dart' as features;
import 'pos.dart';
import 'settings.dart';

const kindLabels = {
  'mate': 'Mate',
  'promotion': 'Promotion',
  'fork': 'Fork',
  'pin': 'Pin',
  'sacrifice': 'Sacrifice',
  'tempo': 'Tempo attack',
  'simplification': 'Simplification',
  'barter': 'Barter',
  'exchange': 'Exchange',
  'break': 'Pawn break',
  'undermining': 'Undermining',
  'push': 'Pawn push',
  'push_center': 'Centre pawn push',
  'push_flank': 'Flank pawn push',
  'overload': 'Overloaded piece',
  'offer_exchange': 'Exchange offer',
  'offer_barter': 'Barter offer',
  'free': 'Free material',
  'retreat': 'Retreat from attack',
  'missed_again': 'Missed again',
  'discovered_check': 'Discovered check',
  'discovered_queen': 'Discovered attack on the queen',
  'discovered_attack': 'Discovered attack',
  'check_escape': 'Escape from check',
  'trade_choice': 'Choice of trade',
  'wrong_piece': 'Wrong piece',
  'development': 'Development',
  'king_safety': 'King safety',
  'open_file': 'Open file',
  'outpost': 'Outpost',
  'reroute': 'Reroute',
  'poisoned': 'Poisoned material',
  'capture': 'Capture',
  'check': 'Check',
  'quiet': 'Quiet move',
};

int _value(Role r) => switch (r) {
      Role.pawn => 1,
      Role.knight || Role.bishop => 3,
      Role.rook => 5,
      Role.queen => 9,
      Role.king => 100,
    };

/// Kinds of [move] in [board] with the engine line [pv] (starting with the
/// move) and its evaluation [eval] (side to move).
List<String> kindsOf(Pos board, NormalMove move, List<String> pv, Eval eval, Settings s, {List<Line>? lines}) {
  final me = board.turn;
  final piece = board.pieceAt(move.from);
  if (piece == null) return const [];
  final after = board.push(move);
  final out = <String>[];
  final capture = board.isCapture(move);
  final taken = capture ? (board.roleAt(move.to) ?? Role.pawn) : null;

  if (after.p.isCheckmate) out.add('mate');
  if (move.promotion != null) out.add('promotion');

  // вилка: сходившая фигура бьёт две ценные фигуры (или короля и ценную)
  final targets = after.attacks(move.to).squares.where((sq) {
    final p = after.pieceAt(sq);
    return p != null && p.color != me && (p.role == Role.king || _value(p.role) >= 3);
  }).length;
  if (targets >= 2 && piece.role != Role.king) out.add('fork');

  // связка: связанная фигура соперника, которой раньше не было
  for (final (sq, p) in after.pieces) {
    if (p.color == me || p.role == Role.king) continue;
    if (after.isPinned(me.opposite, sq) && !board.isPinned(me.opposite, sq)) {
      out.add('pin');
      break;
    }
  }

  // вскрытое нападение: ход открывает линию другой своей фигуры
  if (_discovered(board, after, move, me) case final d?) out.add(d);

  // выход из-под шаха: взятие, уход короля или перекрытие
  if (board.isCheck) out.add('check_escape');

  if (_overload(board, after, move, me)) out.add('overload');

  if (features.leavesMaterialEnPrise(board, move) && features.isSacrificeLine(board, pv, s)) out.add('sacrifice');

  // нападение с темпом: на фигуру дороже себя или незащищённую
  if (!capture && piece.role != Role.king) {
    for (final sq in after.attacks(move.to).squares) {
      final p = after.pieceAt(sq);
      if (p == null || p.color == me || p.role == Role.king) continue;
      if (_value(p.role) > _value(piece.role) || !after.isAttackedBy(me.opposite, sq)) {
        out.add('tempo');
        break;
      }
    }
  }

  // отступление: фигура уходит из-под взятия на безопасное поле
  if (!capture &&
      piece.role != Role.king &&
      features.threatened(board, me).contains(move.from) &&
      !features.threatened(after, me).contains(move.to)) {
    out.add('retreat');
  }

  // свободный материал: взятие фигуры, которую никто не защищает
  if (capture && taken != null && !board.isAttackedBy(me.opposite, move.to)) out.add('free');

  // размены
  if (_isTrade(board, move)) {
    if (lines != null && _tradeChoice(board, move, lines, s)) out.add('trade_choice');
    final trade = _value(taken!) == _value(piece.role) ? 'exchange' : 'barter';
    out.add(eval.pawns(s) >= 3 ? 'simplification' : trade);
  }

  // предложение размена или обмена: фигуры встают друг против друга
  if (!capture && piece.role != Role.king && piece.role != Role.pawn && after.isAttackedBy(me, move.to)) {
    for (final sq in after.attacks(move.to).squares) {
      final p = after.pieceAt(sq);
      if (p == null || p.color == me || p.role == Role.king || p.role == Role.pawn) continue;
      if (!after.attacks(sq).has(move.to)) continue;
      out.add(_value(p.role) == _value(piece.role) ? 'offer_exchange' : 'offer_barter');
      break;
    }
  }

  if (piece.role == Role.pawn && !capture) {
    // прорыв: пешка входит в контакт с пешкой соперника
    final contact = after.attacks(move.to).squares.where((sq) {
      final p = after.pieceAt(sq);
      return p != null && p.color != me && p.role == Role.pawn;
    }).toList();
    final blocked = after.attackers(me.opposite, move.to).squares.any((sq) => after.roleAt(sq) == Role.pawn);
    if (contact.isNotEmpty || blocked) {
      final chain = contact.any((sq) => after.attackers(me.opposite, sq).squares.any((d) => after.roleAt(d) == Role.pawn));
      out.add(chain ? 'undermining' : 'break');
    } else if (features.stage(board, s) == 'endgame') {
      out.add('push');
    } else {
      // в дебюте и миттельшпиле центр (c–f) и фланги различаются
      out.add(move.to.file >= 2 && move.to.file <= 5 ? 'push_center' : 'push_flank');
    }
  }

  final rank1 = me == Side.white ? Rank.first : Rank.eighth;
  if ((piece.role == Role.knight || piece.role == Role.bishop) &&
      move.from.rank == rank1 &&
      features.stage(board, s) == 'opening') {
    out.add('development');
  }
  if (board.isCastling(move)) out.add('king_safety');

  if (piece.role == Role.rook || piece.role == Role.queen) {
    final file = move.to.file;
    final ownPawn = List.generate(8, (r) => Square.fromCoords(file, Rank(r)))
        .any((sq) => after.pieceAt(sq) == Piece(color: me, role: Role.pawn));
    if (!ownPawn && file != move.from.file) out.add('open_file');
  }

  if (piece.role == Role.knight) {
    final enemyHalf = me == Side.white ? move.to.rank >= Rank.fifth : move.to.rank <= Rank.fourth;
    final pawnDefended = after.attackers(me, move.to).squares.any((sq) => after.roleAt(sq) == Role.pawn);
    // пешки соперника на соседних вертикалях впереди поля коня
    final ahead = [
      for (final df in [-1, 1])
        if (move.to.file + df >= 0 && move.to.file + df < 8)
          for (var r = 0; r < 8; r++)
            if (me == Side.white ? r > move.to.rank : r < move.to.rank) Square.fromCoords(File(move.to.file + df), Rank(r)),
    ];
    final chased = ahead.any((sq) => after.pieceAt(sq) == Piece(color: me.opposite, role: Role.pawn));
    if (enemyHalf && pawnDefended && !chased) out.add('outpost');
  }

  // перевод фигуры: та же фигура снова ходит в ближайших двух своих ходах линии
  var b = after;
  var at = move.to;
  for (var i = 1; i < pv.length && i <= 4; i++) {
    final m = NormalMove.fromUci(pv[i]);
    if (!b.isLegal(m)) break;
    if (i.isEven && m.from == at && !b.isCapture(m) && piece.role != Role.pawn) {
      out.add('reroute');
      break;
    }
    b = b.push(m);
  }

  if (out.isEmpty) {
    out.add(capture ? 'capture' : (after.isCheck ? 'check' : 'quiet'));
  }
  return out;
}

/// Kinds of a played move that went wrong: as [kindsOf], plus "poisoned"
/// when it took material and the best move did not, and "wrong piece" when
/// the best move took on the same square with another piece.
List<String> playedKinds(Pos board, NormalMove move, List<String> pv, Eval eval, NormalMove best, Settings s) {
  final out = kindsOf(board, move, pv, eval, s);
  if (board.isCapture(move) && board.isCapture(best) && move.to == best.to && move.from != best.from) {
    return ['wrong_piece', ...out.where((k) => k != 'capture')];
  }
  // отравленное взятие — не свободный материал, даже если фигура не защищена
  if (board.isCapture(move) && !board.isCapture(best)) {
    return ['poisoned', ...out.where((k) => k != 'capture' && k != 'free')];
  }
  return out;
}

/// The strongest target newly attacked by a line the move opened: 'king',
/// 'queen' or another piece (not a pawn), as a kind; null when none.
String? _discovered(Pos board, Pos after, NormalMove move, Side me) {
  var best = 0;
  for (final (sq, p) in after.pieces) {
    if (p.color != me || sq == move.to) continue;
    if (p.role != Role.bishop && p.role != Role.rook && p.role != Role.queen) continue;
    final was = board.attacks(sq);
    for (final t in after.attacks(sq).squares) {
      if (was.has(t)) continue;
      final target = after.pieceAt(t);
      if (target == null || target.color == me || target.role == Role.pawn) continue;
      final rank = switch (target.role) { Role.king => 3, Role.queen => 2, _ => 1 };
      if (rank > best) best = rank;
    }
  }
  return switch (best) { 3 => 'discovered_check', 2 => 'discovered_queen', 1 => 'discovered_attack', _ => null };
}

/// A trade: a piece (not a pawn or the king) takes a defended piece that is
/// not a pawn.
bool _isTrade(Pos board, NormalMove m) {
  if (!board.isCapture(m)) return false;
  final piece = board.roleAt(m.from), taken = board.roleAt(m.to);
  if (piece == null || taken == null || piece == Role.pawn || piece == Role.king || taken == Role.pawn) return false;
  return board.isAttackedBy(board.turn.opposite, m.to);
}

/// [авторское] Choice of trade: there are two or more trades, and each other
/// one loses half a pawn or more against [move] (a trade the lines do not
/// hold counts as worse).
bool _tradeChoice(Pos board, NormalMove move, List<Line> lines, Settings s) {
  final others = [for (final m in board.legalMoves) if (m != move && _isTrade(board, m)) m];
  if (others.isEmpty) return false;
  final byMove = {for (final l in lines) l.move: l};
  final mine = byMove[move.uci];
  if (mine == null) return false;
  final v = mine.eval.pawns(s);
  return others.every((m) {
    final l = byMove[m.uci];
    return l == null || v - l.eval.pawns(s) >= 0.5;
  });
}

/// [авторское] Overload: a defender of the opponent with two duties — the
/// only defender of two pieces attacked by [me] after the move (and fewer
/// before it), or the move takes a piece whose only defender also guards
/// another attacked piece.
bool _overload(Pos board, Pos after, NormalMove move, Side me) {
  int duties(Pos b, Square d, {Square? skip}) {
    var n = 0;
    for (final (sq, p) in b.pieces) {
      if (p.color == me || p.role == Role.king || sq == d || sq == skip) continue;
      if (!b.isAttackedBy(me, sq)) continue;
      final defenders = b.attackers(me.opposite, sq);
      if (defenders.size == 1 && defenders.has(d)) n++;
    }
    return n;
  }

  for (final (d, p) in after.pieces) {
    if (p.color == me || p.role == Role.king) continue;
    if (duties(after, d) >= 2 && (board.pieceAt(d) != p || duties(board, d) < 2)) return true;
  }
  if (board.isCapture(move)) {
    final defenders = board.attackers(me.opposite, move.to);
    if (defenders.size == 1) {
      final d = defenders.squares.first;
      // после взятия: тот же защитник ещё один держит атакованную фигуру
      if (board.roleAt(d) != Role.king && duties(after, d, skip: move.to) >= 1) return true;
    }
  }
  return false;
}
