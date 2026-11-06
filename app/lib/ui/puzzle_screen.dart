/// Puzzles: a start screen (what the puzzles are, start, the recorded
/// attempts) and the solving screen. Find the move, and the next ones, from
/// the engine's line. A solved puzzle ends with the dartboard over the last
/// moved piece: a dart flies into its centre and the board lights up. Then the
/// result can be recorded, the puzzle tried again, the position opened on the
/// analysis board, or the next puzzle taken.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:chessground/chessground.dart' as cg;
import 'package:chessground/chessground.dart' hide GameData;
import 'package:dartchess/dartchess.dart' hide Board;
import 'package:flutter/material.dart';

import '../analysis/game.dart';
import '../analysis/openings.dart';
import '../analysis/pgn_import.dart' show normalizeCastling;
import '../analysis/pos.dart';
import '../analysis/weakness.dart' show similarity;
import '../engine/bot.dart';
import '../engine/game_job.dart' show JobState;
import '../engine/puzzle_rater.dart';
import 'board_screen.dart';
import 'analysis_cache.dart';
import 'analysis_queue.dart';
import 'history_store.dart';
import 'prefs.dart';
import 'player_stats.dart' show collectStats;
import 'puzzles.dart';
import 'step_icons.dart' show StepIcon;
import 'widgets/board_background.dart';
import 'widgets/board_view.dart' show FlyOutPainter;

/// Start screen of the puzzles.
class PuzzleHomeScreen extends StatefulWidget {
  const PuzzleHomeScreen({super.key, required this.games, required this.book});

  final List<GameData> games;
  final OpeningBook book;

  @override
  State<PuzzleHomeScreen> createState() => _PuzzleHomeScreenState();
}

class _PuzzleHomeScreenState extends State<PuzzleHomeScreen> {
  List<Puzzle>? _puzzles;
  List<PuzzleAttempt> _attempts = [];
  Map<String, int> _ratings = {};
  Map<String, double> _profile = {};

  @override
  void initState() {
    super.initState();
    prefs.addListener(_rebuild);
    _load();
  }

