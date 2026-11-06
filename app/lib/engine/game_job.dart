/// Analysis of a user's game on the device, with the built-in engine.
///
/// Two passes: a quick one (depth 8) so the analysis can open at once, then
/// the chosen depth. The game screen refreshes from the job every 5 seconds;
/// changed icons and cards animate. The job can be paused, resumed and sent
/// deeper (+4 plies). Power limits the heat: engine threads and a pause after
/// every position, as a share of its computing time.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../analysis/eval.dart';
import '../analysis/game.dart';
import '../analysis/pgn_import.dart';
import '../analysis/pos.dart';
import '../analysis/settings.dart';
import 'bot.dart';

enum EnginePower { low, medium, high }

enum JobState { running, paused, done, failed }

/// Depth presets of the import screen.
/// Depth of the pass over all legal moves (as trivial_depth in Python).
const allMovesDepth = 8;

/// How much longer each extra ply of depth takes (rough, measured on phones).
const _depthFactor = 1.45;

/// Rough time for one position before anything is measured: about 0.4 s at
/// depth 8 with 10 lines on one thread of a phone.
double _estimateMs(int depth, int lines, EnginePower power) =>
    400 *
    math.pow(_depthFactor, depth - 8).toDouble() *
    math.pow(lines / 10, 0.7).toDouble() *
    (power == EnginePower.low ? 1.6 : (power == EnginePower.medium ? 1.0 : 0.7));

/// Expected duration of a whole analysis, from the number of positions, the
/// depth, the lines and the power (shown before it starts).
Duration estimateDuration(int positions, int depth, int lines, EnginePower power, {bool quickFirst = true}) {
  final rest = switch (power) { EnginePower.low => 1.5, EnginePower.medium => 0.5, EnginePower.high => 0.0 };
  var ms = positions * _estimateMs(depth, lines, power) * (1 + rest);
  if (quickFirst && depth > quickDepth) ms += positions * _estimateMs(quickDepth, lines, power) * (1 + rest);
  return Duration(milliseconds: ms.round());
}

String durationText(Duration d) {
  if (d.inMinutes < 1) return 'under a minute';
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  return '${d.inHours} h ${d.inMinutes % 60} min';
}

const depthPresets = {'Quick': 10, 'Standard': 14, 'Deep': 18, 'Maximum': 22};

const quickDepth = 8;
const maxDepth = 26;

class AnalysisJob extends ChangeNotifier {
  AnalysisJob({
    required this.id,
    required this.source,
    required this.targetDepth,
    this.power = EnginePower.medium,
    this.multipv = 10,
    this.quickFirst = true,
    List<GamePly?>? plies,
    List<int>? depthAt,
    DateTime? created,
    this.finished,
    this.rules = analysisRules,
    this.puzzles = true,
    this.tagSnapshot,
  })  : plies = plies ?? List.filled(source.ucis.length, null),
        depthAt = depthAt ?? List.filled(source.ucis.length, 0),
        created = created ?? DateTime.now();

  final String id;

  /// Engine lines per move (MultiPV).
  final int multipv;

  /// Quick mode: a quick pass first (the game opens), then on to the depth
  /// while the user reads it. Full mode: one pass at the depth, the game
  /// opens when it is done.
  final bool quickFirst;
  final ImportedGame source;
  int targetDepth;
  EnginePower power;
  final List<GamePly?> plies;
  final List<int> depthAt;
  final DateTime created;

  /// When the analysis reached its depth everywhere (null while running).
  DateTime? finished;

  /// Version of the analysis rules it was made with ([analysisRules]).
  final int rules;

  /// Puzzles are made from this game.
  final bool puzzles;

  /// The traits of each side's negative moves when the analysis ended
  /// (side → tag → count): the statistics keep kinds that a later version
  /// may drop.
  Map<String, Map<String, int>>? tagSnapshot;

  JobState state = JobState.paused;

  /// Paused by the user in this session (a job restored from the device or
  /// stopped by an error is not: opening it resumes it).
  bool pausedByUser = false;

  /// Unfinished and not running for a reason other than the user's pause.
  bool get stalled => !done && state != JobState.running && !pausedByUser;
  String? error;

  /// The engine is computing a position right now (false during the rest
  /// between positions that saves power, and while paused).
  bool thinking = false;

  /// Grows with every analysed position; the game screen refreshes on change.
  int revision = 0;

