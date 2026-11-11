/// Puzzles and weakness entries of each analysed game, made once when its
/// analysis ends and kept on the device.
///
/// [авторское] The Puzzles screen used to rebuild the whole analysis of
/// every game (grades, kinds, ideas) each time it opened, so it grew slower
/// with every game: with a hundred games there are thousands of puzzles.
/// Now each game leaves a small record when its analysis ends — its puzzles
/// and its mistakes with their traits and weight — and the screen only reads
/// these records. A record is made again only when it is out of date: the
/// game was analysed deeper, or the analysis rules or this format changed.
///
/// The weakness profile comes from four sources, from the heaviest:
/// 1. mistakes in your games that you underlined (not clear to you): ×2;
/// 2. the other mistakes in your games, by how serious they are
///    (inaccuracy 1 … blunder 4, ×1…×2 for a hard punishment, ×1.5 for each
///    repeated miss of the same move);
/// 3. mistakes in puzzles: 1.25 for a try with a mistake, +0.25 for each
///    further mistake, up to 2 — a little less than a mistake in a game;
/// 4. mistakes when correcting your own games (Start to improve): the same
///    weight as in puzzles.
library;

import 'dart:convert';

import 'package:dartchess/dartchess.dart' show Side;
import 'package:shared_preferences/shared_preferences.dart';

import '../analysis/game.dart';
import '../analysis/human.dart';
import '../analysis/pos.dart';
import '../analysis/settings.dart';
import '../analysis/weakness.dart';
import 'prefs.dart';
import 'improve_history.dart';
import 'puzzles.dart';
import 'underlines.dart';

/// A mistake of a game with its traits and base weight (without the
/// underline, which can change later).
class StoredMistake {
  const StoredMistake(this.white, this.ply, this.step, this.tags, this.weight);

  final bool white;
  final int ply;
  final String step;
  final List<String> tags;
  final double weight;

  Map<String, dynamic> toJson() => {'w': white, 'p': ply, 's': step, 't': tags, 'x': weight};

  factory StoredMistake.fromJson(Map<String, dynamic> j) => StoredMistake(
      j['w'] as bool, j['p'] as int, j['s'] as String, (j['t'] as List).cast<String>(), (j['x'] as num).toDouble());
}

class StoredGame {
  const StoredGame({
    required this.gameId,
    required this.white,
    required this.black,
    required this.depth,
    required this.plies,
    required this.puzzlesOn,
    required this.puzzles,
    required this.mistakes,
  });

  final String gameId, white, black;
  final int depth, plies;

  /// The game's puzzles were switched on when it was analysed.
  final bool puzzlesOn;
  final List<Puzzle> puzzles;
  final List<StoredMistake> mistakes;

  Map<String, dynamic> toJson() => {
        'v': PuzzleStore.version,
        'rules': analysisRules,
        'game': gameId,
        'white': white,
        'black': black,
        'depth': depth,
        'plies': plies,
        'on': puzzlesOn,
        'puzzles': [for (final p in puzzles) p.toJson()],
        'mistakes': [for (final m in mistakes) m.toJson()],
      };

  factory StoredGame.fromJson(Map<String, dynamic> j) => StoredGame(
        gameId: j['game'] as String,
        white: j['white'] as String? ?? '',
        black: j['black'] as String? ?? '',
        depth: j['depth'] as int? ?? 0,
        plies: j['plies'] as int? ?? 0,
        puzzlesOn: j['on'] as bool? ?? true,
        puzzles: [for (final p in (j['puzzles'] as List)) Puzzle.fromJson(p as Map<String, dynamic>)],
        mistakes: [for (final m in (j['mistakes'] as List)) StoredMistake.fromJson(m as Map<String, dynamic>)],
      );
}

class PuzzleStore {
  /// Version of the record; with the analysis rules and the depth it decides
  /// whether a record is still good.
  static const version = 2;
  static const _prefix = 'pstore.';

  /// The record of [key] if it is up to date for [depth] and [plies].
  static Future<StoredGame?> read(String key, {int? depth, int? plies}) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('$_prefix$key');
      if (raw == null) return null;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      if (j['v'] != version || j['rules'] != analysisRules) return null;
      if (depth != null && j['depth'] != depth) return null;
      if (plies != null && j['plies'] != plies) return null;
      return StoredGame.fromJson(j);
    } catch (_) {
      return null;
    }
  }

  /// Makes and saves the record of [key] from analysis [a].
  static Future<StoredGame> build(String key, GameAnalysis a, {bool puzzles = true}) async {
    final g = StoredGame(
      gameId: a.game.id,
      white: a.game.white,
      black: a.game.black,
      depth: (a.game.engine['depth'] as num?)?.toInt() ?? 0,
      plies: a.game.plies.length,
      puzzlesOn: puzzles,
      puzzles: puzzles ? puzzlesFrom(a) : const [],
      mistakes: mistakesOf(a),
    );
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('$_prefix$key', jsonEncode(g.toJson()));
    } catch (_) {}
    return g;
  }

  static Future<void> remove(String key) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove('$_prefix$key');
    } catch (_) {}
  }
}

