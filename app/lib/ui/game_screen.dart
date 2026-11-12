/// Game analysis screen.
///
/// The layout follows the width: on a wide screen the board, the move list and
/// the panel stand side by side; on a phone the board is on top and the tabs
/// below. The unit switch floats over the bottom of the tab content.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../analysis/settings.dart';
import '../engine/game_job.dart';
import 'controller.dart';
import 'labels.dart';
import 'prefs.dart';
import 'step_icons.dart';
import 'widgets/board_view.dart';
import 'widgets/eval_widgets.dart';
import 'widgets/idea_panel.dart';
import 'widgets/locks_panel.dart';
import 'widgets/move_detail.dart';
import 'analysis_queue.dart';
import 'widgets/more_graphs.dart';
import 'widgets/move_list.dart';

const _floatSpace = 72.0; // место под плавающим переключателем единиц

class GameScreen extends StatefulWidget {
  const GameScreen(
      {super.key, required this.controller, this.heroTag, this.heroShuttle, this.job, this.keepPosition = false});

  /// Opened at a chosen move (from the Positions screen and the like): the
  /// last saved state of the game must not take it elsewhere.
  final bool keepPosition;

  final AnalysisController controller;
  final Object? heroTag;

  /// Device analysis still feeding this game: the screen refreshes from it
  /// every 5 seconds and shows its controls.
  final AnalysisJob? job;

  /// Flight of the board from the home card (crossfades the position).
  final HeroFlightShuttleBuilder? heroShuttle;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final _focus = FocusNode();

  AnalysisController get c => widget.controller;

  Timer? _refresh;
  int _seen = -1;

  Timer? _saveState;
  TabController? _tabs;
  List<String?> _tabNames = const [];
  String? _tabName;

  String get _stateKey => 'game.state.${c.game.id}';