  @override
  void dispose() {
    prefs.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  Future<void> _load() async {
    // тяжёлый разбор партий — после анимации перехода, чтобы она не дёргалась
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final list = <Puzzle>[];
    for (final g in widget.games) {
      list.addAll(puzzlesFrom(await analysisOf(g, widget.book)));
    }
    // разборы своих партий из истории (законченные)
    await history.load();
    // свои партии дают задачи сразу после быстрого прохода
    final own = <GameAnalysis>[];
    for (final e in history.entries) {
      final job = await history.open(e.id);
      if (job == null || !job.ready) continue;
      own.add(await analysisOf(job.snapshot(), widget.book));
      // партия без задач — только для профиля слабостей
      if (job.puzzles) list.addAll(puzzlesFrom(own.last));
    }
    // профиль слабостей — по своим ошибкам (для «Consider weaknesses»)
    final stats = await collectStats(own, puzzles: list);
    _profile = stats.profile;
    final attempts = await PuzzleHistory.load();
    final ratings = await PuzzleRatings.load();
    list.shuffle(math.Random(DateTime.now().day));
    if (!mounted) return;
    setState(() {
      _puzzles = list;
      _attempts = attempts;
      _ratings = ratings;
    });
    _rateRest(list);
  }

  /// Puzzles the analysis has not rated yet (the showcase games, analyses
  /// made before the rating) are rated in the background while the screen
  /// is open and no analysis is running.
  Future<void> _rateRest(List<Puzzle> list) async {
    if (!prefs.estimatePuzzleRating) return;
    final busy = analysisQueue.ratingPuzzles || analysisQueue.jobs.any((j) => j.state == JobState.running);
    if (busy) return;
    await ratePuzzles(list, cancelled: () => !mounted || analysisQueue.jobs.any((j) => j.state == JobState.running));
    final ratings = await PuzzleRatings.load();
    if (mounted) setState(() => _ratings = ratings);
  }

  int _ratingOf(Puzzle p) => _ratings[p.id] ?? quickRating(p);

  Set<String> get _solvedIds {
    final ids = {for (final p in _puzzles ?? const <Puzzle>[]) p.id};
    return {for (final a in _attempts) if (a.solved && ids.contains(a.id)) a.id};
  }

  /// How many puzzles there are at each rating (400…3000, by hundreds), the
  /// solved ones darker.
  void _histogram() {
    final list = _puzzles ?? const <Puzzle>[];
    final solved = _solvedIds;
    final all = List.filled(27, 0), done = List.filled(27, 0);
    for (final p in list) {
      final i = ((_ratingOf(p) - 400) ~/ 100).clamp(0, 26);
      all[i]++;
      if (solved.contains(p.id)) done[i]++;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Puzzles by rating', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('${solved.length} of ${list.length} solved · the dark part of a bar is solved',
                style: TextStyle(color: scheme.outline, fontSize: 13)),
            const SizedBox(height: 16),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, t, _) => CustomPaint(
                size: const Size(double.infinity, 160),
                painter: _HistogramPainter(all, done, t, scheme, prefs.puzzleAutoRating ? autoRating(_attempts) : prefs.puzzleTarget),
              ),
            ),
            const SizedBox(height: 6),
            Row(children: [
              for (final r in ['400', '1000', '1600', '2200', '2800'])
                Expanded(child: Text(r, style: TextStyle(fontSize: 11, color: scheme.outline))),
            ]),
          ]),
        );
      },
    );
  }

  /// Puzzles of the chosen rating (its hundred) first, then the nearest
  /// easier ones, the harder ones last; solved ones after all the rest.
  List<Puzzle> _ordered() {
    final target = prefs.puzzleAutoRating ? autoRating(_attempts) : prefs.puzzleTarget;
    final top = target ~/ 100 * 100 + 99;
    final solved = {for (final a in _attempts) if (a.solved) a.id};
    final weak = prefs.weaknessPuzzles && _profile.isNotEmpty;
    int key(Puzzle p) {
      final r = _ratingOf(p);
      final band = r <= top ? (top - r) ~/ 100 : 100 + r ~/ 100;
      // в пределах сотни рейтинга — сначала похожие на свои ошибки
      final like = weak ? (similarity(p.tags, _profile) * 10).round().clamp(0, 999) : 0;
      return (solved.contains(p.id) ? 1000000 : 0) + band * 1000 + (999 - like);
    }

    return [..._puzzles!]..sort((a, b) => key(a) - key(b));
  }

  Future<void> _start() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PuzzleScreen(puzzles: _ordered())));
    final attempts = await PuzzleHistory.load();
    final ratings = await PuzzleRatings.load();
    if (mounted) {
      setState(() {
        _attempts = attempts;
        _ratings = ratings;
      });
    }
  }

  void _info() {
    final list = _puzzles;
    final counts = {for (final g in PuzzleGoal.values) g: list?.where((p) => p.goal == g).length ?? 0};
    showDialog<void>(
      context: context,
      builder: (context) {
        final style = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
        return AlertDialog(
          title: const Text('About the puzzles'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  'Puzzles come from the games you have analysed: the showcase games and the finished analyses in '
                  'your history. Each one is a position where a single move stands out.',
                  style: style),
              const SizedBox(height: 8),
              Text(
                  'Not only attacks: some ask you to mate, win material or gain an advantage, others to hold — the '
                  'only defence that keeps the balance, stalemate and perpetual check included. The solution goes on '
                  'as long as the tactic does.',
                  style: style),
              const SizedBox(height: 8),
              Text(
                  'Puzzles of the chosen rating come first; if there are none, the nearest easier ones. Until the '
                  'engine has judged a puzzle its rating is a quick guess.',
                  style: style),
              if (list != null) ...[
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  for (final e in counts.entries)
                    Chip(visualDensity: VisualDensity.compact, label: Text('${_goalTitle(e.key)}: ${e.value}')),
                ]),
              ],
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final list = _puzzles;
    final hits = _attempts.where((a) => a.solved).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Puzzles')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          const SizedBox(width: 56, height: 56, child: CustomPaint(painter: DartboardPainter())),
          const SizedBox(width: 14),
          Expanded(child: Text('Find the move', style: theme.textTheme.headlineSmall)),
          IconButton(onPressed: _info, tooltip: 'About the puzzles', icon: const Icon(Icons.info_outline_rounded)),
        ]),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: Text('Rating', style: theme.textTheme.titleMedium)),
          // решено / всего — по нажатию распределение задач по рейтингу
          if (list != null)
            TextButton.icon(
              onPressed: _histogram,
              icon: const Icon(Icons.bar_chart_rounded, size: 18),
              label: Text('${_solvedIds.length}/${list.length}'),
            ),
        ]),
        IgnorePointer(
          ignoring: prefs.puzzleAutoRating,
          child: AnimatedOpacity(
            opacity: prefs.puzzleAutoRating ? 0.5 : 1,
            duration: const Duration(milliseconds: 200),
            child: RatingSlider(
                value: prefs.puzzleAutoRating ? autoRating(_attempts) : prefs.puzzleTarget,
                onChanged: (v) => prefs.update(target: v)),
          ),
        ),
        // автоматически: рейтинг идёт за результатами (по записанным попыткам)
        SizedBox(
          width: double.infinity,
          child: prefs.puzzleAutoRating
              ? FilledButton.icon(
                  onPressed: () => prefs.update(autoRating: false),
                  icon: const Icon(Icons.auto_mode_rounded, size: 18),
                  label: const Text('Rating by your results · tap to choose'),
                )
              : OutlinedButton.icon(
                  onPressed: () => prefs.update(autoRating: true),
                  icon: const Icon(Icons.auto_mode_rounded, size: 18),
                  label: const Text('Choose the rating automatically'),
                ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Consider weaknesses'),
          subtitle: Text(_profile.isEmpty
              ? 'Analyse your games: puzzles like your mistakes will come first'
              : 'Puzzles like your mistakes come first (colour, stage, missed move, cost)'),
          value: prefs.weaknessPuzzles,
          onChanged: (v) => prefs.update(weakness: v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Estimate puzzle rating'),
          subtitle: const Text('The engine judges how hard each puzzle is while you solve it'),
          value: prefs.estimatePuzzleRating,
          onChanged: (v) => prefs.update(puzzleRating: v),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: list == null || list.isEmpty ? null : _start,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(list == null ? 'Loading…' : (list.isEmpty ? 'No puzzles yet' : 'Start to solve')),
          ),
        ),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(child: Text('Recorded attempts', style: theme.textTheme.titleMedium)),
          if (_attempts.isNotEmpty) Text('$hits hits · ${_attempts.length - hits} misses', style: TextStyle(color: scheme.outline)),
        ]),
        const SizedBox(height: 6),
        if (_attempts.isEmpty)
          Text('Nothing recorded yet. Solved puzzles are recorded as hits; after a mistake you can save the miss.',
              style: TextStyle(color: scheme.outline, fontSize: 13)),
        for (final a in _attempts)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: a.solved
                ? const SizedBox(width: 28, height: 28, child: CustomPaint(painter: DartboardPainter()))
                : Icon(Icons.close_rounded, color: scheme.error),
            title: Text(a.source, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text([
              a.solved ? 'Hit' : 'Miss',
              if (a.rating != null) 'rating ${a.rating}',
              a.date.toLocal().toString().substring(0, 16),
            ].join(' · ')),
          ),
      ]),
    );
  }
}

