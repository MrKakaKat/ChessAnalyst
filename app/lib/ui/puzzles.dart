/// Puzzles from analysed games and the history of attempts.
///
/// [авторское] A position becomes a puzzle when one move clearly stands out:
/// - attack: the best move is tactical and the second line is at least a pawn
///   worse (or the best line mates) — goal mate, win or gain an advantage;
/// - defence: everything else loses and only one line holds — an equal or
///   slightly worse position kept, stalemate or perpetual check included
///   (the second line is at least 1.5 pawns worse, the best is not winning).
/// The solution is the engine's main line for as long as the tactic goes on:
/// after the first move the line continues while the solver's moves are
/// forcing (check, capture, promotion) or answer a capture, up to eight moves.
/// Correct moves: in attack puzzles every move that keeps the goal counts —
/// another mate, or a line at least 70% as strong as the best (the
/// "excellent" ratio) that still wins or keeps the advantage; then the
/// puzzle follows that line. The first move's alternatives come from the
/// analysis lines, later ones are checked by the engine while solving.
/// Defence puzzles accept only the line: there is no other way to hold.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:dartchess/dartchess.dart' show NormalMove, Side;
import 'package:shared_preferences/shared_preferences.dart';

import '../analysis/eval.dart';
import '../analysis/game.dart';
import '../analysis/pos.dart';
import '../analysis/settings.dart';
import '../analysis/weakness.dart';

enum PuzzleGoal { mate, win, advantage, defend }

const goalLabels = {
  PuzzleGoal.mate: 'mate',
  PuzzleGoal.win: 'win',
  PuzzleGoal.advantage: 'gain an advantage',
  PuzzleGoal.defend: 'hold the position',
};

class Puzzle {
  const Puzzle({
    required this.id,
    required this.fen,
    required this.solution,
    required this.source,
    required this.gap,
    required this.goal,
    this.value = 0,
    this.alternatives = const [],
    this.prevFen,
    this.prevMove,
    this.tags = const {},
  });

  /// Facts of the puzzle for matching weaknesses (weakness.dart).
  final Set<String> tags;

  /// The position before the opponent's last move, and that move (to look
  /// back at how the puzzle came about).
  final String? prevFen;
  final String? prevMove;

  final String id;
  final String fen;

  /// Moves in UCI: solver, reply, solver, ...
  final List<String> solution;
  final String source;

  /// How much the second line falls behind (pawns): a rough difficulty.
  final double gap;
  final PuzzleGoal goal;

  /// The best line's value for the solver (pawns).
  final double value;

  /// Other solutions from the first position (same rule as [solution]).
  final List<List<String>> alternatives;

  List<List<String>> get solutions => [solution, ...alternatives];

  /// Whether a solver move that left [after] (evaluated for the opponent,
  /// who is to move) keeps the puzzle's goal. In a defence the first move
  /// must be the one that holds; a later move ([step] > 0) counts when it
  /// holds as well: within half a pawn of the solution and not below −1.
  bool keepsGoal(Eval after, {int step = 0}) {
    const s = Settings();
    final mates = after.mate != null && after.mate! < 0;
    final v = -after.pawns(s);
    if (goal == PuzzleGoal.defend) {
      return step > 0 && (mates || (after.mate == null && v >= math.max(-1.0, value - 0.5)));
    }
    if (goal == PuzzleGoal.mate) return mates;
    return mates || v >= math.max(goal == PuzzleGoal.win ? 3.0 : 1.0, s.excellentRatio * value);
  }

  Side get solver => Pos.fromFen(fen).turn;
  int get solverMoves => (solution.length + 1) ~/ 2;
}

List<Puzzle> puzzlesFrom(GameAnalysis a) {
  const s = Settings();
  final out = <Puzzle>[];
  for (final r in a.records) {
    if (r.step == 'book' || r.step == 'forced' || r.bestMoves.isEmpty) continue;
    final p = a.game.plies[r.ply];
    final lines = p.lines;
    if (lines.isEmpty) continue;
    final best = lines.first;
    final value = best.eval.pawns(s);
    final gap = lines.length < 2 ? 9.0 : value - lines[1].eval.pawns(s);
    final mates = best.eval.mate != null && best.eval.mate! > 0;
    final tactical = r.bestMoves.first.type == 'tactical';
    PuzzleGoal? goal;
    if (mates) {
      goal = PuzzleGoal.mate;
    } else if (tactical && gap >= 1.0 && value >= 3.0) {
      goal = PuzzleGoal.win;
    } else if (tactical && gap >= 1.0 && value >= 1.0) {
      goal = PuzzleGoal.advantage;
    } else if (gap >= 1.5 && value > -1.0 && value < 1.0) {
      // единственная защита: остальное проигрывает, лучший ход держит
      goal = PuzzleGoal.defend;
    }
    if (goal == null) continue;
    final start = Pos.fromFen(p.fenBefore);
    final solution = tacticLine(start, best.pv);
    if (solution.isEmpty) continue;
    final draft = Puzzle(id: '', fen: p.fenBefore, solution: solution, source: '', gap: gap, goal: goal, value: value);
    final alternatives = [
      for (final l in lines.skip(1))
        if (goal != PuzzleGoal.defend && draft.keepsGoal(l.eval.negate())) tacticLine(start, l.pv),
    ]..removeWhere((x) => x.isEmpty);
    out.add(Puzzle(
      id: '${a.game.id}:${r.ply}',
      fen: p.fenBefore,
      solution: solution,
      source: '${a.game.title}, move ${r.ply ~/ 2 + 1}',
      gap: gap,
      goal: goal,
      value: value,
      alternatives: alternatives,
      prevFen: r.ply > 0 ? a.game.plies[r.ply - 1].fenBefore : null,
      prevMove: r.ply > 0 ? a.game.plies[r.ply - 1].uci : null,
      tags: puzzleTags(r, start, best, lines: lines),
    ));
  }
  return withoutOverlaps(out);
}

