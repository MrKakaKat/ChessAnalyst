/// Puzzles from the Lichess puzzle database (CC0), the ones rated in the
/// calibration runs (tools/lichess): a stratified sample, 600…2600 on
/// Lichess, each with the engine rating our rater gave it. Their rating in
/// the app is ours: the engine rating through the Lichess calibration
/// (puzzle_rater.dart), about 350 below the Lichess one.
library;

import 'package:flutter/services.dart' show rootBundle;

import '../analysis/pos.dart';
import '../engine/puzzle_rater.dart' show calibrated;
import 'puzzles.dart';

const lichessAsset = 'assets/lichess_puzzles.csv';

/// A Lichess puzzle in our form: the position after the opponent's first
/// move, the rest of the moves as the solution; the goal from its themes.
Puzzle fromLichess(String id, String fen, List<String> moves, Set<String> themes, double value, {int? lichessRating}) {
  final start = Pos.fromFen(fen).push(Pos.move(moves.first));
  final goal = themes.any((t) => t == 'mate' || t.startsWith('mateIn'))
      ? PuzzleGoal.mate
      : (themes.contains('defensiveMove') || themes.contains('equality'))
          ? PuzzleGoal.defend
          : (themes.contains('crushing') ? PuzzleGoal.win : PuzzleGoal.advantage);
  return Puzzle(
    id: 'lichess:$id',
    fen: start.fen,
    solution: moves.sublist(1),
    source: lichessRating == null ? 'Lichess $id' : 'Lichess $id · $lichessRating on Lichess',
    gap: 2,
    goal: goal,
    value: value,
    tags: themes,
    prevFen: fen,
    prevMove: moves.first,
  );
}

/// The packed Lichess puzzles with our ratings (id → rating).
Future<(List<Puzzle>, Map<String, int>)> loadLichessPuzzles() async {
  final puzzles = <Puzzle>[];
  final ratings = <String, int>{};
  try {
    final rows = (await rootBundle.loadString(lichessAsset)).split('\n');
    // id,fen,moves,lichess,raw,themes
    for (final line in rows.skip(1)) {
      final r = line.split(',');
      if (r.length < 6) continue;
      final p = fromLichess(r[0], r[1], r[2].split(' '), r[5].split(' ').toSet(), 0,
          lichessRating: int.parse(r[3]));
      puzzles.add(p);
      ratings[p.id] = calibrated(int.parse(r[4]), p).clamp(400, 3000).toInt();
    }
  } catch (_) {}
  return (puzzles, ratings);
}