String _goalTitle(PuzzleGoal g) => switch (g) {
      PuzzleGoal.mate => 'Mate',
      PuzzleGoal.win => 'Win',
      PuzzleGoal.advantage => 'Advantage',
      PuzzleGoal.defend => 'Defence',
    };

enum _State { solving, wrong, solved, shown }

class PuzzleScreen extends StatefulWidget {
  const PuzzleScreen({super.key, required this.puzzles});

  final List<Puzzle> puzzles;

  @override
  State<PuzzleScreen> createState() => _PuzzleScreenState();
}

class _PuzzleScreenState extends State<PuzzleScreen> {
  int _index = 0;
  int _step = 0;
  _State _state = _State.solving;
  bool _recorded = false;

  /// A wrong move was played in this try: the position it was played in and
  /// its index in the solution (saved as a miss on request).
  bool _erred = false;
  int? _errStep;
  String? _errFen;
  bool _showSource = false;
  int? _rating;
  bool _ratingBusy = false;
  Map<String, int> _ratings = {};
  Pos _pos = Pos(Chess.initial);
  NormalMove? _last;

  /// The line being followed: the puzzle's solution or an accepted
  /// alternative.
  List<String> _line = const [];

  /// The engine is checking a move off the line.
  bool _checking = false;
  late final ChessboardController _board = ChessboardController(game: _gameData());
  Timer? _reply;

  List<Puzzle> get _puzzles => widget.puzzles;
  Puzzle get p => _puzzles[_index];

  @override
  void initState() {
    super.initState();
    PuzzleRatings.load().then((m) {
      _ratings = m;
      if (mounted) _start(0);
    });
  }

  @override
  void dispose() {
    _intro?.cancel();
    _reply?.cancel();
    _board.dispose();
    super.dispose();
  }

  cg.GameData _gameData() => cg.GameData(
        fen: _pos.fen,
        lastMove: _last,
        playerSide: _state == _State.solving && !_checking && !_peek && _puzzles.isNotEmpty && _pos.turn == p.solver
            ? (_pos.turn == Side.white ? PlayerSide.white : PlayerSide.black)
            : PlayerSide.none,
        sideToMove: _pos.turn,
        kingSquareInCheck: null,
        validMoves: makeLegalMoves(_pos.p),
      );

  void _sync({bool animate = true}) {
    // живая позиция: просмотр по стрелкам заканчивается
    _view = null;
    _board.updatePosition(_gameData(), animate: animate);
    syncCheck(_board, inCheck: _pos.isCheck, king: _pos.king(_pos.turn));
  }

