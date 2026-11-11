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
/// another mate, a crushing line (+5) in a mate puzzle, or a line at least
/// 60% as strong as the best that still wins or keeps the advantage; then the
/// puzzle follows that line. The first move's alternatives come from the
/// analysis lines, the others are checked by the engine while solving (a
/// deeper search often finds a second good move the analysis did not rank).
/// In a defence another move counts when the engine finds that it holds as
/// well: within 0.3 pawn of the solution on the first move, 0.5 later.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:dartchess/dartchess.dart' show NormalMove, Side;
import 'package:shared_preferences/shared_preferences.dart';

import '../analysis/character.dart' show Sharpness, characterOf;
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
    this.minValue,
    this.goal2,
    this.value2 = 0,
    this.switchAt,
  });

  /// The least value that still counts as the goal in an advantage puzzle
  /// (+3, or +2 early in the game in a calm position); null: by the goal.
  final double? minValue;

  /// A combined puzzle: from solution index [switchAt] (a solver move) the
  /// goal becomes [goal2] with the best value [value2] — for example, win
  /// material, then hold against the counterattack.
  final PuzzleGoal? goal2;
  final double value2;
  final int? switchAt;

  bool get combined => goal2 != null && switchAt != null;

  PuzzleGoal goalAt(int step) => combined && step >= switchAt! ? goal2! : goal;
  double valueAt(int step) => combined && step >= switchAt! ? value2 : value;

  /// Whether the puzzle has a defensive part.
  bool get defends => goal == PuzzleGoal.defend || goal2 == PuzzleGoal.defend;

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
  /// who is to move) keeps the puzzle's goal. In a defence another move
  /// counts when it holds as well: not below −1 and within 0.3 pawn of the
  /// solution on the first move ([step] 0), 0.5 later.
  bool keepsGoal(Eval after, {int step = 0}) {
    const s = Settings();
    final mates = after.mate != null && after.mate! < 0;
    final v = -after.pawns(s);
    final goal = goalAt(step), value = valueAt(step);
    // начало защитной части комбинированной задачи — как первый ход защиты
    final first = step == 0 || (combined && step == switchAt);
    if (goal == PuzzleGoal.defend) {
      return mates || (after.mate == null && v >= math.max(-1.0, value - (first ? 0.3 : 0.5)));
    }
    if (goal == PuzzleGoal.mate) return mates || (after.mate == null && v >= 5.0);
    final least = goal == PuzzleGoal.win ? 4.0 : (minValue ?? 3.0);
    return mates || v >= math.max(least, 0.6 * value);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'fen': fen,
        'solution': solution,
        'source': source,
        'gap': gap,
        'goal': goal.name,
        'value': value,
        if (alternatives.isNotEmpty) 'alternatives': alternatives,
        if (prevFen != null) 'prevFen': prevFen,
        if (prevMove != null) 'prevMove': prevMove,
        if (tags.isNotEmpty) 'tags': tags.toList(),
        'minValue': ?minValue,
        if (goal2 != null) 'goal2': goal2!.name,
        if (goal2 != null) 'value2': value2,
        'switchAt': ?switchAt,
      };

  factory Puzzle.fromJson(Map<String, dynamic> j) => Puzzle(
        id: j['id'] as String,
        fen: j['fen'] as String,
        solution: (j['solution'] as List).cast<String>(),
        source: j['source'] as String,
        gap: (j['gap'] as num).toDouble(),
        goal: PuzzleGoal.values.byName(j['goal'] as String),
        value: (j['value'] as num?)?.toDouble() ?? 0,
        alternatives: [for (final a in (j['alternatives'] as List?) ?? const []) (a as List).cast<String>()],
        prevFen: j['prevFen'] as String?,
        prevMove: j['prevMove'] as String?,
        tags: {...((j['tags'] as List?) ?? const []).cast<String>()},
        minValue: (j['minValue'] as num?)?.toDouble(),
        goal2: j['goal2'] == null ? null : PuzzleGoal.values.byName(j['goal2'] as String),
        value2: (j['value2'] as num?)?.toDouble() ?? 0,
        switchAt: j['switchAt'] as int?,
      );

  /// This puzzle followed by [next] (a combined puzzle): [reply] is the
  /// opponent's move between them.
  Puzzle then(String reply, Puzzle next) => Puzzle(
        id: id,
        fen: fen,
        solution: [...solution, reply, ...next.solution],
        source: source,
        gap: gap,
        goal: goal,
        value: value,
        alternatives: const [],
        prevFen: prevFen,
        prevMove: prevMove,
        tags: {...tags, ...next.tags},
        minValue: minValue,
        goal2: next.goal,
        value2: next.value,
        switchAt: solution.length + 1,
      );

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
    // [авторское] перевес — от +3; +2 только в дебюте и начале миттельшпиля,
    // если позиция дальше не острая; выигрыш — от +4 или мат
    final early = r.stage == 'opening' || (r.stage == 'middlegame' && r.ply < 30);
    final calm = early &&
        characterOf(Pos.fromFen(p.fenBefore), lines, p.allLines, s).sharpness != Sharpness.sharp;
    final advantageFrom = calm ? 2.0 : 3.0;
    PuzzleGoal? goal;
    if (mates) {
      goal = PuzzleGoal.mate;
    } else if (tactical && gap >= 1.0 && value >= 4.0) {
      goal = PuzzleGoal.win;
    } else if (tactical && gap >= 1.0 && value >= advantageFrom) {
      goal = PuzzleGoal.advantage;
    } else if (gap >= 1.5 && value > -1.0 && value < 1.0) {
      // единственная защита: остальное проигрывает, лучший ход держит
      goal = PuzzleGoal.defend;
    }
    if (goal == null) continue;
    final start = Pos.fromFen(p.fenBefore);
    final solution = tacticLine(start, best.pv);
    if (solution.isEmpty) continue;
    final draft = Puzzle(
        id: '',
        fen: p.fenBefore,
        solution: solution,
        source: '',
        gap: gap,
        goal: goal,
        value: value,
        minValue: goal == PuzzleGoal.advantage ? advantageFrom : null);
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
      minValue: goal == PuzzleGoal.advantage ? advantageFrom : null,
    ));
  }
  return withoutOverlaps(combine(out, a.game));
}