  /// Called after a pass and every few positions (history store).
  void Function(AnalysisJob job)? onSave;

  int get length => plies.length;

  /// All positions have at least the quick pass: the game can open.
  bool get ready => plies.every((p) => p != null);

  /// Depth reached everywhere.
  int get depth => depthAt.isEmpty ? 0 : depthAt.reduce(math.min);

  bool get done => depthAt.every((d) => d >= targetDepth);

  /// 0..1 over both passes.
  double get progress {
    if (length == 0) return 1;
    final quick = depthAt.where((d) => d >= math.min(quickDepth, targetDepth)).length / length;
    final full = depthAt.where((d) => d >= targetDepth).length / length;
    if (!quickFirst) return full;
    return targetDepth <= quickDepth ? quick : 0.3 * quick + 0.7 * full;
  }

  String get title => source.title;

  GameData snapshot() => GameData(
        id: id,
        headers: source.headers,
        startFen: source.startFen,
        engine: {'name': 'Stockfish 19 (light)', 'depth': depth, 'multipv': multipv, 'trivial_depth': 0},
        plies: [for (final p in plies) p!],
      );

  int _threads(int cores) => switch (power) {
        EnginePower.low => 1,
        EnginePower.medium => math.min(2, cores),
        EnginePower.high => math.max(1, math.min(cores - 1, 4)),
      };

  /// Pause after a position, as a share of its computing time.
  /// Mean milliseconds per position at each depth, measured as it runs.
  final _msAt = <int, double>{};

  /// Time left: the positions still to do at each pass, at the measured
  /// speed (the next pass scaled from the current one), with the pauses
  /// between positions. Before any measurement: [estimateDuration].
  Duration get eta {
    if (done) return Duration.zero;
    final passes = [if (quickFirst && targetDepth > quickDepth) quickDepth, targetDepth];
    var ms = 0.0;
    for (final d in passes) {
      final left = depthAt.where((x) => x < d).length;
      if (left == 0) continue;
      final known = _msAt[d];
      final base = _msAt.entries.isEmpty ? null : _msAt.entries.reduce((a, b) => a.key > b.key ? a : b);
      final per = known ??
          (base != null ? base.value * math.pow(_depthFactor, d - base.key) : _estimateMs(d, multipv, power));
      ms += left * per * (1 + _rest);
    }
    return Duration(milliseconds: ms.round());
  }

  double get _rest => switch (power) { EnginePower.low => 1.5, EnginePower.medium => 0.5, EnginePower.high => 0.0 };

  Future<void> start() async {
    if (state == JobState.running || done) return;
    state = JobState.running;
    pausedByUser = false;
    error = null;
    notifyListeners();
    try {
      var bot = await EngineBot.shared();
      for (final d in [if (quickFirst && targetDepth > quickDepth) quickDepth, targetDepth]) {
        for (var i = 0; i < length; i++) {
          if (state != JobState.running) return;
          if (depthAt[i] >= d) continue;
          final watch = Stopwatch()..start();
          thinking = true;
          notifyListeners();
          // движок не ответил — повторяем позицию ещё раз (без перезапуска)
          for (var attempt = 0;; attempt++) {
            try {
              await _analyse(bot, i, d);
              break;
            } on TimeoutException {
              if (attempt >= 1) rethrow;
            }
          }
          watch.stop();
          thinking = false;
          // средняя скорость по глубине — для оценки оставшегося времени
          final prev = _msAt[d];
          _msAt[d] = prev == null ? watch.elapsedMilliseconds.toDouble() : 0.8 * prev + 0.2 * watch.elapsedMilliseconds;
          revision++;
          notifyListeners();
          // сохраняется часто: после обрыва анализ продолжится отсюда
          if (i % 2 == 1) onSave?.call(this);
          final rest = watch.elapsedMilliseconds * _rest;
          if (rest > 0) {
            // пауза для экономии энергии видна на экране партии
            notifyListeners();
            await Future<void>.delayed(Duration(milliseconds: rest.round()));
          }
        }
        onSave?.call(this);
      }
      state = JobState.done;
      finished = DateTime.now();
    } catch (e) {
      thinking = false;
      error = '$e';
      state = JobState.failed;
    }
    onSave?.call(this);
    notifyListeners();
  }