  /// Looking at the position before the opponent's last move.
  bool _peek = false;

  /// The solver's last correct move: a best-move badge on its square until
  /// the opponent answers.
  Square? _bestAt;
  Timer? _intro;

  /// Positions of this try, oldest first: before the opponent's last move,
  /// the puzzle's start, then after each move played (the wrong one too).
  List<(Pos, NormalMove?)> get _trail {
    final out = <(Pos, NormalMove?)>[];
    if (p.prevFen != null) out.add((Pos.fromFen(p.prevFen!), null));
    var pos = Pos.fromFen(p.fen);
    out.add((pos, p.prevMove != null ? NormalMove.fromUci(p.prevMove!) : null));
    for (final uci in _line.take(_step)) {
      final m = NormalMove.fromUci(uci);
      if (!pos.isLegal(m)) break;
      pos = pos.push(m);
      out.add((pos, m));
    }
    if (_pos.fen != pos.fen) out.add((_pos, _last));
    return out;
  }

  /// The position looked at with the arrows (null: the live one).
  int? _view;

  /// One move back or forward through [_trail]; at its end the board is live
  /// again.
  void _step1(int d) {
    final trail = _trail;
    final i = ((_view ?? trail.length - 1) + d).clamp(0, trail.length - 1);
    if (i == trail.length - 1) {
      setState(() {
        _view = null;
        _peek = false;
      });
      _sync();
      return;
    }
    final (pos, m) = trail[i];
    setState(() {
      _view = i;
      _peek = true;
    });
    _board.updatePosition(
        cg.GameData(
          fen: pos.fen,
          lastMove: m,
          playerSide: PlayerSide.none,
          sideToMove: pos.turn,
          kingSquareInCheck: null,
          validMoves: makeLegalMoves(pos.p),
        ),
        animate: true);
  }

  void _showPrev(bool on) {
    if (p.prevFen == null) return;
    setState(() => _peek = on);
    if (on) {
      final prev = Pos.fromFen(p.prevFen!);
      _board.updatePosition(
          cg.GameData(
            fen: prev.fen,
            lastMove: null,
            playerSide: PlayerSide.none,
            sideToMove: prev.turn,
            kingSquareInCheck: null,
            validMoves: makeLegalMoves(prev.p),
          ),
          animate: true);
    } else {
      _sync();
    }
  }

  void _start(int i) {
    _reply?.cancel();
    _intro?.cancel();
    setState(() {
      _peek = false;
      _view = null;
      _bestAt = null;
      _index = i % _puzzles.length;
      _step = 0;
      _state = _State.solving;
      _recorded = false;
      _erred = false;
      _errStep = null;
      _errFen = null;
      _showSource = false;
      _pos = Pos.fromFen(p.fen);
      _last = null;
      _line = p.solution;
      _checking = false;
      _rating = _ratings[p.id];
      _last = p.prevMove != null ? NormalMove.fromUci(p.prevMove!) : null;
    });
    // задача начинается с хода соперника: сначала позиция до него, затем ход
    if (p.prevFen != null) {
      _showPrev(true);
      _intro = Timer(const Duration(milliseconds: 650), () {
        if (mounted) _showPrev(false);
      });
    } else {
      _sync(animate: false);
    }
    _estimate();
  }

  /// Rates the puzzle in the background while it is being solved.
  Future<void> _estimate() async {
    if (!prefs.estimatePuzzleRating || _rating != null || _ratingBusy) return;
    final puzzle = p;
    _ratingBusy = true;
    try {
      final r = await estimateRating(puzzle, cancelled: () => !mounted || !identical(puzzle, p));
      _ratings[puzzle.id] = r;
      await PuzzleRatings.save(puzzle.id, r);
      if (mounted && identical(puzzle, p)) setState(() => _rating = r);
    } catch (_) {
      // отменено (следующая задача) или движок недоступен
    } finally {
      _ratingBusy = false;
    }
  }

  void _onMove(NormalMove m) {
    if (_state != _State.solving || _checking) return;
    m = normalizeCastling(_pos, m);
    if (m.uci == _line[_step]) return _accept();
    // другая линия анализа с тем же началом
    final played = [..._line.take(_step), m.uci];
    for (final s in p.solutions) {
      if (s.length > _step && _listEq(s.take(_step + 1).toList(), played)) {
        _line = s;
        return _accept();
      }
    }
    if (p.goal == PuzzleGoal.defend) return _wrong(m);
    _checkWithEngine(m);
  }

