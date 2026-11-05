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
}