  Future<void> _analyse(EngineBot bot, int i, int depth) async {
    final fen = source.fensBefore[i];
    final uci = source.ucis[i];
    final threads = _threads(bot.cores);
    final lines = await bot.analyse(fen, depth: depth, multipv: multipv, threads: threads);
    if (lines.isEmpty) throw StateError('No engine lines at move ${i + 1}');
    Line? played;
    for (final l in lines) {
      if (l.move == uci) played = l;
    }
    played ??= (await bot.analyse(fen, depth: depth, threads: threads, searchMove: uci)).firstOrNull;
    // все легальные ходы на малой глубине — для характера позиции
    // (тривиальная / острая) и метки trivial; только на основном проходе
    List<Line>? all = plies[i]?.allLines;
    if (all == null && depth >= targetDepth) {
      final n = Pos.fromFen(fen).legalCount;
      all = n <= lines.length ? lines : await bot.analyse(fen, depth: allMovesDepth, multipv: n, threads: threads);
    }
    plies[i] = GamePly(
      san: source.sans[i],
      uci: uci,
      fenBefore: fen,
      lines: lines,
      played: played ?? lines.first,
      allLines: all,
    );
    depthAt[i] = depth;
  }

  void pause() {
    if (state != JobState.running) return;
    pausedByUser = true;
    state = JobState.paused;
    onSave?.call(this);
    notifyListeners();
  }

  /// Sends the analysis 4 plies deeper and runs it.
  void deeper() {
    deepen();
    start();
  }

  /// Raises the target 4 plies without starting (the queue starts it).
  void deepen() => targetDepth = math.min(maxDepth, math.max(targetDepth, depth) + 4);

  Map<String, dynamic> toJson() => {
        'id': id,
        'created': created.toIso8601String(),
        if (finished != null) 'finished': finished!.toIso8601String(),
        'rules': rules,
        'puzzles': puzzles,
        'tag_snapshot': ?tagSnapshot,
        'target': targetDepth,
        'multipv': multipv,
        'quick_first': quickFirst,
        'power': power.name,
        'source': {
          'headers': source.headers,
          'start_fen': source.startFen,
          'sans': source.sans,
          'ucis': source.ucis,
          'fens': source.fensBefore,
        },
        'depth_at': depthAt,
        'plies': [
          for (final p in plies)
            p == null
                ? null
                : {
                    'san': p.san,
                    'uci': p.uci,
                    'fen_before': p.fenBefore,
                    'lines': [for (final l in p.lines) l.toJson()],
                    'played': p.played.toJson(),
                    if (p.allLines != null) 'all_lines': [for (final l in p.allLines!) l.toJson()],
                  },
        ],
      };

  factory AnalysisJob.fromJson(Map<String, dynamic> j) {
    final s = j['source'] as Map<String, dynamic>;
    List<String> strings(dynamic xs) => (xs as List).cast<String>();
    return AnalysisJob(
      id: j['id'] as String,
      created: DateTime.tryParse(j['created'] as String? ?? ''),
      finished: DateTime.tryParse(j['finished'] as String? ?? ''),
      // анализы до появления версии правил — версия 1
      rules: j['rules'] as int? ?? 1,
      puzzles: j['puzzles'] as bool? ?? true,
      tagSnapshot: (j['tag_snapshot'] as Map?)?.map((k, v) => MapEntry(k as String, (v as Map).cast<String, int>())),
      targetDepth: j['target'] as int,
      multipv: j['multipv'] as int? ?? 10,
      quickFirst: j['quick_first'] as bool? ?? true,
      power: EnginePower.values.asNameMap()[j['power']] ?? EnginePower.medium,
      source: ImportedGame(
        headers: (s['headers'] as Map).map((k, v) => MapEntry(k as String, '$v')),
        startFen: s['start_fen'] as String,
        sans: strings(s['sans']),
        ucis: strings(s['ucis']),
        fensBefore: strings(s['fens']),
      ),
      depthAt: (j['depth_at'] as List).cast<int>().toList(),
      plies: [
        for (final p in j['plies'] as List)
          p == null
              ? null
              : GamePly(
                  san: p['san'] as String,
                  uci: p['uci'] as String,
                  fenBefore: p['fen_before'] as String,
                  lines: [for (final l in p['lines'] as List) Line.fromJson(l as Map<String, dynamic>)],
                  played: Line.fromJson(p['played'] as Map<String, dynamic>),
                  allLines: p['all_lines'] == null
                      ? null
                      : [for (final l in p['all_lines'] as List) Line.fromJson(l as Map<String, dynamic>)],
                ),
      ],
    );
  }
}
