import 'package:chessanalyst/analysis/pos.dart';
import 'package:chessanalyst/ui/lichess_puzzles.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('the packed Lichess puzzles load, play and are rated on our scale', () async {
    final (puzzles, ratings) = await loadLichessPuzzles();
    expect(puzzles.length, 3000);
    expect(ratings.length, 3000);
    var lichess = 0, ours = 0;
    for (final p in puzzles) {
      // ход соперника и решение — легальны
      var pos = Pos.fromFen(p.prevFen!);
      for (final uci in [p.prevMove!, ...p.solution]) {
        final m = NormalMove.fromUci(uci);
        expect(pos.isLegal(m), isTrue, reason: p.id);
        pos = pos.push(m);
      }
      final r = ratings[p.id]!;
      expect(r, inInclusiveRange(400, 3000));
      lichess += int.parse(RegExp(r'· (\d+) on Lichess').firstMatch(p.source)!.group(1)!);
      ours += r;
    }
    // наша шкала — примерно на 350 ниже Lichess
    final shift = (lichess - ours) / puzzles.length;
    expect(shift, inInclusiveRange(250, 450));
  });
}
