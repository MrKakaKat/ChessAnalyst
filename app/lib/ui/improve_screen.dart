/// Start to improve: work through the mistakes of a game.
///
/// [авторское]
/// - **Fix**: the mistakes in order — blunders, mistakes, weaknesses,
///   passes, inaccuracies — each as a position where the player finds a
///   positive move without hints.
/// - **Survival**: after the found move, hold the position against the
///   strongest engine with positive moves only, until the position is quiet,
///   clearly winning (+3) or eight moves are played.
/// - **Foresight**: from the mistake's position, play the plan of both sides
///   for four plies; it counts as understood when the ideas match the
///   engine's line (the same kinds of moves, the same pieces and squares),
///   not the exact moves.
/// A move is positive when it keeps the category of the best line and loses
/// at most 0.3 pawns to it (character.dart).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:chessground/chessground.dart' as cg;
import 'package:chessground/chessground.dart' hide GameData;
import 'package:dartchess/dartchess.dart' hide Board;
import 'package:flutter/material.dart';

import '../analysis/character.dart' show positiveLoss;
import '../analysis/eval.dart';
import '../analysis/features.dart' as features;
import '../analysis/kinds.dart';
import '../analysis/pgn_import.dart' show normalizeCastling;
import '../analysis/pos.dart';
import '../analysis/settings.dart';
import '../engine/bot.dart';
import 'analysis_queue.dart';
import 'controller.dart';
import 'improve_history.dart';
import 'labels.dart';
import 'player_stats.dart' show playerSide;
import 'prefs.dart';
import 'puzzle_screen.dart' show DartHit;
import 'step_icons.dart';
import 'underlines.dart';
import 'board_screen.dart' show AnalysisBoardScreen;
import 'widgets/board_background.dart';

enum ImproveMode { fix, foresight }

const _order = ['blunder', 'mistake', 'laxity', 'pass', 'inaccuracy'];

class ImproveScreen extends StatefulWidget {
  const ImproveScreen({super.key, required this.controller});

  final AnalysisController controller;

  @override
  State<ImproveScreen> createState() => _ImproveScreenState();
}

enum _Phase { find, wrong, found, survival, held, lost, foresight, judged }

class _ImproveScreenState extends State<ImproveScreen> {
  AnalysisController get c => widget.controller;
  late final List<int> _tasks = _collect();
  int _task = 0;
  ImproveMode _mode = ImproveMode.fix;
  _Phase _phase = _Phase.find;
  Pos _pos = Pos(Chess.initial);
  NormalMove? _last;
  bool _busy = false;
  String _note = '';
  int _held = 0;
  final _plan = <NormalMove>[];

  /// The better move after a miss, shown only when its fold is opened.
  String? _better;
  bool _showBetter = false;

  /// After a wrong move: the position before it and the move, to play out
  /// its consequences.
  Pos? _wrongFrom;
  NormalMove? _wrongMove;
  bool _replaying = false;

  /// A line shown on the board (consequences, why the game move was bad):
  /// its positions with the move that led to each, the one shown, and where
  /// the board was before it (to come back).
  List<(Pos, NormalMove?)>? _replay;
  int _replayAt = 0;
  (Pos, NormalMove?)? _beforeReplay;

  /// A positive move was found or held: the dartboard on its square.
  Square? _dartAt;

  /// History of each position (improve_history.dart); the first outcome of
  /// an opened task is recorded once.
  Map<String, ImproveRecord> _hist = {};
  bool _recordedHere = false;
  late final ChessboardController _board = ChessboardController(game: _data());

  /// The player's negative moves (their side in an own game, else both),
  /// from the worst kind to the mildest.
  List<int> _collect() {
    // свои ошибки — если имя игрока задано в статистике и нашлось в партии
    final side = prefs.playerName.trim().isEmpty ? null : playerSide(c.game, prefs.playerName);
    final out = [
      for (final r in c.analysis.records)
        if (_order.contains(r.step) && (side == null || r.side == side)) r.ply,
    ];
    out.sort((a, b) {
      final d = _order.indexOf(c.analysis.records[a].step) - _order.indexOf(c.analysis.records[b].step);
      return d != 0 ? d : a - b;
    });
    return out;
  }