/// Puzzles that share positions: the longest line is kept, and no other
/// puzzle may use any of its positions (the start or a position along the
/// solution, compared without the move counters).
List<Puzzle> withoutOverlaps(List<Puzzle> list) {
  String key(String fen) => fen.split(' ').take(4).join(' ');
  Set<String> positions(Puzzle p) {
    final out = {key(p.fen)};
    var pos = Pos.fromFen(p.fen);
    for (final uci in p.solution) {
      final m = NormalMove.fromUci(uci);
      if (!pos.isLegal(m)) break;
      pos = pos.push(m);
      out.add(key(pos.fen));
    }
    return out;
  }

  final order = [...list]..sort((a, b) => b.solution.length.compareTo(a.solution.length));
  final used = <String>{};
  final kept = <String>{};
  for (final p in order) {
    final ps = positions(p);
    if (ps.any(used.contains)) continue;
    used.addAll(ps);
    kept.add(p.id);
  }
  return [for (final p in list) if (kept.contains(p.id)) p];
}

/// The engine line cut where the tactic ends (see the library comment).
/// Always ends with a solver move.
/// [free]: the first move counts whatever it is; [captured]: the move
/// before [start] was the opponent's capture.
List<String> tacticLine(Pos start, List<String> pv, {bool free = true, bool captured = false}) {
  final out = <String>[];
  var pos = start;
  var replyCaptured = captured;
  for (var i = 0; i < pv.length && out.length < 15; i += 2) {
    final m = NormalMove.fromUci(pv[i]);
    if (!pos.isLegal(m)) break;
    if (i == 0 && !free) {
      final forcing = pos.givesCheck(m) || pos.isCapture(m) || m.promotion != null;
      if (!forcing && !replyCaptured) break;
    }
    if (i > 0) {
      final forcing = pos.givesCheck(m) || pos.isCapture(m) || m.promotion != null;
      // ответ соперника был взятием — отыгрыш тоже часть тактики
      if (!forcing && !replyCaptured) break;
      out.add(pv[i - 1]);
    }
    out.add(m.uci);
    pos = pos.push(m);
    if (i + 1 >= pv.length) break;
    final reply = NormalMove.fromUci(pv[i + 1]);
    if (!pos.isLegal(reply)) break;
    replyCaptured = pos.isCapture(reply);
    pos = pos.push(reply);
  }
  return out;
}

/// The rest of a puzzle after a solver move found by the engine: the reply
/// and the solver's moves while the tactic goes on; empty when it ends there.
List<String> tacticTail(Pos after, List<String> pv) {
  if (pv.length < 2) return [];
  final reply = NormalMove.fromUci(pv.first);
  if (!after.isLegal(reply)) return [];
  final rest = tacticLine(after.push(reply), pv.sublist(1), free: false, captured: after.isCapture(reply));
  return rest.isEmpty ? [] : [pv.first, ...rest];
}

/// Rating guess without the engine (until it has rated the puzzle).
int quickRating(Puzzle p) {
  final pos = Pos.fromFen(p.fen);
  final m = NormalMove.fromUci(p.solution.first);
  final quiet = !pos.isCapture(m) && !pos.givesCheck(m);
  final r = 900 +
      120 * (p.solverMoves - 1) +
      (quiet ? 250 : 0) +
      (p.goal == PuzzleGoal.defend ? 200 : 0) +
      (p.gap < 1.5 ? 150 : 0);
  return r.clamp(400, 3500);
}

