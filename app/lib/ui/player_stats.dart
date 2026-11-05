/// The player's statistics over their own analysed games, and the weakness
/// profile built from their mistakes.
///
/// [простое решение] The player's side in a game is the side whose name
/// matches the name in Settings; without one, the name met most often in
/// the analysed games.
library;

import 'package:dartchess/dartchess.dart' show Side;

import '../analysis/game.dart';
import '../analysis/kinds.dart';
import '../analysis/openings.dart';
import '../analysis/pos.dart';
import '../analysis/settings.dart';
import '../analysis/weakness.dart';
import 'history_store.dart';
import 'labels.dart' show typeLabels;
import 'prefs.dart';
import 'puzzles.dart';
import 'underlines.dart';

class ColourStats {
  int games = 0, wins = 0, draws = 0, losses = 0;
  final steps = <String, int>{};
}

class PlayerStats {
  PlayerStats(this.name);

  final String name;
  final colours = {Side.white: ColourStats(), Side.black: ColourStats()};
  final stages = <String, int>{};
  final missed = <String, int>{};

  /// Kinds of the opponent's moves that punished the mistakes.
  final punished = <String, int>{};
  final losses = <String, int>{};
  final irreversibility = <String, int>{};

  /// Tag → weight (weakness.dart).
  final profile = <String, double>{};

  /// For the strongest weakness tags: puzzles solved with that tag and their
  /// mean rating ("chunks": the more and the harder, the better learnt).
  final chunks = <String, (int solved, double rating)>{};

  int get games => colours[Side.white]!.games + colours[Side.black]!.games;
}

/// Own analysed games (ready) with their analyses.
Future<List<GameAnalysis>> ownAnalyses(OpeningBook? book) async {
  await history.load();
  final out = <GameAnalysis>[];
  for (final e in history.entries) {
    final job = await history.open(e.id);
    if (job == null || !job.ready) continue;
    if (job.tagSnapshot case final snap?) _snapshots[job.id] = snap;
    out.add(analyzeGame(job.snapshot(), const Settings(unit: Unit.pawns), book: book));
  }
  return out;
}

/// Trait snapshots of the own analyses, by game id (see [mistakeSnapshot]).
final _snapshots = <String, Map<String, Map<String, int>>>{};

String _norm(String s) => s.trim().toLowerCase();

/// The player's names: from Settings (comma-separated), or the most
/// frequent one.
String playerNameOf(List<GameAnalysis> games) {
  if (prefs.playerName.trim().isNotEmpty) return prefs.playerName.trim();
  final count = <String, int>{};
  for (final a in games) {
    for (final n in [a.game.white, a.game.black]) {
      count[_norm(n)] = (count[_norm(n)] ?? 0) + 1;
    }
  }
  if (count.isEmpty) return '';
  return (count.entries.toList()..sort((a, b) => b.value - a.value)).first.key;
}

/// The names in [names]: several, separated by commas (accounts on
/// different sites).
List<String> playerNames(String names) => [for (final n in names.split(',')) if (_norm(n).isNotEmpty) _norm(n)];

/// The side the player had in [g]: the first of the names that matches.
Side? playerSide(GameData g, String names) {
  for (final n in playerNames(names)) {
    if (_norm(g.white) == n || _norm(g.white).contains(n)) return Side.white;
    if (_norm(g.black) == n || _norm(g.black).contains(n)) return Side.black;
  }
  return null;
}

/// Traits of each side's negative moves in [a]: side → tag → count (kept
/// with the analysis, see AnalysisJob.tagSnapshot).
Map<String, Map<String, int>> mistakeSnapshot(GameAnalysis a) {
  final out = {'white': <String, int>{}, 'black': <String, int>{}};
  for (final r in a.records.where((r) => negativeSteps.contains(r.step))) {
    final p = a.game.plies[r.ply];
    final next = r.ply + 1 < a.game.plies.length ? a.game.plies[r.ply + 1] : null;
    final tags = mistakeTags(r, Pos.fromFen(p.fenBefore), p.lines.first,
        after: next == null ? null : Pos.fromFen(next.fenBefore), reply: next?.lines.firstOrNull, lines: p.lines);
    final m = out[r.side == Side.white ? 'white' : 'black']!;
    for (final t in tags) {
      m[t] = (m[t] ?? 0) + 1;
    }
  }
  return out;
}

