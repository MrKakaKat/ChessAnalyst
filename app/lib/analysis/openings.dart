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
  List<String?> names(String startFen, List<String> ucis) {
    var b = Pos.fromFen(startFen);
    if (b.fen != Chess.initial.fen) return List.filled(ucis.length, null);
    final out = <String?>[];
    var inBook = true;
    var name = '';
    for (final uci in ucis) {
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
