import 'package:chessanalyst/analysis/paths.dart';
import 'package:chessanalyst/analysis/pos.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('direct hit is one leg', () {
    final b = Pos.fromFen('4k3/8/8/8/8/8/8/R3K3 w - - 0 1');
    expect(piecePath(b, Square.a1, Square.a8), [Square.a1, Square.a8]);
  });

  test('bishop reaches a blocked target in two moves', () {
    // Bc8 aims at Nf3: c8 and f3 are not on one diagonal.
    final b = Pos.fromFen('2b1k3/8/8/8/8/5N2/8/4K3 b - - 0 1');
    final path = piecePath(b, Square.c8, Square.f3);
    expect(path!.length, 3);
    expect(path.first, Square.c8);
    expect(path.last, Square.f3);
  });

  test('a knight far from its target gets no arrow', () {
    final b = Pos.fromFen('4k3/3n4/8/8/8/2N5/8/4K3 b - - 0 1');
    expect(piecePath(b, Square.d7, Square.c3), isNull);
  });
}
