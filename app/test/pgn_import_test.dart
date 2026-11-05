import 'dart:io';

import 'package:chessanalyst/analysis/pgn_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('imports the Opera game with castling as e1c1 and mate termination', () {
    final g = importPgn(File('../examples/opera_game.pgn').readAsStringSync());
    expect(g.sans.length, 33);
    expect(g.ucis, contains('e1c1'));
    expect(g.headers['termination'], 'mate');
    expect(g.headers['white'], 'Paul Morphy');
  });

  test('bare move list without headers', () {
    final g = importPgn('1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6 4. Qxf7# 1-0');
    expect(g.sans.last, 'Qxf7#');
    expect(g.headers['termination'], 'mate');
  });

  test('garbage is rejected', () {
    expect(() => importPgn('hello'), throwsFormatException);
  });
}
