/// Позиция с API, повторяющим нужные места python-chess.
///
/// Код анализа перенесён из Python построчно, поэтому обёртка даёт те же
/// операции: attackers, is_attacked_by, gives_check, is_pinned, null-ход,
/// счёт легальных ходов с превращениями ×4 и т. д. Ходы — строки UCI, как в
/// данных движка; рокировка записывается обычным e1g1.
library;

import 'package:dartchess/dartchess.dart';

const pieceValues = {
  Role.pawn: 1, Role.knight: 3, Role.bishop: 3, Role.rook: 5, Role.queen: 9, Role.king: 0,
};

const _unicode = {
  'R': '♖', 'N': '♘', 'B': '♗', 'Q': '♕', 'K': '♔', 'P': '♙',
  'r': '♜', 'n': '♞', 'b': '♝', 'q': '♛', 'k': '♚', 'p': '♟',
};

String pieceSymbol(Piece p) => p.color == Side.white ? p.role.letter.toUpperCase() : p.role.letter;

String unicodeSymbol(String symbol) => _unicode[symbol] ?? symbol;

String squareName(Square sq) => sq.name;

class Pos {
  Pos(this.p);

  factory Pos.fromFen(String fen) => Pos(Chess.fromSetup(Setup.parseFen(fen)));

  final Position p;

  Side get turn => p.turn;
  int get fullmoves => p.fullmoves;
  String get fen => p.fen;

  Piece? pieceAt(Square sq) => p.board.pieceAt(sq);
  Role? roleAt(Square sq) => p.board.roleAt(sq);
  Square? king(Side side) => p.board.kingOf(side);

  Iterable<(Square, Piece)> get pieces => p.board.pieces;

  static NormalMove move(String uci) => NormalMove.fromUci(uci);

  bool isLegal(NormalMove m) {
    if (p.board.pieceAt(m.from)?.color != p.turn) return false;
    return p.isLegal(m);
  }

  Pos push(NormalMove m) => Pos(p.playUnchecked(m));

  /// Ход «передать очередь» (python-chess Move.null()).
  Pos nullMove() => Pos((p as Chess).copyWith(
        turn: p.turn.opposite,
        epSquare: null,
        fullmoves: p.turn == Side.black ? p.fullmoves + 1 : p.fullmoves,
      ));

  bool get isCheck => p.isCheck;
  bool get isCheckmate => p.isCheckmate;
  bool get isGameOver => p.isGameOver || p.halfmoves >= 150;

  SquareSet get checkers => p.checkers;

  bool givesCheck(NormalMove m) => push(m).isCheck;

  bool isEnPassant(NormalMove m) {
    final ep = p.epSquare;
    return ep != null &&
        m.to == ep &&
        p.board.pawns.has(m.from) &&
        p.board.bySide(p.turn).has(m.from) &&
        const [7, 9].contains((m.to - m.from).abs()) &&
        !p.board.occupied.has(m.to);
  }

  bool isCapture(NormalMove m) {
    final target = p.board.pieceAt(m.to);
    return (target != null && target.color != p.turn) || isEnPassant(m);
  }

  bool isCastling(NormalMove m) {
    if (!p.board.kings.has(m.from)) return false;
    final diff = m.from.file - m.to.file;
    return diff.abs() > 1 || (p.board.rooks & p.board.bySide(p.turn)).has(m.to);
  }

  bool isKingsideCastling(NormalMove m) => isCastling(m) && m.to.file > m.from.file;

  /// Поля, которые бьёт фигура на sq (python board.attacks).
  SquareSet attacks(Square sq) {
    final piece = p.board.pieceAt(sq);
    if (piece == null) return SquareSet.empty;
    return dartchessAttacks(piece, sq, p.board.occupied);
  }

  SquareSet attackers(Side side, Square sq) => p.board.attacksTo(sq, side);

  bool isAttackedBy(Side side, Square sq) => attackers(side, sq).isNotEmpty;

  /// Абсолютная связка фигуры стороны side на sq (python board.is_pinned).
  bool isPinned(Side side, Square sq) {
    final k = king(side);
    if (k == null) return false;
    final enemy = p.board.bySide(side.opposite);
    final lines = <(SquareSet, SquareSet)>[
      (rookAttacks(k, SquareSet.empty), (p.board.rooks | p.board.queens) & enemy),
      (bishopAttacks(k, SquareSet.empty), (p.board.bishops | p.board.queens) & enemy),
    ];
    final mask = SquareSet.fromSquare(sq);
    for (final (rays, sliders) in lines) {
      if (!rays.has(sq)) continue;
      for (final sniper in (rays & sliders).squares) {
        if (!ray(k, sniper).has(sq)) continue;
        if ((between(sniper, k) & (p.board.occupied | mask)) == mask) return true;
      }
    }
    return false;
  }

  /// Все легальные ходы в UCI, как их перечисляет python-chess
  /// (рокировка e1g1, превращения — четыре хода).
  List<NormalMove> get legalMoves {
    final out = <NormalMove>[];
    p.legalMoves.forEach((from, targets) {
      for (final to in targets.squares) {
        final piece = p.board.pieceAt(from)!;
        var dest = to;
        if (piece.role == Role.king && p.board.bySide(p.turn).has(to)) {
          // dartchess кодирует рокировку ходом на ладью
          dest = Square.fromCoords(to.file > from.file ? File.g : File.c, from.rank);
        }
        if (piece.role == Role.pawn && (to.rank == Rank.first || to.rank == Rank.eighth)) {
          for (final r in [Role.queen, Role.rook, Role.bishop, Role.knight]) {
            out.add(NormalMove(from: from, to: dest, promotion: r));
          }
        } else {
          out.add(NormalMove(from: from, to: dest));
        }
      }
    });
    return out;
  }

  int get legalCount => legalMoves.length;

  String san(NormalMove m) => p.makeSanUnchecked(m).$2;
}

SquareSet dartchessAttacks(Piece piece, Square sq, SquareSet occupied) => attacks(piece, sq, occupied);
