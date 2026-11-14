/// Opening book (chessanalyst/openings.py): EPD -> opening name, from the Lichess
/// opening tables. A move is a book move while every earlier move was one and
/// the position after it is in the book.
library;

import 'dart:convert';

import 'package:dartchess/dartchess.dart';

import 'pos.dart';

class OpeningBook {
  OpeningBook(this.positions, [this.weights = const {}]);

  factory OpeningBook.parse(String source, {String? weights}) => OpeningBook(
        (jsonDecode(source) as Map<String, dynamic>).cast<String, String>(),
        weights == null ? const {} : (jsonDecode(weights) as Map<String, dynamic>).cast<String, int>(),
      );

  static final empty = OpeningBook(const {});

  final Map<String, String> positions;

  /// EPD -> number of named book lines through the position (popularity
  /// stand-in: the tables have no game counts).
  final Map<String, int> weights;

  static String epd(Pos b) => b.fen.split(' ').take(4).join(' ');

  /// For each ply: the opening name if the move is a book move, else null.
  static const alienGambit = 'Caro-Kann Defense: Alien Gambit';

  /// White's knight from g5 takes on f7 early in a Caro-Kann.
  static bool isAlienGambit(Pos b, String uci, String name, int ply) {
    if (ply >= 20 || !name.contains('Caro-Kann') || uci != 'g5f7') return false;
    final piece = b.pieceAt(Square.g5), target = b.pieceAt(Square.f7);
    return piece == const Piece(color: Side.white, role: Role.knight) && target != null && target.color == Side.black;
  }

  List<String?> names(String startFen, List<String> ucis) {
    var b = Pos.fromFen(startFen);
    if (b.fen != Chess.initial.fen) return List.filled(ucis.length, null);
    final out = <String?>[];
    var inBook = true;
    var name = '';
    for (final (i, uci) in ucis.indexed) {
      // [авторское] Alien Gambit: жертва коня Ng5xf7 в Каро-Канн — в любой
      // системе (книга знает её только после 4...Nf6)
      if (isAlienGambit(b, uci, name, i)) {
        b = b.push(Pos.move(uci));
        name = alienGambit;
        out.add(name);
        inBook = false;
        continue;
      }
      b = b.push(Pos.move(uci));
      final key = epd(b);
      final hit = positions[key];
      if (inBook && hit != null) {
        if (hit.isNotEmpty) name = hit;
        out.add(name);
      } else {
        inBook = false;
        out.add(null);
      }
    }
    return out;
  }

  /// Book moves from [b], most popular first (by [weights]).
  List<BookMove> continuations(Pos b, {int limit = 4}) {
    final out = <BookMove>[];
    for (final m in b.legalMoves) {
      if (m.promotion != null) continue;
      final key = epd(b.push(m));
      final name = positions[key];
      if (name == null) continue;
      out.add(BookMove(m.uci, b.san(m), name, weights[key] ?? 0));
    }
    out.sort((x, y) => y.weight != x.weight ? y.weight.compareTo(x.weight) : x.san.compareTo(y.san));
    return out.take(limit).toList();
  }
}

class BookMove {
  const BookMove(this.uci, this.san, this.name, this.weight);

  final String uci;
  final String san;
  final String name;
  final int weight;
}
