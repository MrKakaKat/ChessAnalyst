/// Engine opponent with eight levels of strength.
library;

import 'dart:async';
import 'dart:math' as math;

import '../analysis/eval.dart';
import 'engine.dart';

/// A level: Stockfish's Skill Level with a depth and time cap.
class BotLevel {
  const BotLevel(this.number, this.skill, this.depth, this.movetimeMs);

  final int number;
  final int skill;
  final int depth;
  final int movetimeMs;
}

/// [простое решение] Levels 1–8: Skill Level 0..20 with growing depth and
/// thinking time, as in common online engine ladders.
const botLevels = [
  BotLevel(1, 0, 1, 50),
  BotLevel(2, 2, 2, 100),
  BotLevel(3, 4, 3, 150),
  BotLevel(4, 7, 5, 250),
  BotLevel(5, 10, 7, 400),
  BotLevel(6, 13, 9, 600),
  BotLevel(7, 16, 12, 900),
  BotLevel(8, 20, 16, 1500),
];

/// Engine evaluation: centipawns or mate (side to move), and the main line.
class EngineEval {
  const EngineEval({this.cp, this.mate, required this.pv});

  final int? cp;
  final int? mate;
  final List<String> pv;
}

class EngineBot {
  EngineBot._(this._engine) {
    _sub = _engine.lines.listen(_onLine);
  }

  final UciEngine _engine;
  late final StreamSubscription<String> _sub;
  Completer<String>? _waiting;
  String? _waitFor;
  final _info = <String>[];
  Future<void> _queue = Future.value();

  /// When the engine last wrote anything (a long search keeps writing).
  DateTime _lastLine = DateTime.now();

  /// Runs engine requests one after another (the engine is single-threaded).
  Future<T> _serial<T>(Future<T> Function() job) {
    final next = _queue.then((_) => job());
    _queue = next.then((_) {}, onError: (_) {});
    return next;
  }

  static Future<EngineBot>? _shared;

  /// One engine for the whole app: games against it and game analysis take
  /// turns on it (requests run one after another).
  static Future<EngineBot> shared() => _shared ??= start().catchError((Object e) {
        _shared = null;
        throw e;
      });

  /// Drops the shared engine (it stopped answering); the next [shared]
  /// starts a fresh one.
  static Future<void> reset() async {
    final old = _shared;
    _shared = null;
    if (old == null) return;
    try {
      final bot = await old;
      bot._engine.send('stop');
      await bot.dispose();
    } catch (_) {}
  }

  static Future<EngineBot> start() async {
    final bot = EngineBot._(await startEngine());
    await bot._ask('uci', 'uciok');
    bot._engine.send('setoption name UCI_ShowWDL value true');
    await bot._ask('isready', 'readyok');
    return bot;
  }

  int get cores => _engine.cores;

  /// Root lines of [fen] at [depth]: up to [multipv] best moves (or only
  /// [searchMove]), each with its evaluation (side to move) and main line.
  Future<List<Line>> analyse(String fen,
          {required int depth, int multipv = 10, int threads = 1, String? searchMove}) =>
      _serial(() async {
        _engine.send('setoption name Skill Level value 20');
        _engine.send('setoption name Threads value $threads');
        _engine.send('setoption name MultiPV value ${searchMove == null ? multipv : 1}');
        _engine.send('position fen $fen');
        _info.clear();
        await _ask('go depth $depth${searchMove != null ? ' searchmoves $searchMove' : ''}', 'bestmove', search: true);
        _engine.send('setoption name MultiPV value 1');
        final byIndex = <int, Line>{};
        for (final info in _info) {
          final line = _parseLine(info);
          if (line != null) byIndex[line.$1] = line.$2;
        }
        return [for (final k in byIndex.keys.toList()..sort()) byIndex[k]!];
      });

