import 'package:chessanalyst/analysis/locks.dart';
import 'package:chessanalyst/analysis/pos.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sleeping line: bishop g7 to rook a1 through knight d4 (own lock)', () {
    final b = Pos.fromFen('6k1/6b1/8/8/3n4/8/8/R5K1 b - - 0 1');
    final lines = findLines(b, Side.black);
    final l = lines.firstWhere((l) => l.slider == Square.g7 && l.target == Square.a1);
    expect(l.open, isFalse);
    expect(l.locks.map((x) => x.square), [Square.d4]);
    expect(l.discovered, isTrue); // a knight move opens the line
  });

  test('open line to the king is a direct threat, sorted first', () {
    final b = Pos.fromFen('4k3/8/8/8/n7/8/8/4R1KB b - - 0 1');
    final lines = findLines(b, Side.white);
    expect(lines, isNotEmpty);
    expect(lines.first.targetRole, Role.king);
  });

  test('cheaper defended target is not a line', () {
    // Слон бьёт защищённую пешку — не цель.
    final b = Pos.fromFen('4k3/8/2p5/1p6/8/8/8/4K1B1 w - - 0 1');
    expect(findLines(b, Side.white).where((l) => l.target == Square.c6 || l.target == Square.b5), isEmpty);
  });

  test('timeline: the lock opens when the blocker leaves', () {
    final moves = ['d4f3', 'e1f1', 'f3d2'].map(NormalMove.fromUci).toList();
    final start = Pos.fromFen('6k1/6b1/8/8/3n4/8/8/R3K3 b - - 0 1');
    final before = <Pos>[], after = <Pos>[];
    var p = start;
    for (final m in moves) {
      before.add(p);
      p = p.push(m);
      after.add(p);
    }
    // якорь — позиция после первого хода; линия g7 → a1
    final points = lockTimeline(before, after, moves, 0, Square.g7, Square.a1);
    expect(points.first.state, LineState.open); // после Nf3 линия открыта
    final lineBefore = lineBetween(start, Square.g7, Square.a1)!;
    expect(lineBefore.state, LineState.closed);
  });
}