  static bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _wrong(NormalMove m) {
    // неверный ход: показываем его и отмечаем промах
    setState(() {
      if (!_erred) {
        _erred = true;
        _errStep = _step;
        _errFen = _pos.fen;
      }
      _last = m;
      _pos = _pos.push(m);
      _state = _State.wrong;
      _checking = false;
    });
    _sync();
  }

  /// A move off the line in an attack puzzle: the engine decides whether it
  /// keeps the goal; if so the puzzle goes on along the engine's line.
  Future<void> _checkWithEngine(NormalMove m) async {
    final puzzle = p;
    final before = _pos;
    final after = before.push(m);
    setState(() {
      _checking = true;
      _last = m;
      _pos = after;
    });
    _sync();
    List<String>? tail;
    if (after.p.isCheckmate) {
      tail = [];
    } else {
      try {
        final bot = await EngineBot.shared();
        final lines = await bot.analyse(after.fen, depth: 14, multipv: 1);
        if (lines.isNotEmpty && puzzle.keepsGoal(lines.first.eval)) tail = tacticTail(after, lines.first.pv);
      } catch (_) {}
    }
    if (!mounted || !identical(puzzle, p) || !_checking) return;
    // ход вернулся на позицию до проверки — дальше как с обычным ходом
    _pos = before;
    _last = _step > 0 ? NormalMove.fromUci(_line[_step - 1]) : null;
    _checking = false;
    if (tail == null) return _wrong(m);
    _line = [..._line.take(_step), m.uci, ...tail];
    _accept();
  }