  /// Back to where the user left this game (after the board's flight).
  Future<void> _restore() async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_stateKey);
      if (raw != null && mounted && !widget.keepPosition) {
        final s = jsonDecode(raw) as Map<String, dynamic>;
        await c.restoreState(s);
        final i = _tabNames.indexOf(s['tab'] as String? ?? '');
        if (i >= 0 && _tabs != null && mounted && !_limited) _tabs!.animateTo(i);
      }
    } catch (_) {}
    if (mounted) c.addListener(_scheduleSave);
  }

  void _scheduleSave() {
    _saveState?.cancel();
    _saveState = Timer(const Duration(milliseconds: 800), _save);
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_stateKey, jsonEncode({...c.saveState(), 'tab': ?_tabName}));
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    c.addListener(_rebuild);
    c.setPercentSteps(prefs.percentSteps);
    prefs.addListener(_onPrefs);
    _restore();
    final job = widget.job;
    if (job != null) {
      _seen = job.revision;
      job.addListener(_rebuild);
      // [авторское] разбор обновляется раз в 5 секунд, а не на каждой позиции:
      // пересчёт меток и идей дешевле, а значки не мерцают
      _refresh = Timer.periodic(const Duration(seconds: 5), (_) => _pull());
      // Diff без анализа сложности: кнопка запускает его для этой партии
      // (классический анализ не пересчитывается)
      c.runDifficulty = () {
        job.addDifficulty();
        analysisQueue.resume(job);
        _syncDifficulty();
      };
      _syncDifficulty();
    }
  }

  void _syncDifficulty() {
    final job = widget.job;
    if (job == null) return;
    c.difficultyRunning = job.difficulty && !job.scanned;
    if (mounted) setState(() {});
  }

  void _onPrefs() => c.setPercentSteps(prefs.percentSteps);

  void _pull() {
    final job = widget.job;
    if (job == null || job.revision == _seen || !job.ready) return;
    _seen = job.revision;
    c.updateGame(job.snapshot());
    _syncDifficulty();
  }

  @override
  void dispose() {
    c.removeListener(_scheduleSave);
    if (_saveState?.isActive ?? false) _save();
    _saveState?.cancel();
    _refresh?.cancel();
    widget.job?.removeListener(_rebuild);
    prefs.removeListener(_onPrefs);
    c.removeListener(_rebuild);
    _focus.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowRight:
        c.next();
      case LogicalKeyboardKey.arrowLeft:
        c.prev();
      case LogicalKeyboardKey.home:
        c.first();
      case LogicalKeyboardKey.end:
        c.last();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final h = c.game.headers;
    // в узкой и средней раскладке заголовок партии — во вкладке Game; в
    // шапке остаётся только ход анализа
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final job = widget.job;
    final status = job != null && !job.done;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        appBar: AppBar(
          title: wide
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.game.title, style: const TextStyle(fontSize: 17), overflow: TextOverflow.ellipsis),
                    Text(
                      _subtitle(h),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                    ),
                  ],
                )
              : (status
                  ? Text(_subtitle(h), style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis)
                  : null),
          // полоска под шапкой: бежит, пока движок считает; стоит на месте,
          // когда анализ отдыхает, на паузе или ждёт очереди
          bottom: status
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(3),
                  child: SizedBox(
                    height: 3,
                    child: job.state == JobState.running && job.thinking
                        ? const LinearProgressIndicator(minHeight: 3)
                        : LinearProgressIndicator(
                            minHeight: 3,
                            value: job.progress,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                  ),
                )
              : null,
          actions: [
            if (widget.job case final job?) ..._jobActions(job),
            // кнопка «стереть всё» появляется и уходит плавно
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (w, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: a, child: w)),
                child: c.hasArrows
                    ? IconButton(
                        key: const ValueKey('clear'),
                        tooltip: 'Clear arrows and marks',
                        onPressed: c.clearArrows,
                        icon: const Icon(Icons.layers_clear_rounded))
                    : const SizedBox.shrink(key: ValueKey('none')),
              ),
            ),
            IconButton(
              tooltip: c.pen ? 'Stop drawing' : 'Draw arrows',
              isSelected: c.pen,
              onPressed: c.togglePen,
              icon: const Icon(Icons.edit_outlined),
              selectedIcon: const Icon(Icons.edit_rounded),
            ),
            IconButton(tooltip: 'Flip board', onPressed: c.flip, icon: const Icon(Icons.swap_vert)),
            const SizedBox(width: 4),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, box) {
            if (box.maxWidth >= 1100) return _wide(box);
            if (box.maxWidth >= 720) return _medium(box);
            return _narrow(box);
          },
        ),
      ),
    );
  }

  String _subtitle(Map<String, String> h, {bool status = true}) {
    final job = widget.job;
    if (status && job != null && !job.done) {
      final waiting = job.state != JobState.running &&
          !job.pausedByUser &&
          job.state != JobState.failed &&
          analysisQueue.jobs.any((j) => j.state == JobState.running && j != job);
      final what = switch (job.state) {
        JobState.running => job.thinking ? 'Analyzing' : 'Resting (power saving)',
        JobState.failed => 'Stopped',
        _ => waiting ? 'Waiting in the queue' : 'Paused',
      };
      return '$what · depth ${job.depth} of ${job.targetDepth} · ${(job.progress * 100).round()}%';
    }
    final year = (h['date'] ?? '').length >= 4 ? h['date']!.substring(0, 4) : '';
    final where = [
      if ((h['event'] ?? '').isNotEmpty && h['event'] != '?') h['event']!,
      if (year.isNotEmpty && !year.contains('?')) year,
    ].join(', ');
    return [
      if (where.isNotEmpty) where,
      h['result'] ?? '*',
      if (job != null) 'depth ${job.depth}',
    ].join(' · ');
  }

  /// Pause / resume while the engine works; "deeper" when it is done.
  List<Widget> _jobActions(AnalysisJob job) => [
        if (job.state == JobState.running)
          IconButton(tooltip: 'Pause analysis', onPressed: job.pause, icon: const Icon(Icons.pause_rounded))
        else if (!job.done)
          IconButton(
              tooltip: 'Resume analysis',
              onPressed: () => analysisQueue.resume(job),
              icon: const Icon(Icons.play_arrow_rounded))
        else if (job.targetDepth < maxDepth)
          IconButton(
              tooltip: 'Analyze deeper (+4)', onPressed: () => analysisQueue.deeper(job), icon: const Icon(Icons.keyboard_double_arrow_down_rounded)),
      ];

  /// Top of the Game tab: players, event, opening, engine, then the
  /// evaluation graph with its fold.
  Widget _gameHeader() {
    final h = c.game.headers;
    final scheme = Theme.of(context).colorScheme;
    String? opening;
    for (final r in c.analysis.records) {
      if (r.opening != null) opening = r.opening;
    }
    final e = c.game.engine;
    final engine = [
      if (e['name'] != null) '${e['name']}',
      if (widget.job case final job?) 'depth ${job.depth}' else if (e['depth'] != null) 'depth ${e['depth']}',
      if (e['multipv'] != null) 'MultiPV ${e['multipv']}',
    ].join(', ');
    final sub = TextStyle(fontSize: 13, color: scheme.outline);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(c.game.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(_subtitle(h, status: false), style: sub),
        if (opening != null) Text(opening, style: sub),
        if (engine.isNotEmpty) Text(engine, style: sub),
        const SizedBox(height: 8),
        // пройтись по ошибкам: «далее» и «назад» — только по негативным ходам
        SizedBox(
          width: double.infinity,
          child: c.errorsOnly
              ? FilledButton.icon(
                  onPressed: () => c.setErrorsOnly(false),
                  icon: const Icon(Icons.flag_rounded, size: 18),
                  label: const Text('Stepping through mistakes · tap to stop'),
                )
              : OutlinedButton.icon(
                  onPressed: () {
                    c.setErrorsOnly(true);
                    final p = c.nextNegative(c.atStart ? -1 : c.ply - 1);
                    if (p != null) c.select(p);
                  },
                  icon: const Icon(Icons.outlined_flag_rounded, size: 18),
                  label: const Text('Step through mistakes'),
                ),
        ),
        const SizedBox(height: 8),
        // пока анализ идёт, графиков нет: данные ещё меняются
        if (!_limited) ...[
          CollapsibleGraph(controller: c, height: 90),
          MoreGraphs(controller: c),
        ],
        // стереть все свои ветки (с подтверждением)
        if (c.variations.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Clear all branches?'),
                    content: Text('${c.variations.length} own branch${c.variations.length == 1 ? '' : 'es'} will be removed.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
                    ],
                  ),
                );
                if (ok ?? false) c.clearVariations();
              },
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: Text('Clear ${c.variations.length} branch${c.variations.length == 1 ? '' : 'es'}'),
            ),
          ),
      ]),
    );
  }

  Widget _boardColumn(double boardSize, {double graphHeight = 110, bool graph = true}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Hero(
              tag: widget.heroTag ?? 'board',
              // перелёт рисует герой карточки на главной (плавная смена позиции)
              flightShuttleBuilder: widget.heroShuttle,
              child: BoardView(controller: c, size: boardSize),
            ),
            const SizedBox(width: 8),
            EvalBar(controller: c, height: boardSize),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: boardSize + 30,
          child: _NavBar(controller: c),
        ),
        if (graph && !_limited)
          SizedBox(
            width: boardSize + 30,
            child: CollapsibleGraph(controller: c, height: graphHeight),
          ),
      ],
    );
  }

  /// Floating controls: quick settings, the unit switch and — while the
  /// device analyses the game — pause / resume, all without grey outlines.
  Widget _unitSwitch() {
    final scheme = Theme.of(context).colorScheme;
    // кнопки рисуют только свой белый контур: без подложки большего размера,
    // хитбокс совпадает с видимой формой
    final side = BorderSide(color: scheme.outline);
    Widget round(Widget icon, String tip, VoidCallback onTap) => IconButton.outlined(
          tooltip: tip,
          onPressed: onTap,
          icon: icon,
          style: IconButton.styleFrom(
            backgroundColor: scheme.surface,
            side: side,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            minimumSize: const Size.square(40),
            fixedSize: const Size.square(40),
          ),
        );
    final job = widget.job;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      round(const Icon(Icons.tune_rounded, size: 20), 'Quick settings', _quickSettings),
      const SizedBox(width: 8),
      SegmentedButton<Unit>(
        segments: [for (final u in Unit.values) ButtonSegment(value: u, label: Text(unitLabel(u)))],
        selected: {c.unit},
        showSelectedIcon: false,
        style: ButtonStyle(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          side: WidgetStatePropertyAll(side),
          backgroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? scheme.secondaryContainer : scheme.surface),
        ),
        onSelectionChanged: (s) => c.setUnit(s.first),
      ),
      if (job != null && !job.done) ...[
        const SizedBox(width: 8),
        job.state == JobState.running
            ? round(const Icon(Icons.pause_rounded, size: 20), 'Pause analysis', job.pause)
            : round(const Icon(Icons.play_arrow_rounded, size: 20), 'Resume analysis', () => analysisQueue.resume(job)),
      ],
    ]);
  }

  /// A setting's name with a blue guide circle after it: a tap explains it.
  Widget _withGuide(BuildContext context, String name, String text) => Row(children: [
        Flexible(child: Text(name)),
        IconButton(
          tooltip: 'What is it?',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.info_outline_rounded, size: 20, color: Color(0xFF3B82F6)),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(name),
              content: Text(text),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
            ),
          ),
        ),
      ]);

  /// What the board shows: best-move arrows, move icons, square colours,
  /// idea arrows.
  void _quickSettings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListenableBuilder(
        listenable: prefs,
        builder: (context, _) => ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 16), children: [
          // копирование партии — первым
          ListTile(
            leading: const Icon(Icons.content_copy_rounded),
            title: const Text('Copy PGN'),
            subtitle: const Text('The game with its headers, to paste elsewhere'),
            onTap: () {
              Clipboard.setData(ClipboardData(text: c.game.pgn));
              Navigator.pop(context);
              ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(content: Text('PGN copied')));
            },
          ),
          SwitchListTile(
            title: const Text('Best move arrows'),
            value: prefs.showBestArrow,
            onChanged: (v) => prefs.update(bestArrow: v),
          ),
          SwitchListTile(
            title: const Text('Move icons on the board'),
            value: prefs.showBoardIcons,
            onChanged: (v) => prefs.update(boardIcons: v),
          ),
          SwitchListTile(
            title: const Text('Colour of the move squares'),
            value: prefs.showSquareTint,
            onChanged: (v) => prefs.update(squareTint: v),
          ),
          SwitchListTile(
            title: const Text('Idea threat arrows'),
            value: prefs.showIdeaArrows,
            onChanged: (v) => prefs.update(ideaArrows: v),
          ),
          SwitchListTile(
            title: _withGuide(context, 'Trick sign',
                'In a lost position, a white sign next to the move\'s sign shows that some of the opponent\'s moves '
                'would let the game slip to a draw: stalemate, perpetual check or another drawing line. Tap the sign '
                'to see how many.'),
            value: prefs.showTrick,
            onChanged: (v) => prefs.update(trick: v),
          ),
          SwitchListTile(
            title: _withGuide(context, 'Steps in percent',
                'Moves are graded by the share of the expected result they lose: best up to 1%, excellent 1–2%, '
                'good 2–5%, inaccuracy 5–10%, laxity 10–15%, mistake 15–25%, blunder over 25%. A move outside the '
                'best lines that loses up to 1% is neutral.'),
            value: prefs.percentSteps,
            onChanged: (v) => prefs.update(percent: v),
          ),
        ]),
      ),
    );
  }

  /// The analysis of this game is still running: only the Game tab with the
  /// move list works, the other tabs are dimmed and the graphs hidden.
  bool get _limited => widget.job != null && !widget.job!.done;

  Widget _panel({required bool withMoves}) {
    final limited = _limited;
    Tab tab(String name, {bool off = false}) => Tab(
          text: name,
          child: off ? Opacity(opacity: 0.38, child: Text(name)) : null,
        );
    final tabs = [
      if (withMoves) tab('Game'),
      tab('Move', off: limited),
      tab('Ideas', off: limited),
      tab('Lines', off: limited),
      tab('Locks', off: limited),
    ];
    // в полной ширине вкладки Game нет: панель целиком ждёт конца анализа
    if (limited && !withMoves) {
      final scheme = Theme.of(context).colorScheme;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('The analysis is still running. The move, ideas, lines and locks open when it is done.',
              textAlign: TextAlign.center, style: TextStyle(color: scheme.outline)),
        ),
      );
    }
    return DefaultTabController(
      key: ValueKey('$withMoves-$limited'),
      length: tabs.length,
      initialIndex: withMoves && !limited ? 1 : 0,
      child: Builder(
        builder: (context) {
          final tc = DefaultTabController.of(context);
          final views = [
            if (withMoves) MoveList(controller: c, bottomPadding: _floatSpace, header: _gameHeader()),
            _scroll(MoveDetail(controller: c, onOpenIdea: () => tc.animateTo(withMoves ? 2 : 1))),
            IdeaPanel(controller: c, bottomPadding: _floatSpace),
            _scroll(LinesTable(controller: c)),
            LocksPanel(controller: c, bottomPadding: _floatSpace),
          ];
          _tabs = tc;
          _tabNames = [for (final x in tabs) x.text];
          return _TabWatcher(
            controller: tc,
            // линия замков показывается на доске только на вкладке Locks
            onIndex: (i) {
              if (i != tabs.length - 1 && c.selectedLock != null) c.selectLock(null);
              // открытая вкладка тоже сохраняется между запусками
              if (_tabName != tabs[i].text) {
                _tabName = tabs[i].text;
                _scheduleSave();
              }
            },
            child: Stack(
              children: [
                Column(
                  children: [
                    TabBar(
                      tabs: tabs,
                      controller: tc,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      // идёт анализ — остальные вкладки не открываются
                      onTap: limited ? (i) => tc.animateTo(0) : null,
                    ),
                    Expanded(
                      child: TabBarView(
                          controller: tc,
                          physics: limited ? const NeverScrollableScrollPhysics() : null,
                          children: views),
                    ),
                  ],
                ),
                Positioned(left: 0, right: 0, bottom: 14, child: Center(child: _unitSwitch())),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _scroll(Widget child) =>
      SingleChildScrollView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 14 + _floatSpace), child: child);

  Widget _wide(BoxConstraints box) {
    final boardSize = (box.maxHeight - 190).clamp(320.0, 620.0);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.all(16), child: _boardColumn(boardSize)),
        SizedBox(
          width: 250,
          child: Card(
            margin: const EdgeInsets.fromLTRB(0, 16, 12, 16),
            child: MoveList(controller: c),
          ),
        ),
        Expanded(
          child: Card(margin: const EdgeInsets.fromLTRB(0, 16, 16, 16), child: _panel(withMoves: false)),
        ),
      ],
    );
  }

  Widget _medium(BoxConstraints box) {
    final boardSize = (box.maxWidth * 0.5 - 50).clamp(300.0, box.maxHeight - 200);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.all(12), child: _boardColumn(boardSize, graph: false)),
        Expanded(
          child: Card(margin: const EdgeInsets.fromLTRB(0, 12, 12, 12), child: _panel(withMoves: true)),
        ),
      ],
    );
  }

  Widget _narrow(BoxConstraints box) {
    final boardSize = (box.maxWidth - 46).clamp(240.0, 520.0);
    return Column(
      children: [
        const SizedBox(height: 8),
        _boardColumn(boardSize, graph: false),
        Expanded(child: _panel(withMoves: true)),
      ],
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({required this.controller});

  final AnalysisController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final scheme = Theme.of(context).colorScheme;
    final Widget label;
    final vm = c.varMove;
    if (vm != null) {
      // своя ветка: ход и оценка, если ветка идёт по линии движка
      final v = c.variation!;
      final ply = v.anchor + 1 + c.varIndex;
      // в линиях движка — знак вердикта; свой ход — значок ветки, серым
      final kind = vm.kind ?? 'branch';
      final color = vm.kind != null ? markColor(kind) : markColor('neutral');
      label = Row(
        key: ValueKey(c.positionKey),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // значок ветки: синий — линия анализа, серый — продолжение движка
          // телефона, фиолетовый — свой ход
          Icon(Icons.call_split_rounded, size: 16, color: branchColor(vm)),
          const SizedBox(width: 10),
          Text('${plyText(ply)} ${vm.san}', style: TextStyle(fontWeight: FontWeight.w700, color: color)),
          const SizedBox(width: 6),
          StepGlyph(kind: kind, color: color, size: 18),
          if (vm.eval != null) ...[
            const SizedBox(width: 6),
            Text(whiteEvalText(vm.eval!, vm.root, c.unit), style: TextStyle(fontSize: 12, color: scheme.outline)),
          ],
        ],
      );
    } else if (c.atStart) {
      label = Text('Start', key: const ValueKey('start'),
          textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, color: scheme.outline));
    } else if (c.atEnd) {
      final e = c.end!;
      final color = e.step != null ? markColor(e.step!) : markColor('forced');
      label = Row(
        key: const ValueKey('end'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(e.label, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
          const SizedBox(width: 6),
          StepGlyph(kind: e.kind, color: color, size: 18),
        ],
      );
    } else {
      final r = c.analysis.records[c.ply];
      final kind = c.kindAt(c.ply);
      // среднее поле: только знак, ход того же цвета
      final color = c.kindColorAt(c.ply, kind);
      label = Row(
        key: ValueKey(c.positionKey),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${plyText(r.ply)} ${r.san}',
            style: TextStyle(fontWeight: FontWeight.w700, color: color),
          ),
          const SizedBox(width: 6),
          StepGlyph(kind: kind, color: color, size: 18),
        ],
      );
    }
    return Row(
      children: [
        IconButton(tooltip: 'First move', onPressed: c.canPrev ? c.first : null, icon: const Icon(Icons.first_page)),
        _HoldRepeat(
          onStep: () => c.canPrev ? c.prev() : null,
          // без подсказки: долгое нажатие здесь — автоповтор
          child: IconButton(
              onPressed: c.canPrev ? c.prev : null,
              icon: const Icon(Icons.chevron_left)),
        ),
        // по ошибкам: рядом со стрелками — значки соседних негативных ходов
        if (c.errorsOnly && !c.inVariation) _neighbour(c, c.prevNegative()),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (w, a) => ScaleTransition(
              scale: a,
              child: FadeTransition(opacity: a, child: w),
            ),
            child: label,
          ),
        ),
        if (c.errorsOnly && !c.inVariation) _neighbour(c, c.nextNegative()),
        _HoldRepeat(
          onStep: () => c.canNext ? c.next() : null,
          child: IconButton(
              onPressed: c.canNext ? c.next : null,
              icon: const Icon(Icons.chevron_right)),
        ),
        IconButton(
          tooltip: 'Last move',
          onPressed: c.inVariation || c.ply < c.lastPly ? c.last : null,
          icon: const Icon(Icons.last_page),
        ),
      ],
    );
  }
}