  int get _ply => _tasks[_task];

  cg.GameData _data() => cg.GameData(
    fen: _pos.fen,
    lastMove: _last,
    playerSide: _interactive ? (_pos.turn == Side.white ? PlayerSide.white : PlayerSide.black) : PlayerSide.none,
    sideToMove: _pos.turn,
    kingSquareInCheck: null,
    validMoves: makeLegalMoves(_pos.p),
  );

  bool get _interactive =>
      !_busy && !_replaying && (_phase == _Phase.find || _phase == _Phase.survival || _phase == _Phase.foresight);

  void _sync({bool animate = true}) {
    _board.updatePosition(_data(), animate: animate);
    syncCheck(_board, inCheck: _pos.isCheck, king: _pos.king(_pos.turn));
  }

  @override
  void initState() {
    super.initState();
    if (_tasks.isNotEmpty) _open(0);
    ImproveHistory.load().then((h) {
      if (mounted) setState(() => _hist = h);
    });
  }

  String get _histId => ImproveHistory.id(c.game.id, _ply, _mode.name);

  Future<void> _remember({required bool solved, required bool clean, double? share}) async {
    if (_recordedHere) return;
    _recordedHere = true;
    final id = _histId;
    final rec = await ImproveHistory.add(id, solved: solved, clean: clean, share: share);
    if (mounted) setState(() => _hist[id] = rec);
  }

  /// What the history says about this position, before the attempt.
  String? _historyText() {
    final h = _hist[_histId];
    if (h == null || h.tries == 0) return null;
    final solved = h.solved == 0 ? 'Not solved before' : 'Solved ${h.solved} of ${h.tries} times';
    final last = h.lastClean == null
        ? ''
        : (h.lastClean! ? ' · last time without an error' : ' · last time with an error');
    final share = _mode == ImproveMode.foresight && h.lastShare != null
        ? ' · last prediction ${(h.lastShare! * 100).round()}% accurate'
        : '';
    return '$solved$last$share';
  }

  @override
  void dispose() {
    _board.dispose();
    super.dispose();
  }

  void _open(int i, {bool keepRecord = false}) {
    setState(() {
      _task = i.clamp(0, _tasks.length - 1);
      _pos = c.before[_ply];
      _last = _ply > 0 ? c.moves[_ply - 1] : null;
      _phase = _mode == ImproveMode.fix ? _Phase.find : _Phase.foresight;
      _note = '';
      _held = 0;
      _plan.clear();
      _better = null;
      _showBetter = false;
      _wrongFrom = null;
      _wrongMove = null;
      _replay = null;
      _replaying = false;
      _beforeReplay = null;
      _dartAt = null;
      if (!keepRecord) _recordedHere = false;
    });
    _sync(animate: false);
  }

  /// Whether [m] is positive in [pos]: from known lines, else the engine.
  Future<(bool, Line?)> _judge(Pos pos, NormalMove m, {List<Line>? known}) async {
    const s = Settings();
    final bot = await EngineBot.shared();
    final lines = known ?? await bot.analyse(pos.fen, depth: 12, multipv: 5);
    if (lines.isEmpty) return (false, null);
    var line = lines.where((l) => l.move == m.uci).firstOrNull;
    line ??= (await bot.analyse(pos.fen, depth: 12, searchMove: m.uci)).firstOrNull;
    if (line == null) return (false, lines.first);
    final best = lines.first.eval.pawns(s), v = line.eval.pawns(s);
    final ok = category(v, s.pawns) >= category(best, s.pawns) && best - v <= positiveLoss + 1e-9;
    return (ok, lines.first);
  }