  static (int, Line)? _parseLine(String info) {
    final t = info.split(' ');
    int at(String key) => t.indexOf(key);
    final pvAt = at('pv');
    final scoreAt = at('score');
    if (pvAt < 0 || scoreAt < 0 || pvAt + 1 >= t.length) return null;
    final multipv = at('multipv') >= 0 ? int.parse(t[at('multipv') + 1]) : 1;
    final kind = t[scoreAt + 1];
    final value = int.parse(t[scoreAt + 2]);
    final cp = kind == 'cp' ? value : null;
    final mate = kind == 'mate' && value != 0 ? value : null;
    if (cp == null && mate == null) return null;
    (int, int, int) wdl;
    final w = at('wdl');
    if (w >= 0) {
      wdl = (int.parse(t[w + 1]), int.parse(t[w + 2]), int.parse(t[w + 3]));
    } else if (mate != null) {
      wdl = mate > 0 ? (1000, 0, 0) : (0, 0, 1000);
    } else {
      // без WDL — грубая логистическая оценка по сантипешкам
      final win = (1000 / (1 + math.exp(-cp! / 250))).round();
      wdl = (win, 0, 1000 - win);
    }
    final pv = t.sublist(pvAt + 1).where((s) => s.isNotEmpty).toList();
    return (multipv, Line(move: pv.first, eval: Eval(cp: cp, mate: mate, wdl: wdl), pv: pv));
  }


  void _onLine(String line) {
    _lastLine = DateTime.now();
    if (line.startsWith('info ') && line.contains(' pv ')) _info.add(line);
    final w = _waitFor;
    if (w != null && line.startsWith(w)) {
      _waitFor = null;
      _waiting?.complete(line);
      _waiting = null;
    }
  }

  /// Sends [command] and waits for the line starting with [reply].
  /// [search]: a deep search may take minutes on a phone, so there is no
  /// total limit. After 90 s without a line the search is asked to stop: the
  /// engine then answers with the best move found so far (a shallower
  /// result rather than none). Only if even that brings no answer within
  /// another minute is it an error. The engine is never killed and
  /// restarted here: the native engine may not free itself in time, and a
  /// new one then cannot start ("Failed to spawn isolates").
  Future<String> _ask(String command, String reply, {bool search = false}) {
    _waitFor = reply;
    final c = _waiting = Completer<String>();
    _lastLine = DateTime.now();
    _engine.send(command);
    if (!search) return c.future.timeout(const Duration(seconds: 30));
    var stopped = false;
    final watch = Timer.periodic(const Duration(seconds: 5), (_) {
      if (c.isCompleted) return;
      final quiet = DateTime.now().difference(_lastLine);
      if (!stopped && quiet >= const Duration(seconds: 90)) {
        stopped = true;
        _lastLine = DateTime.now();
        _engine.send('stop');
      } else if (stopped && quiet >= const Duration(seconds: 60)) {
        _waitFor = null;
        _waiting = null;
        c.completeError(TimeoutException('The engine stopped answering'));
      }
    });
    return c.future.whenComplete(watch.cancel);
  }

  Future<void> newGame() => _serial(() async {
        _engine.send('ucinewgame');
        await _ask('isready', 'readyok');
      });

  /// Best move (UCI) in [fen] at [level].
  Future<String> bestMove(String fen, BotLevel level) => _serial(() async {
        _engine.send('setoption name Skill Level value ${level.skill}');
        _engine.send('position fen $fen');
        final line = await _ask('go depth ${level.depth} movetime ${level.movetimeMs}', 'bestmove', search: true);
        return line.split(' ')[1];
      });

  /// Full-strength evaluation of [fen]: score from the side to move
  /// (centipawns or mate) and the main line.
  Future<EngineEval> evaluate(String fen, {int depth = 12}) => _serial(() async {
        _engine.send('setoption name Skill Level value 20');
        _engine.send('position fen $fen');
        _info.clear();
        await _ask('go depth $depth movetime 1500', 'bestmove', search: true);
        final last = _info.isEmpty ? null : _info.last;
        if (last == null) return const EngineEval(cp: 0, pv: []);
        final t = last.split(' ');
        final i = t.indexOf('score');
        final pv = t.sublist(t.indexOf('pv') + 1);
        if (i >= 0 && t[i + 1] == 'mate') return EngineEval(mate: int.parse(t[i + 2]), pv: pv);
        return EngineEval(cp: i >= 0 ? int.parse(t[i + 2]) : 0, pv: pv);
      });

  Future<void> dispose() async {
    await _sub.cancel();
    await _engine.dispose();
  }
}