/// Holding the button steps on and on (a step every 140 ms) until released.
class _HoldRepeat extends StatefulWidget {
  const _HoldRepeat({required this.onStep, required this.child});

  final VoidCallback onStep;
  final Widget child;

  @override
  State<_HoldRepeat> createState() => _HoldRepeatState();
}

class _HoldRepeatState extends State<_HoldRepeat> {
  Timer? _timer;

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onLongPressStart: (_) {
          widget.onStep();
          _timer = Timer.periodic(const Duration(milliseconds: 140), (_) => widget.onStep());
        },
        onLongPressEnd: (_) => _stop(),
        onLongPressCancel: _stop,
        child: widget.child,
      );
}

Widget _neighbour(AnalysisController c, int? ply) => AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: SizedBox(
        key: ValueKey(ply),
        width: 22,
        child: ply == null
            ? null
            : StepGlyph(kind: c.kindAt(ply), color: c.kindColorAt(ply, c.kindAt(ply)), size: 16),
      ),
    );

class _TabWatcher extends StatefulWidget {
  const _TabWatcher({required this.controller, required this.onIndex, required this.child});

  final TabController controller;
  final ValueChanged<int> onIndex;
  final Widget child;

  @override
  State<_TabWatcher> createState() => _TabWatcherState();
}

class _TabWatcherState extends State<_TabWatcher> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() => widget.onIndex(widget.controller.index);

  @override
  Widget build(BuildContext context) => widget.child;
}