  Future<void> _onMove(NormalMove m) async {
    m = normalizeCastling(_pos, m);
    if (!_pos.isLegal(m)) return;
    if (_phase == _Phase.foresight) return _planMove(m);
    final before = _pos;
    setState(() {
      _busy = true;
      _last = m;
      _pos = before.push(m);
    });
    _sync();
    try {
      final known = _phase == _Phase.find ? c.game.plies[_ply].lines : null;
      final (ok, best) = await _judge(before, m, known: known);
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _phase = _phase == _Phase.find ? _Phase.wrong : _Phase.lost;
          _note = _phase == _Phase.wrong ? 'Not a positive move.' : 'The position slipped away.';
          // лучший ход — в свёртке, чтобы не подсказывать сразу
          _better = best == null ? null : before.san(Pos.move(best.move));
          _wrongFrom = before;
          _wrongMove = m;
          _dartAt = null;
        });
        if (_phase == _Phase.wrong) _remember(solved: false, clean: false);
        return;
      }
      if (_phase == _Phase.find) {
        setState(() {
          _phase = _Phase.found;
          _note = 'A positive move.';
          _dartAt = m.to;
        });
        _remember(solved: true, clean: true);
        return;
      }
      // выдержка: ход принят — мишень на нём, затем отвечает движок
      setState(() => _dartAt = m.to);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      _held++;
      await _engineReply();
    } catch (_) {
      if (mounted) setState(() => _note = 'The engine is not available.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        // та же позиция — только снова можно ходить; без сброса анимации
        _sync();
      }
    }
  }

  Future<void> _engineReply() async {
    final bot = await EngineBot.shared();
    final lines = await bot.analyse(_pos.fen, depth: 16, multipv: 1);
    if (!mounted || lines.isEmpty) {
      setState(() => _phase = _Phase.held);
      return;
    }
    final reply = Pos.move(lines.first.move);
    setState(() {
      _dartAt = null;
      _last = reply;
      _pos = _pos.push(reply);
    });
    _sync();
    // конец выдержки: тихая позиция, явный выигрыш (+3) или восемь ходов
    const s = Settings();
    final mine = await bot.analyse(_pos.fen, depth: 12, multipv: 1);
    if (!mounted) return;
    final value = mine.isEmpty ? 0.0 : mine.first.eval.pawns(s);
    var quiet = mine.isNotEmpty;
    var b = _pos;
    for (final uci in mine.isEmpty ? const <String>[] : mine.first.pv.take(4)) {
      final m = Pos.move(uci);
      if (!b.isLegal(m) || features.isForcing(b, m)) {
        quiet = false;
        break;
      }
      b = b.push(m);
    }
    if (_pos.p.isGameOver || value >= 3 || (quiet && _held >= 2) || _held >= 8) {
      setState(() {
        _phase = _Phase.held;
        _note = value >= 3
            ? 'Held: the position is clearly winning.'
            : (quiet ? 'Held: the position is quiet now.' : 'Held for $_held moves.');
      });
    }
  }

  void _survive() {
    setState(() {
      _phase = _Phase.survival;
      _note = 'The strongest engine answers. Keep playing positive moves.';
    });
    _busy = true;
    _engineReply().whenComplete(() {
      if (!mounted) return;
      setState(() => _busy = false);
      _sync();
    });
  }

  /// Plays a line on the board move by move, animated, from the position
  /// shown now when [from] is it (nothing is taken back first); then the
  /// line can be browsed back and forth.
  Future<void> _playLine(Pos from, List<NormalMove> line, {NormalMove? lastBefore}) async {
    final positions = <(Pos, NormalMove?)>[(from, lastBefore)];
    var b = from;
    for (final m in line) {
      if (!b.isLegal(m)) break;
      b = b.push(m);
      positions.add((b, m));
    }
    setState(() {
      _beforeReplay ??= (_pos, _last);
      _replay = positions;
      _replayAt = 0;
      _replaying = true;
      _dartAt = null;
      _pos = from;
      _last = lastBefore;
    });
    _sync();
    for (var i = 1; i < positions.length; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 750));
      if (!mounted || !_replaying || !identical(_replay, positions)) return;
      _showReplay(i);
    }
    if (mounted && identical(_replay, positions)) setState(() => _replaying = false);
  }

  void _showReplay(int i) {
    final r = _replay;
    if (r == null) return;
    final (pos, m) = r[i.clamp(0, r.length - 1)];
    setState(() {
      _replayAt = i.clamp(0, r.length - 1);
      _pos = pos;
      _last = m;
    });
    _sync();
  }

  /// Back to the board as it was before the line.
  void _closeReplay() {
    final b = _beforeReplay;
    setState(() {
      _replay = null;
      _replaying = false;
      _beforeReplay = null;
      if (b != null) {
        _pos = b.$1;
        _last = b.$2;
      }
    });
    _sync();
  }

  /// What the wrong move allows: the engine's best line after it, from the
  /// board as it is (the wrong move stays where it is).
  Future<void> _consequences() async {
    final from = _wrongFrom, m = _wrongMove;
    if (from == null || m == null) return;
    setState(() => _busy = true);
    try {
      final bot = await EngineBot.shared();
      final after = from.push(m);
      // анализ партии в фоне ждёт: движок нужен здесь
      final lines = await analysisQueue
          .priority(() => bot.analyse(after.fen, depth: 14, multipv: 1))
          .timeout(const Duration(seconds: 20));
      final pv = lines.isEmpty ? <NormalMove>[] : [for (final u in lines.first.pv.take(6)) Pos.move(u)];
      if (!mounted) return;
      setState(() => _busy = false);
      if (pv.isEmpty) return _engineBusy();
      await _playLine(after, pv, lastBefore: m);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        _engineBusy();
      }
    }
  }

  void _engineBusy() => ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
      content: Text('The consequences could not be computed: the engine did not answer. '
          'If a game is being analysed, try again in a moment.')));

  /// Why the game move was a mistake: the move, then the opponent's best
  /// line after it (from the analysis).
  void _whyGameMove() {
    final next = _ply + 1 < c.game.plies.length ? c.game.plies[_ply + 1] : null;
    final pv = next == null || next.lines.isEmpty ? const <String>[] : next.lines.first.pv.take(6);
    _playLine(c.before[_ply], [c.moves[_ply], ...pv.map(Pos.move)], lastBefore: _ply > 0 ? c.moves[_ply - 1] : null);
  }

  /// Foresight: the engine's line from the mistake's position.
  void _playEngineLine() {
    final line = c.game.plies[_ply].lines.first.pv.take(6).map(Pos.move).toList();
    _playLine(c.before[_ply], line, lastBefore: _ply > 0 ? c.moves[_ply - 1] : null);
  }

  void _undoPlan() {
    if (_plan.isEmpty) return;
    setState(() {
      _plan.removeLast();
      _pos = c.before[_ply];
      for (final m in _plan) {
        _pos = _pos.push(m);
      }
      _last = _plan.isEmpty ? null : _plan.last;
      _phase = _Phase.foresight;
    });
    _sync();
  }

  /// The player's chances (expected result) in the mistake's position.
  double get _chances {
    final r = c.analysis.records[_ply];
    return r.wdl.e1;
  }

  // --- предвидение ---

  void _planMove(NormalMove m) {
    setState(() {
      _plan.add(m);
      _last = m;
      _pos = _pos.push(m);
    });
    _sync();
    if (_plan.length >= 4) _judgePlan();
  }

  /// Compares the played plan with the engine's line by ideas: kinds of the
  /// moves, the pieces moved and the squares reached.
  void _judgePlan() {
    const s = Settings();
    final start = c.before[_ply];
    final line = c.game.plies[_ply].lines.first;
    final engine = [for (final u in line.pv.take(4)) Pos.move(u)];
    Set<String> ideas(List<NormalMove> seq) {
      final out = <String>{};
      var b = start;
      for (final m in seq) {
        if (!b.isLegal(m)) break;
        out.addAll(kindsOf(b, m, [m.uci], line.eval, s).where((k) => k != 'quiet' && k != 'capture'));
        out.add('${b.roleAt(m.from)?.name}->${m.to.name}');
        out.add('piece:${b.roleAt(m.from)?.name}');
        b = b.push(m);
      }
      return out;
    }

    final mine = ideas(_plan), theirs = ideas(engine);
    final common = mine.intersection(theirs);
    final share = theirs.isEmpty ? 0.0 : common.length / theirs.length;
    final exact = [
      for (var i = 0; i < math.min(_plan.length, engine.length); i++)
        if (_plan[i] == engine[i]) 1,
    ].length;
    var b = start;
    final sans = <String>[];
    for (final m in engine) {
      if (!b.isLegal(m)) break;
      sans.add(b.san(m));
      b = b.push(m);
    }
    final understood = share >= 0.5 || exact >= 2;
    _remember(solved: understood, clean: understood, share: share);
    setState(() {
      _phase = _Phase.judged;
      _note =
          '${understood ? 'Understood' : 'Not quite'}: ${(share * 100).round()}% of the ideas match '
          '($exact exact moves). The engine: ${sans.join(' ')}.';
    });
  }

  /// The dartboard over a square (as in the puzzles).
  Widget _dartOver(Square s, double size) {
    final sq = size / 8;
    final white = c.before[_ply].turn == Side.white;
    final x = white ? s.file : 7 - s.file;
    final y = white ? 7 - s.rank : s.rank;
    final d = sq * 0.51;
    final atRight = x == 7, atTop = y == 0;
    final cx = atRight ? x * sq + d * 0.06 : (x + 1) * sq - d * 0.06;
    final cy = atTop ? (y + 1) * sq - d * 0.06 : y * sq + d * 0.06;
    return Positioned(
      left: cx - d * 0.8,
      top: cy - d * 0.8,
      width: d * 1.6,
      height: d * 1.6,
      child: IgnorePointer(
        child: Center(
          child: DartHit(key: ValueKey('$s-$_held'), size: d),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_tasks.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Start to improve')),
        body: const Center(child: Text('No mistakes to work on in this game.')),
      );
    }
    final r = c.analysis.records[_ply];
    return Scaffold(
      appBar: AppBar(
        title: Text('Mistake ${_task + 1} of ${_tasks.length}'),
        actions: [
          IconButton(
            tooltip: 'Previous',
            onPressed: _task > 0 ? () => _open(_task - 1) : null,
            icon: const Icon(Icons.skip_previous_rounded),
          ),
          IconButton(
            tooltip: 'Next',
            onPressed: _task + 1 < _tasks.length ? () => _open(_task + 1) : null,
            icon: const Icon(Icons.skip_next_rounded),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, box) {
          final size = math.min(box.maxWidth - 24, math.min(520.0, box.maxHeight * 0.55));
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              SegmentedButton<ImproveMode>(
                segments: const [
                  ButtonSegment(
                    value: ImproveMode.fix,
                    label: Text('Fix and survive'),
                    icon: Icon(Icons.healing_rounded),
                  ),
                  ButtonSegment(
                    value: ImproveMode.foresight,
                    label: Text('Foresight'),
                    icon: Icon(Icons.visibility_rounded),
                  ),
                ],
                selected: {_mode},
                showSelectedIcon: false,
                onSelectionChanged: (s) {
                  _mode = s.first;
                  _open(_task);
                },
              ),
              const SizedBox(height: 10),
              Center(
                child: SizedBox.square(
                  dimension: size,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Chessboard(
                        size: size,
                        controller: _board,
                        orientation: c.before[_ply].turn,
                        onMove: (m, {viaDragAndDrop}) {
                          if (m is NormalMove) _onMove(m);
                        },
                        settings: ChessboardSettings(
                          colorScheme: appScheme(
                            _board,
                            lastMove: _phase == _Phase.wrong || _phase == _Phase.lost ? const Color(0x99E53935) : null,
                          ),
                          pieceAssets: prefs.pieceSet.assets,
                          animationDuration: Duration(milliseconds: prefs.moveAnimationMs),
                          borderRadius: const BorderRadius.all(Radius.circular(6)),
                        ),
                      ),
                      if (_dartAt != null && _replay == null) _dartOver(_dartAt!, size),
                    ],
                  ),
                ),
              ),
              // листание показанной линии
              if (_replay != null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Previous move',
                      onPressed: _replaying || _replayAt == 0 ? null : () => _showReplay(_replayAt - 1),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Text('$_replayAt / ${_replay!.length - 1}', style: TextStyle(color: scheme.outline)),
                    IconButton(
                      tooltip: 'Next move',
                      onPressed: _replaying || _replayAt >= _replay!.length - 1
                          ? null
                          : () => _showReplay(_replayAt + 1),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: _closeReplay,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Close'),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  StepIcon(kind: r.step, size: 26),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '${plyText(r.ply)} ${r.san} was a ${stepLabels[r.step]!.toLowerCase()}. '
                      '${switch (_phase) {
                        _Phase.find || _Phase.wrong => 'Find a better move.',
                        _Phase.foresight => 'Play the plan of both sides: ${4 - _plan.length} plies left.',
                        _ => '',
                      }}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  // после исправления — почему ход партии был ошибкой
                  if (_mode == ImproveMode.fix &&
                      (_phase == _Phase.found || _phase == _Phase.held || _phase == _Phase.lost))
                    IconButton(
                      tooltip: 'Why the game move was a mistake',
                      visualDensity: VisualDensity.compact,
                      onPressed: _replaying ? null : _whyGameMove,
                      icon: Icon(Icons.account_tree_rounded, color: scheme.primary),
                    ),
                ],
              ),
              if (_historyText() case final h?)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(h, style: TextStyle(fontSize: 12, color: scheme.outline)),
                ),
              if (_busy) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator()),
              if (_note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _note,
                    style: TextStyle(
                      color: _phase == _Phase.wrong || _phase == _Phase.lost ? scheme.error : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              // лучший ход — в свёртке с красным заголовком, как источник в задачах
              if (_better != null)
                InkWell(
                  onTap: () => setState(() => _showBetter = !_showBetter),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      layoutBuilder: (cur, prev) => Stack(alignment: Alignment.centerLeft, children: [...prev, ?cur]),
                      child: Text(
                        _showBetter ? 'Better was $_better' : 'Show the better move',
                        key: ValueKey(_showBetter),
                        style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (_phase == _Phase.wrong || _phase == _Phase.lost || _phase == _Phase.judged)
                    FilledButton.icon(
                      onPressed: () => _open(_task, keepRecord: true),
                      icon: const Icon(Icons.replay_rounded),
                      label: const Text('Again'),
                    ),
                  if ((_phase == _Phase.wrong || _phase == _Phase.lost) && _wrongMove != null)
                    OutlinedButton.icon(
                      onPressed: _busy || _replaying ? null : _consequences,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Show the consequences'),
                    ),
                  // выживать в почти проигранной позиции (≥ 80% у соперника) смысла мало
                  if (_phase == _Phase.found && _chances > 0.2)
                    FilledButton.icon(
                      onPressed: _survive,
                      icon: const Icon(Icons.shield_rounded),
                      label: const Text('Survive against the engine'),
                    ),
                  if (_phase == _Phase.foresight && _plan.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: _undoPlan,
                      icon: const Icon(Icons.undo_rounded),
                      label: const Text('Take back'),
                    ),
                  if (_mode == ImproveMode.foresight)
                    OutlinedButton.icon(
                      onPressed: _replaying ? null : _playEngineLine,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text("Play the engine's line"),
                    ),
                  if (_phase != _Phase.find &&
                      _phase != _Phase.survival &&
                      _phase != _Phase.foresight &&
                      _task + 1 < _tasks.length)
                    OutlinedButton.icon(
                      onPressed: () => _open(_task + 1),
                      icon: const Icon(Icons.skip_next_rounded),
                      label: const Text('Next mistake'),
                    ),
                  // круглая кнопка: разобрать позицию на доске анализа
                  IconButton.filledTonal(
                    tooltip: 'Analyse this position',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AnalysisBoardScreen(
                          startFen: c.before[_ply].fen,
                          title: 'Mistake: ${plyText(_ply)} ${r.san}',
                          temporary: true,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.biotech_outlined),
                  ),
                ],
              ),
              if (_phase == _Phase.found && _chances <= 0.2)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Survival is left out here: the position was already lost (80% or more for the opponent).',
                    style: TextStyle(fontSize: 12, color: scheme.outline),
                  ),
                ),
              // после ошибки или решения — отметить позицию как непонятую
              if (_phase != _Phase.find && _phase != _Phase.survival && _phase != _Phase.foresight)
                ListenableBuilder(
                  listenable: underlines,
                  builder: (context, _) {
                    final on = underlines.has(c.game.id, _ply);
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => underlines.toggle(c.game.id, _ply),
                        icon: Icon(on ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, size: 18),
                        label: Text(on ? 'Underlined: not clear to me' : 'Underline: not clear to me why'),
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}