  void _accept() {
    _advance();
    if (_step >= _line.length) {
      setState(() {
        _state = _State.solved;
        _showSource = true;
      });
      _sync();
      // решено с первой попытки — попадание записывается само
      if (!_erred && !_recorded) _record(true);
      return;
    }
    _sync();
    // ответ соперника — с небольшой паузой
    _reply = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      _advance();
      _sync();
    });
  }

  void _advance() {
    final m = NormalMove.fromUci(_line[_step]);
    setState(() {
      // ход решающего — значок best; ответ соперника его снимает
      _bestAt = _pos.turn == p.solver ? m.to : null;
      _last = m;
      _pos = _pos.push(m);
      _step++;
    });
  }

  /// Back to the position before the wrong move; the pieces slide back.
  void _retry() {
    setState(() {
      _pos = Pos.fromFen(p.fen);
      for (final uci in _line.take(_step)) {
        _pos = _pos.push(NormalMove.fromUci(uci));
      }
      _last = _step > 0 ? NormalMove.fromUci(_line[_step - 1]) : null;
      _state = _State.solving;
    });
    _sync();
  }

  Future<void> _showSolution() async {
    _retry();
    setState(() {
      _state = _State.shown;
      _showSource = true;
    });
    while (_step < _line.length && mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!mounted) return;
      _advance();
      _sync();
    }
  }

  Future<void> _record(bool solved) async {
    await PuzzleHistory.add(PuzzleAttempt(p.id, p.source, solved, DateTime.now(),
        rating: _rating, goal: goalLabels[p.goal], step: solved ? null : _errStep, fen: solved ? null : _errFen));
    if (mounted) setState(() => _recorded = true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_puzzles.isEmpty) {
      return Scaffold(appBar: AppBar(title: const Text('Puzzles')), body: const Center(child: Text('No puzzles.')));
    }
    return Scaffold(
      appBar: AppBar(title: Text('Puzzle ${_index + 1} of ${_puzzles.length}'), actions: [
        IconButton(
          tooltip: 'Previous puzzle',
          onPressed: _index > 0 ? () => _start(_index - 1) : null,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
      ]),
      body: LayoutBuilder(builder: (context, box) {
        final size = math.min(box.maxWidth - 24, math.min(520.0, box.maxHeight * 0.6));
        return Column(children: [
          const SizedBox(height: 12),
          Center(
            child: SizedBox.square(
              dimension: size,
              child: Stack(clipBehavior: Clip.none, children: [
                Chessboard(
                  size: size,
                  controller: _board,
                  orientation: p.solver,
                  onMove: (m, {viaDragAndDrop}) {
                    if (m is NormalMove) _onMove(m);
                  },
                  settings: ChessboardSettings(
                    // неверный ход — красные клетки под ним
                    colorScheme: appScheme(_board, lastMove: _state == _State.wrong ? const Color(0x99E53935) : null),
                    pieceAssets: prefs.pieceSet.assets,
                    animationDuration: Duration(milliseconds: prefs.moveAnimationMs),
                    borderRadius: const BorderRadius.all(Radius.circular(6)),
                    boxShadow: kElevationToShadow[3]!,
                  ),
                ),
                if (_state == _State.solved && _last != null && !_peek) _dartOver(_last!.to, size),
                if (_bestAt != null && _state != _State.solved && !_peek)
                  _corner(_bestAt!, size, (d) => StepIcon(kind: 'best', size: d)),
              ]),
            ),
          ),
          // в углу под доской: на ход назад и вперёд по сыгранному в задаче
          if (_trail.length > 1)
            SizedBox(
              width: size,
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                IconButton(
                  tooltip: 'One move back',
                  visualDensity: VisualDensity.compact,
                  onPressed: (_view ?? _trail.length - 1) > 0 ? () => _step1(-1) : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                IconButton(
                  tooltip: 'One move forward',
                  visualDensity: VisualDensity.compact,
                  onPressed: _view != null ? () => _step1(1) : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ]),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeInOutCubic,
                alignment: Alignment.topLeft,
                child: _panel(context, scheme),
              ),
            ),
          ),
        ]);
      }),
    );
  }

  /// A badge of [d] px in the corner of square [s], placed like the move
  /// badges of the analysis board.
  Widget _corner(Square s, double size, Widget Function(double d) child) {
    final sq = size / 8;
    final white = p.solver == Side.white;
    final x = white ? s.file : 7 - s.file;
    final y = white ? 7 - s.rank : s.rank;
    final d = sq * 0.51;
    final atRight = x == 7, atTop = y == 0;
    final cx = atRight ? x * sq + d * 0.06 : (x + 1) * sq - d * 0.06;
    final cy = atTop ? (y + 1) * sq - d * 0.06 : y * sq + d * 0.06;
    return Positioned(
      left: cx - d / 2,
      top: cy - d / 2,
      width: d,
      height: d,
      child: IgnorePointer(child: child(d)),
    );
  }

  /// A small dartboard in the corner of the last move's square, placed like
  /// the move badges of the analysis board.
  Widget _dartOver(Square s, double size) {
    final sq = size / 8;
    final white = p.solver == Side.white;
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
      child: IgnorePointer(child: Center(child: DartHit(size: d))),
    );
  }

  Widget _panel(BuildContext context, ColorScheme scheme) {
    final who = p.solver == Side.white ? 'White' : 'Black';
    final title = switch (_state) {
      _State.solving => _checking ? 'Checking…' : '$who to move',
      _State.wrong => 'Not this one',
      _State.solved => 'Solved!',
      _State.shown => 'Solution',
    };
    final finished = _state == _State.solved || _state == _State.shown;
    // рейтинг — только в конце: до этого он подсказка
    final rating = _rating ?? (prefs.estimatePuzzleRating ? null : quickRating(p));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
        AnimatedOpacity(
          opacity: finished ? 1 : 0,
          duration: const Duration(milliseconds: 250),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (rating == null)
              const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
            else
              Text('Rating $rating', style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
          ]),
        ),
      ]),
      // источник может подсказать — скрыт до конца задачи
      InkWell(
        onTap: () => setState(() => _showSource = !_showSource),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: SizedBox(
            width: double.infinity,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              layoutBuilder: (current, previous) =>
                  Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
              child: Text(_showSource ? p.source : 'Source hidden',
                  key: ValueKey(_showSource), style: TextStyle(color: scheme.outline, fontSize: 13)),
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      if (_state == _State.wrong)
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(onPressed: _retry, icon: const Icon(Icons.replay_rounded), label: const Text('Try again')),
          OutlinedButton.icon(
              onPressed: _showSolution, icon: const Icon(Icons.visibility_outlined), label: const Text('Show solution')),
        ]),
      // предложение записать — исчезает плавно, кнопки ниже поднимаются
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        transitionBuilder: (w, a) => FadeTransition(opacity: a, child: SizeTransition(sizeFactor: a, child: w)),
        // позиция сохраняется только после ошибки — та, где был неверный ход
        child: _erred && !_recorded && _state != _State.solving
            ? Padding(
                key: const ValueKey('record'),
                padding: const EdgeInsets.only(top: 8, bottom: 12),
                child: OutlinedButton.icon(
                  onPressed: () => _record(false),
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: const Text('Save result after mistake'),
                ),
              )
            : const SizedBox(width: double.infinity, key: ValueKey('none')),
      ),
      if (finished)
        Row(children: [
          FilledButton.icon(
              onPressed: () => _start(_index + 1), icon: const Icon(Icons.skip_next_rounded), label: const Text('Next puzzle')),
          const SizedBox(width: 8),
          IconButton.outlined(tooltip: 'Again', onPressed: () => _start(_index), icon: const Icon(Icons.replay_rounded)),
          const SizedBox(width: 4),
          IconButton.outlined(
            tooltip: 'Analyze position',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => AnalysisBoardScreen(startFen: p.fen, title: 'Puzzle: ${p.source}', temporary: true))),
            icon: const Icon(Icons.biotech_outlined),
          ),
        ]),
      if (_state == _State.solving)
        TextButton.icon(onPressed: () => _start(_index + 1), icon: const Icon(Icons.skip_next_rounded), label: const Text('Skip')),
    ]);
  }
}