/// [авторское] Combined puzzles: an attack whose line, played in the game,
/// leads straight to a position where only a precise defence holds (or the
/// other way round) becomes one puzzle — take the advantage, then hold it.
/// Rare, but these are the hardest moments: the goal changes on the way.
List<Puzzle> combine(List<Puzzle> list, GameData g) {
  final byPly = {for (final p in list) int.parse(p.id.substring(p.id.lastIndexOf(':') + 1)): p};
  final used = <String>{};
  final out = <Puzzle>[];
  for (final p in list) {
    if (used.contains(p.id)) continue;
    final ply = int.parse(p.id.substring(p.id.lastIndexOf(':') + 1));
    final end = ply + p.solution.length; // ход соперника после решения
    final next = byPly[end + 1];
    final attack = p.goal != PuzzleGoal.defend;
    final follows = end < g.plies.length &&
        [for (var i = 0; i < p.solution.length; i++) ply + i < g.plies.length && g.plies[ply + i].uci == p.solution[i]]
            .every((x) => x);
    if (next != null && !next.combined && follows && attack != (next.goal != PuzzleGoal.defend)) {
      out.add(p.then(g.plies[end].uci, next));
      used.add(next.id);
    } else {
      out.add(p);
    }
  }
  return [for (final p in out) if (!used.contains(p.id) || p.combined) p];
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
      (p.defends ? 200 : 0) +
      (p.combined ? 200 : 0) +
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
      {this.rating, this.goal, this.step, this.fen, this.wrong = const [], this.tags = const []});

  /// The puzzle's traits (weakness.dart), kept for the list of mistakes made
  /// in puzzles even when the puzzle is gone.
  final List<String> tags;

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
      PuzzleAttempt(id, source, solved, date, rating: r, goal: goal, step: step, fen: fen, wrong: wrong, tags: tags);

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
        if (tags.isNotEmpty) 'tags': tags,
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
        tags: (j['tags'] as List?)?.cast<String>() ?? const [],
      );
}

/// Estimated puzzle ratings, kept between sessions.
class PuzzleRatings {
  static const _key = 'puzzles.ratings';

  /// Version of the rating formula (puzzle_rater.dart): ratings of an older
  /// one are forgotten and the puzzles are rated again.
  static const version = 5;

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

  /// Records [a]; an attempt of the same try (same puzzle and start time)
  /// is replaced: a try is recorded once, with all its mistakes.
  static Future<void> add(PuzzleAttempt a) async {
    try {
      final p = await SharedPreferences.getInstance();
      final rest = [
        for (final raw in p.getStringList(_key) ?? <String>[])
          if (!(() {
            final j = jsonDecode(raw) as Map<String, dynamic>;
            return j['id'] == a.id && j['date'] == a.date.toIso8601String();
          })())
            raw,
      ];
      await p.setStringList(_key, [jsonEncode(a.toJson()), ...rest]);
    } catch (_) {}
  }
}

/// Puzzles already shown (opened), so that the next session starts with
/// new ones: unseen first, then the seen and unsolved, the solved last.
class PuzzleSeen {
  static const _key = 'puzzles.seen';

  static Future<Set<String>> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      return {...?p.getStringList(_key)};
    } catch (_) {
      return {};
    }
  }

  static Future<void> add(String id) async {
    try {
      final p = await SharedPreferences.getInstance();
      final list = p.getStringList(_key) ?? <String>[];
      if (list.contains(id)) return;
      // не больше 20 000 последних
      await p.setStringList(_key, [...list.length >= 20000 ? list.sublist(list.length - 19999) : list, id]);
    } catch (_) {}
  }
}