/// The negative moves of both sides of [a] with their traits and weight.
List<StoredMistake> mistakesOf(GameAnalysis a) => [
      for (final r in a.records.where((r) => negativeSteps.contains(r.step)))
        () {
          final p = a.game.plies[r.ply];
          final next = r.ply + 1 < a.game.plies.length ? a.game.plies[r.ply + 1] : null;
          final tags = mistakeTags(r, Pos.fromFen(p.fenBefore), p.lines.first,
              after: next == null ? null : Pos.fromFen(next.fenBefore), reply: next?.lines.firstOrNull, lines: p.lines);
          // [авторское] вес растёт с трудностью наказания (×1…×2) и с каждым
          // повторным пропуском того же лучшего хода (×1,5 за раз)
          final hard = moveWeight(a.game, r.ply)?.value ?? 40;
          final w = mistakeWeight(r.step) * (1 + hard / 100) * (1 + 0.5 * missedAgain(a, r.ply));
          return StoredMistake(r.side == Side.white, r.ply, r.step, tags.toList(), w);
        }(),
    ];

/// The weight of a try at a puzzle with [errors] mistakes (0: none).
double puzzleMistakeWeight(int errors, {bool solved = true}) {
  if (errors == 0 && solved) return 0;
  final n = errors == 0 ? 1 : errors;
  return (1.25 + 0.25 * (n - 1)).clamp(0, 2).toDouble();
}

/// The player's names (Settings) or the most frequent name in [games].
String playerNameFrom(List<StoredGame> games) {
  if (prefs.playerName.trim().isNotEmpty) return prefs.playerName.trim();
  final count = <String, int>{};
  for (final g in games) {
    for (final n in [g.white, g.black]) {
      final k = n.trim().toLowerCase();
      count[k] = (count[k] ?? 0) + 1;
    }
  }
  if (count.isEmpty) return '';
  return (count.entries.toList()..sort((a, b) => b.value - a.value)).first.key;
}

/// Whether the player ([names], comma-separated) was White in a game of
/// [white] and [black]; null when neither matches.
bool? playerIsWhite(String white, String black, String names) {
  final w = white.trim().toLowerCase(), b = black.trim().toLowerCase();
  for (final raw in names.split(',')) {
    final n = raw.trim().toLowerCase();
    if (n.isEmpty) continue;
    if (w == n || w.contains(n)) return true;
    if (b == n || b.contains(n)) return false;
  }
  return null;
}

/// The weakness profile (tag → weight) from the records of the own games,
/// the recorded puzzle attempts and the Start-to-improve history.
Future<Map<String, double>> profileFrom(List<StoredGame> own,
    {List<PuzzleAttempt> attempts = const [], Map<String, Puzzle> puzzles = const {}}) async {
  await underlines.load();
  final name = playerNameFrom(own);
  final out = <String, double>{};
  void add(Iterable<String> tags, double w) {
    for (final t in tags) {
      out[t] = (out[t] ?? 0) + w;
    }
  }

  final byGame = <String, StoredGame>{};
  for (final g in own) {
    byGame[g.gameId] = g;
    final white = playerIsWhite(g.white, g.black, name);
    if (white == null) continue;
    for (final m in g.mistakes.where((m) => m.white == white)) {
      add(m.tags, m.weight * (underlines.has(g.gameId, m.ply) ? 2 : 1));
    }
  }
  await addTrainingMistakes(out, attempts: attempts, puzzles: puzzles, tagsAt: (id, ply) {
    final m = byGame[id]?.mistakes.where((m) => m.ply == ply).firstOrNull;
    return m?.tags;
  });
  return out;
}

/// Adds to [profile] the mistakes made in puzzles ([attempts]) and when
/// correcting own games (the Start-to-improve history; [tagsAt] gives the
/// traits of the game's mistake at a ply), with the same, lighter weight.
Future<void> addTrainingMistakes(Map<String, double> profile,
    {List<PuzzleAttempt> attempts = const [],
    Map<String, Puzzle> puzzles = const {},
    required Iterable<String>? Function(String gameId, int ply) tagsAt}) async {
  void add(Iterable<String> tags, double w) {
    for (final t in tags) {
      profile[t] = (profile[t] ?? 0) + w;
    }
  }

  // ошибки в задачах — чуть легче ошибок в партиях
  for (final a in attempts) {
    final w = puzzleMistakeWeight(a.errors, solved: a.solved);
    if (w == 0) continue;
    add(a.tags.isNotEmpty ? a.tags : (puzzles[a.id]?.tags ?? const <String>{}), w);
  }
  // ошибки при исправлении своих партий — с тем же весом, что в задачах
  final improve = await ImproveHistory.load();
  for (final e in improve.entries) {
    final r = e.value;
    final missed = r.tries - r.solved + ((r.lastClean ?? true) ? 0 : 1);
    if (missed <= 0) continue;
    final parts = e.key.split(':');
    if (parts.length < 3) continue;
    final ply = int.tryParse(parts[parts.length - 2]);
    if (ply == null) continue;
    final tags = tagsAt(parts.sublist(0, parts.length - 2).join(':'), ply);
    if (tags != null) add(tags, puzzleMistakeWeight(missed));
  }
}