Future<PlayerStats> collectStats(List<GameAnalysis> games, {List<Puzzle> puzzles = const []}) async {
  await underlines.load();
  final name = playerNameOf(games);
  final st = PlayerStats(name);
  for (final a in games) {
    final side = playerSide(a.game, name);
    if (side == null) continue;
    final c = st.colours[side]!;
    c.games++;
    final result = a.game.headers['result'] ?? '*';
    final won = (result == '1-0' && side == Side.white) || (result == '0-1' && side == Side.black);
    final lost = (result == '0-1' && side == Side.white) || (result == '1-0' && side == Side.black);
    if (won) c.wins++;
    if (lost) c.losses++;
    if (result == '1/2-1/2') c.draws++;
    for (final r in a.records.where((r) => r.side == side && negativeSteps.contains(r.step))) {
      c.steps[r.step] = (c.steps[r.step] ?? 0) + 1;
      st.stages[r.stage] = (st.stages[r.stage] ?? 0) + 1;
      final p = a.game.plies[r.ply];
      final board = Pos.fromFen(p.fenBefore);
      final best = p.lines.first;
      final next = r.ply + 1 < a.game.plies.length ? a.game.plies[r.ply + 1] : null;
      final tags = mistakeTags(r, board, best,
          after: next == null ? null : Pos.fromFen(next.fenBefore), reply: next?.lines.firstOrNull, lines: p.lines);
      final w = mistakeWeight(r.step, underlined: underlines.has(a.game.id, r.ply));
      for (final t in tags) {
        st.profile[t] = (st.profile[t] ?? 0) + w;
        if (t.startsWith('kind:')) st.missed[t.substring(5)] = (st.missed[t.substring(5)] ?? 0) + 1;
        if (t.startsWith('punish:')) st.punished[t.substring(7)] = (st.punished[t.substring(7)] ?? 0) + 1;
        if (t.startsWith('loss:')) st.losses[t.substring(5)] = (st.losses[t.substring(5)] ?? 0) + 1;
        if (t.startsWith('irr:')) st.irreversibility[t.substring(4)] = (st.irreversibility[t.substring(4)] ?? 0) + 1;
      }
    }
    // виды, которых в новой версии правил нет, берутся из снимка анализа
    final snap = _snapshots[a.game.id]?[side == Side.white ? 'white' : 'black'];
    for (final e in snap?.entries ?? const <MapEntry<String, int>>[]) {
      final t = e.key;
      final i = t.indexOf(':');
      final kind = i < 0 ? '' : t.substring(i + 1);
      if ((t.startsWith('kind:') || t.startsWith('punish:')) && !kindLabels.containsKey(kind)) {
        final m = t.startsWith('kind:') ? st.missed : st.punished;
        m[kind] = (m[kind] ?? 0) + e.value;
      }
    }
  }
  // чанки: решённые задачи по сильнейшим признакам слабости
  final attempts = await PuzzleHistory.load();
  final ratings = await PuzzleRatings.load();
  final byId = {for (final p in puzzles) p.id: p};
  final top = (st.profile.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(6);
  for (final t in top) {
    var n = 0;
    var sum = 0.0;
    for (final at in attempts.where((x) => x.solved)) {
      final pz = byId[at.id];
      if (pz == null || !pz.tags.contains(t.key)) continue;
      n++;
      sum += at.rating ?? ratings[at.id] ?? quickRating(pz);
    }
    st.chunks[t.key] = (n, n == 0 ? 0 : sum / n);
  }
  return st;
}

/// Readable name of a profile tag.
String tagLabel(String tag) {
  final i = tag.indexOf(':');
  final kind = tag.substring(0, i), v = tag.substring(i + 1);
  return switch (kind) {
    'colour' => v == 'white' ? 'With White' : 'With Black',
    'stage' => v[0].toUpperCase() + v.substring(1),
    'type' => '${v[0].toUpperCase()}${v.substring(1)} moves',
    'kind' => 'Missed: ${kindLabels[v] ?? v}',
    'punish' => 'Punished by: ${kindLabels[v] ?? v}',
    'dir' => v.split('+').map((d) => typeLabels[d] ?? d).join(' + '),
    'loss' => lossLabels[v] ?? v,
    'irr' => 'Irreversibility: ${irreversibilityLabels[v] ?? v}',
    _ => tag,
  };
}