/// [авторское] The solver's rating from the recorded attempts, oldest first,
/// as in Elo: start at 1200, after each rated attempt
/// R += K·(result − 1/(1 + 10^((puzzle − R)/400))), K = 40, within 400…3000.
int autoRating(List<PuzzleAttempt> attempts) {
  var r = 1200.0;
  for (final a in attempts.reversed) {
    final p = a.rating;
    if (p == null) continue;
    final expected = 1 / (1 + math.pow(10, (p - r) / 400));
    r = (r + 40 * ((a.solved ? 1 : 0) - expected)).clamp(400, 3000).toDouble();
  }
  return r.round();
}

class PuzzleAttempt {
  const PuzzleAttempt(this.id, this.source, this.solved, this.date,
      {this.rating, this.goal, this.step, this.fen, this.wrong = const []});

  /// The wrong moves of this try, in UCI, with their index in the solution
  /// ("3:e2e4").
  final List<String> wrong;

  int get errors => wrong.length;

  final String id, source;
  final bool solved;
  final DateTime date;
  final int? rating;
  final String? goal;

  /// A miss: the index of the wrong move in the solution, and the position
  /// it was played in (kept on the Positions screen).
  final int? step;
  final String? fen;

  PuzzleAttempt withRating(int r) =>
      PuzzleAttempt(id, source, solved, date, rating: r, goal: goal, step: step, fen: fen, wrong: wrong);

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': source,
        'solved': solved,
        'date': date.toIso8601String(),
        'rating': rating,
        'goal': goal,
        if (step != null) 'step': step,
        if (fen != null) 'fen': fen,
        if (wrong.isNotEmpty) 'wrong': wrong,
      };

  factory PuzzleAttempt.fromJson(Map<String, dynamic> j) => PuzzleAttempt(
        j['id'] as String,
        j['source'] as String,
        j['solved'] as bool,
        DateTime.tryParse(j['date'] as String) ?? DateTime.now(),
        rating: j['rating'] as int?,
        goal: j['goal'] as String?,
        step: j['step'] as int?,
        fen: j['fen'] as String?,
        wrong: (j['wrong'] as List?)?.cast<String>() ?? const [],
      );
}

/// Estimated puzzle ratings, kept between sessions.
class PuzzleRatings {
  static const _key = 'puzzles.ratings';

  /// Version of the rating formula (puzzle_rater.dart): ratings of an older
  /// one are forgotten and the puzzles are rated again.
  static const version = 3;

  static Future<Map<String, int>> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (p.getInt('puzzles.ratingVersion') != version) {
        await p.remove(_key);
        await p.setInt('puzzles.ratingVersion', version);
      }
      final raw = p.getString(_key);
      return raw == null ? {} : (jsonDecode(raw) as Map<String, dynamic>).cast<String, int>();
    } catch (_) {
      return {};
    }
  }

  /// Forgets the ratings of the puzzles of game [gameId].
  static Future<void> removeGame(String gameId) async {
    try {
      final p = await SharedPreferences.getInstance();
      final m = await load()..removeWhere((k, _) => k.startsWith('$gameId:'));
      await p.setString(_key, jsonEncode(m));
    } catch (_) {}
  }

  static Future<void> save(String id, int rating) async {
    try {
      final p = await SharedPreferences.getInstance();
      final m = await load();
      m[id] = rating;
      await p.setString(_key, jsonEncode(m));
    } catch (_) {}
  }
}

/// Attempts the user chose to record (hits and misses, for statistics later).
class PuzzleHistory {
  static const _key = 'puzzles.history';

  static Future<List<PuzzleAttempt>> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      return [
        for (final raw in p.getStringList(_key) ?? <String>[])
          PuzzleAttempt.fromJson(jsonDecode(raw) as Map<String, dynamic>),
      ];
    } catch (_) {
      return [];
    }
  }

  /// Forgets the attempts at the puzzles of game [gameId].
  static Future<void> removeGame(String gameId) async {
    try {
      final p = await SharedPreferences.getInstance();
      final kept = [
        for (final raw in p.getStringList(_key) ?? <String>[])
          if (!((jsonDecode(raw) as Map<String, dynamic>)['id'] as String).startsWith('$gameId:')) raw,
      ];
      await p.setStringList(_key, kept);
    } catch (_) {}
  }

  /// A new engine rating of puzzle [id] (the game was analysed deeper).
  static Future<void> updateRating(String id, int rating) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getStringList(_key) ?? <String>[];
      var changed = false;
      final out = [
        for (final r in raw)
          () {
            final a = PuzzleAttempt.fromJson(jsonDecode(r) as Map<String, dynamic>);
            if (a.id != id || a.rating == rating) return r;
            changed = true;
            return jsonEncode(a.withRating(rating).toJson());
          }(),
      ];
      if (changed) await p.setStringList(_key, out);
    } catch (_) {}
  }

  static Future<void> add(PuzzleAttempt a) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_key, [jsonEncode(a.toJson()), ...?p.getStringList(_key)]);
    } catch (_) {}
  }
}