/// Rating picker: a slider in steps of a hundred with the value in a bubble
/// above the thumb; tapping the bubble lets you type an exact rating.
class RatingSlider extends StatelessWidget {
  const RatingSlider({super.key, required this.value, required this.onChanged});

  static const min = 400, max = 3000;

  final int value;
  final ValueChanged<int> onChanged;

  Future<void> _type(BuildContext context) async {
    final field = TextEditingController(text: '$value');
    final v = await showDialog<int>(
      context: context,
      builder: (context) {
        void done() => Navigator.pop(context, int.tryParse(field.text.trim()));
        return AlertDialog(
          title: const Text('Puzzle rating'),
          content: TextField(
            controller: field,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(helperText: 'From $min to $max'),
            onSubmitted: (_) => done(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(onPressed: done, child: const Text('OK')),
          ],
        );
      },
    );
    field.dispose();
    if (v != null) onChanged(v.clamp(min, max));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, box) {
      // дорожка — от края до края, вровень с кнопкой Auto под ней
      const pad = 0.0;
      final f = (value - min) / (max - min);
      final x = pad + f * (box.maxWidth - 2 * pad);
      return SizedBox(
        height: 84,
        child: Stack(children: [
          Positioned(
            left: (x - 36).clamp(0, box.maxWidth - 72),
            top: 0,
            width: 72,
            height: 32,
            child: Material(
              color: scheme.primaryContainer,
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => _type(context),
                child: Center(
                  child: Text('$value',
                      style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 36,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(padding: EdgeInsets.zero),
              child: Slider(
                min: min.toDouble(),
                max: max.toDouble(),
                divisions: (max - min) ~/ 100,
                value: value.toDouble(),
                onChanged: (v) => onChanged((v / 100).round() * 100),
              ),
            ),
          ),
        ]),
      );
    });
  }
}

/// The dartboard: red and white rings ([mono]: outline rings in [color], for
/// menus).
class DartboardPainter extends CustomPainter {
  const DartboardPainter({this.wobble = 0, this.mono = false, this.color = const Color(0xFFFFFFFF)});

  final double wobble;
  final bool mono;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final c = size.center(Offset.zero) + Offset(wobble * r * 0.04, 0);
    if (mono) {
      final stroke = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.16;
      canvas.drawCircle(c, r * 0.9, stroke);
      canvas.drawCircle(c, r * 0.5, stroke);
      canvas.drawCircle(c, r * 0.14, Paint()..color = color);
      return;
    }
    const red = Color(0xFFF9432F), white = Color(0xFFFFFFFF);
    canvas.drawCircle(c, r, Paint()..color = red);
    canvas.drawCircle(c, r * 0.76, Paint()..color = white);
    canvas.drawCircle(c, r * 0.46, Paint()..color = red);
    canvas.drawCircle(c, r * 0.14, Paint()..color = white);
  }

  @override
  bool shouldRepaint(DartboardPainter old) => old.wobble != wobble || old.mono != mono || old.color != color;
}

/// Monochrome dartboard in the current icon colour.
class DartboardIcon extends StatelessWidget {
  const DartboardIcon({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: DartboardPainter(mono: true, color: IconTheme.of(context).color ?? Colors.white)),
      );
}

/// A short, thick dart pointing at the centre from the upper right: blue
/// shaft, yellow fletching.
class _DartPainter extends CustomPainter {
  const _DartPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    // ось из правого верхнего угла в левый нижний; наконечник — в (0, s)
    final tip = Offset(0, s);
    final tail = Offset(s, 0);
    final dir = (tail - tip) / (tail - tip).distance;
    final n = Offset(-dir.dy, dir.dx);
    canvas.drawLine(tip, tail - dir * (s * 0.2), Paint()
      ..color = const Color(0xFF119FDC)
      ..strokeWidth = s * 0.2
      ..strokeCap = StrokeCap.round);
    final f0 = tail - dir * (s * 0.5);
    final w = s * 0.26;
    final fletch = Path()
      ..moveTo(f0.dx, f0.dy)
      ..lineTo((f0 + n * w + dir * (s * 0.14)).dx, (f0 + n * w + dir * (s * 0.14)).dy)
      ..lineTo((tail + n * w).dx, (tail + n * w).dy)
      ..lineTo(tail.dx, tail.dy)
      ..lineTo((tail - n * w).dx, (tail - n * w).dy)
      ..lineTo((f0 - n * w + dir * (s * 0.14)).dx, (f0 - n * w + dir * (s * 0.14)).dy)
      ..close();
    canvas.drawPath(fletch, Paint()..color = const Color(0xFFF9D648));
  }

  @override
  bool shouldRepaint(_DartPainter old) => false;
}

