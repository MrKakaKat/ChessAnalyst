import 'dart:io';

import 'package:chessanalyst/analysis/openings.dart';
import 'package:chessanalyst/analysis/pos.dart';
import 'package:dartchess/dartchess.dart' show Chess;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('popular continuations from the start: e4 and d4 first', () {
    final book = OpeningBook.parse(File('assets/openings_book.json').readAsStringSync(),
        weights: File('assets/openings_weights.json').readAsStringSync());
    final top = book.continuations(Pos(Chess.initial)).take(2).map((b) => b.san).toSet();
    expect(top, {'e4', 'd4'});
  });

  test('a knight taking on f7 from g5 in a Caro-Kann is the Alien Gambit, in any system', () {
    final book = OpeningBook.parse(File('assets/openings_book.json').readAsStringSync());
    const start = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
    // классическая система: 4...Bf5 5.Ng5 h6 6.Nxf7
    final classical = book.names(start, ['e2e4', 'c7c6', 'd2d4', 'd7d5', 'b1c3', 'd5e4', 'c3e4', 'c8f5', 'e4g5', 'h7h6', 'g5f7']);
    expect(classical.last, OpeningBook.alienGambit);
    // линия книги: 4...Nf6 5.Ng5 h6 6.Nxf7
    final twoKnights = book.names(start, ['e2e4', 'c7c6', 'd2d4', 'd7d5', 'b1c3', 'd5e4', 'c3e4', 'g8f6', 'e4g5', 'h7h6', 'g5f7']);
    expect(twoKnights.last, OpeningBook.alienGambit);
    // не Каро-Канн — не гамбит
    final other = book.names(start, ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4', 'g8f6', 'f3g5', 'd7d5', 'g5f7']);
    expect(other.last, isNot(OpeningBook.alienGambit));
  });
}

