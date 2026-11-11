import 'package:chessanalyst/analysis/difficulty.dart';
import 'package:chessanalyst/analysis/eval.dart';
import 'package:chessanalyst/analysis/kinds.dart';
import 'package:chessanalyst/analysis/pos.dart';
import 'package:chessanalyst/analysis/settings.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> kinds(String fen, List<String> pv, {int cp = 0}) => kindsOf(
    Pos.fromFen(fen), Pos.move(pv.first), pv, Eval(cp: cp, wdl: (0, 1000, 0)), const Settings());

void main() {
  test('a fork right now is positional; one after forcing moves is tactical', () {
    // 1.Rd8+ Kxd8 2.Nc6+ — вилка королю и ферзю после жертвы ладьи
    const fen = '4k3/8/8/q3N3/8/8/8/3R2K1 w - - 0 1';
    final first = kinds(fen, ['d1d8', 'e8d8', 'e5c6']);
    expect(first, contains('fork_tactical'));
    expect(first, isNot(contains('fork')));
    // сама 2.Nc6+ — позиционная вилка
    const fen2 = '3k4/8/8/q3N3/8/8/8/6K1 w - - 0 1';
    final second = kinds(fen2, ['e5c6']);
    expect(second, contains('fork'));
    expect(second, isNot(contains('fork_tactical')));
    // тихий ход без форсирования — не тактическая вилка
    expect(kinds(fen, ['g1h2', 'a5b5', 'e5c6']), isNot(contains('fork_tactical')));
  });

  test('a piece that takes the king its escape square', () {
    // Bc4 отнимает у короля h8 поле g8
    expect(kinds('7k/6pp/8/8/8/8/8/4KB2 w - - 0 1', ['f1c4']), contains('block_escape'));
    // слон в другую сторону — поле свободно
    expect(kinds('7k/6pp/8/8/8/8/8/4KB2 w - - 0 1', ['f1e2']), isNot(contains('block_escape')));
  });

  test('in the endgame a king that does not let the other king pass', () {
    expect(kinds('8/8/8/4k3/8/8/4K3/8 w - - 0 1', ['e2e3']), contains('block_escape'));
    // король уходит — ничего не отнимает
    expect(kinds('8/8/8/4k3/8/8/4K3/8 w - - 0 1', ['e2e1']), isNot(contains('block_escape')));
  });

  test('the puzzle threshold is checked after the key move', () {
    Line l(String m, int cp, List<String> pv) => Line(move: m, eval: Eval(cp: cp, wdl: (0, 1000, 0)), pv: pv);
    const fen = '4k3/8/8/8/8/8/8/4K3 w - - 0 1';
    final lines = [l('a', 500, ['a', 'b', 'c']), l('x', 0, ['x'])];
    // после ключевого хода путь широкий — +5 остаётся выше +3
    final easy = PlyScan(10, {0: [null, null, [300, 290, 280]]});
    expect(practicalAfterKey(fen, lines, easy), greaterThanOrEqualTo(winBoundary));
    // а сама позиция трудная — первый ход единственный
    expect(positionDifficulty(fen, lines, easy).mover, greaterThan(0));
  });
}