/// Success: the board pops up, the dart flies into the centre, the icon
/// lights up and wobbles, then two outlines fly out like the badges'
/// (white and smaller first, then red — the board's rings).
class DartHit extends StatefulWidget {
  const DartHit({super.key, required this.size});

  final double size;

  @override
  State<DartHit> createState() => _DartHitState();
}

class _DartHitState extends State<DartHit> with SingleTickerProviderStateMixin {
  late final AnimationController _a =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  /// Colour matrix that lightens everything by [k] (0..1).
  static ColorFilter _lighten(double k) => ColorFilter.matrix([
        1 - k, 0, 0, 0, 255 * k, //
        0, 1 - k, 0, 0, 255 * k,
        0, 0, 1 - k, 0, 255 * k,
        0, 0, 0, 1, 0,
      ]);

  @override
  Widget build(BuildContext context) {
    final d = widget.size;
    const hitAt = 0.38;
    return AnimatedBuilder(
      animation: _a,
      builder: (context, _) {
        final t = _a.value;
        final pop = Curves.easeOutBack.transform((t / 0.2).clamp(0, 1));
        final flight = Curves.easeInCubic.transform(((t - 0.15) / (hitAt - 0.15)).clamp(0, 1));
        final hit = ((t - hitAt) / 0.22).clamp(0.0, 1.0);
        final wobble = hit > 0 && hit < 1 ? math.sin(hit * math.pi * 3) * (1 - hit) : 0.0;
        // после попадания светлеет вся иконка, затем возвращается
        final glow = hit > 0 ? 0.5 * math.sin(math.pi * hit) : 0.0;
        final dart = d * 0.46;
        final start = Offset(d * 0.9, -d * 0.9);
        final at = Offset.lerp(start, Offset.zero, flight)!;
        Widget ring(double from, double box, Color color) => SizedBox.square(
              dimension: box,
              child: CustomPaint(painter: FlyOutPainter(((t - from) / 0.48).clamp(0, 1), color, circle: true)),
            );
        return SizedBox.square(
          dimension: d * 1.6,
          child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
            ColorFiltered(
              colorFilter: _lighten(glow),
              child: SizedBox.square(
                dimension: d * 1.6,
                child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                  Transform.scale(
                    scale: pop,
                    child: SizedBox.square(dimension: d, child: CustomPaint(painter: DartboardPainter(wobble: wobble))),
                  ),
                  if (t > 0.15)
                    Transform.translate(
                      offset: at + Offset(dart / 2, -dart / 2),
                      // стрела проявляется из прозрачного по ходу полёта
                      child: Opacity(
                        opacity: flight.clamp(0.0, 1.0),
                        child: SizedBox.square(dimension: dart, child: const CustomPaint(painter: _DartPainter())),
                      ),
                    ),
                ]),
              ),
            ),
            // кольца — поверх мишени, расходятся наружу
            if (t > hitAt) ring(hitAt, d * 0.76, Colors.white),
            if (t > hitAt + 0.14) ring(hitAt + 0.14, d, const Color(0xFFF9432F)),
          ]),
        );
      },
    );
  }
}

/// Bars of puzzle counts by rating hundreds; solved part darker; the chosen
/// rating marked.
class _HistogramPainter extends CustomPainter {
  _HistogramPainter(this.all, this.done, this.t, this.scheme, this.target);

  final List<int> all, done;
  final double t;
  final ColorScheme scheme;
  final int target;

  @override
  void paint(Canvas canvas, Size size) {
    final top = all.fold(1, math.max);
    final w = size.width / all.length;
    for (var i = 0; i < all.length; i++) {
      if (all[i] == 0) continue;
      final h = size.height * all[i] / top * t;
      final r = RRect.fromRectAndCorners(Rect.fromLTWH(i * w + 1, size.height - h, w - 2, h),
          topLeft: const Radius.circular(3), topRight: const Radius.circular(3));
      canvas.drawRRect(r, Paint()..color = scheme.primary.withValues(alpha: 0.45));
      final hd = size.height * done[i] / top * t;
      if (hd > 0) canvas.drawRect(Rect.fromLTWH(i * w + 1, size.height - hd, w - 2, hd), Paint()..color = scheme.primary);
    }
    final x = ((target - 400) / 100 + 0.5) * w;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), Paint()
      ..color = scheme.tertiary
      ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_HistogramPainter old) => old.t != t;
}

