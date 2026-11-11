/// Analysis board screen: a free board with the engine's evaluation and its
/// best lines, a move tree with branches, saved sessions (new session and the
/// list in the app bar).
library;

import 'dart:math' as math;

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' hide Board;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../analysis/eval.dart';
import '../analysis/pos.dart';
import '../engine/game_job.dart' show EnginePower;
import 'analysis_queue.dart';
import 'board_session.dart';
import 'prefs.dart';
import 'widgets/arrows.dart';
import 'widgets/board_background.dart';
import 'widgets/faded_line.dart';

class AnalysisBoardScreen extends StatefulWidget {
  const AnalysisBoardScreen({super.key, this.startFen, this.title, this.temporary = false});

  /// Start from this position in a new session (e.g. a solved puzzle).
  final String? startFen;
  final String? title;

  /// Not saved unless the user keeps it (a position from a puzzle).
  final bool temporary;

  @override
  State<AnalysisBoardScreen> createState() => _AnalysisBoardScreenState();
}

class _AnalysisBoardScreenState extends State<AnalysisBoardScreen> {
  SessionController? c;
  late final ChessboardController _board;
  bool _pen = false;
  MoveNode? _shown;

  /// [авторское] Walking along an engine line without analysing: the lines
  /// as they were, the walked line's index and how many of its moves are on
  /// the board. Nothing is added to the tree; the board is not playable.
  ({List<Line> lines, int line, int at, Pos start})? _walk;
  final _walkKeys = <int, GlobalKey>{};

  List<String> get _walkPv => _walk!.lines[_walk!.line].pv;

  /// Starts (or leaves, for the same line) a walk along line [i].
  void _toggleWalk(SessionController s, int i) {
    final w = _walk;
    if (w != null && w.line == i) return _leaveWalk(s);
    final lines = w?.lines ?? s.lines;
    if (lines == null || i >= lines.length || lines[i].pv.isEmpty) return;
    _walkKeys.clear();
    setState(() => _walk = (lines: lines, line: i, at: 1, start: w?.start ?? s.position));
    _showWalk();
  }

  void _leaveWalk(SessionController s) {
    setState(() => _walk = null);
    _board.updatePosition(_gameData(s.position, s.current.move), animate: true);
    syncCheck(_board, inCheck: s.position.isCheck, king: s.position.king(s.position.turn));
  }

  void _stepWalk(int d) {
    final w = _walk!;
    final at = (w.at + d).clamp(0, _walkPv.length);
    setState(() => _walk = (lines: w.lines, line: w.line, at: at, start: w.start));
    _showWalk();
  }

  void _showWalk() {
    final w = _walk!;
    var pos = w.start;
    NormalMove? last;
    for (final uci in _walkPv.take(w.at)) {
      final m = NormalMove.fromUci(uci);
      if (!pos.isLegal(m)) break;
      pos = pos.push(m);
      last = m;
    }
    _board.updatePosition(
        GameData(
          fen: pos.fen,
          lastMove: last,
          playerSide: PlayerSide.none,
          sideToMove: pos.turn,
          kingSquareInCheck: null,
          validMoves: makeLegalMoves(pos.p),
        ),
        animate: true);
    syncCheck(_board, inCheck: pos.isCheck, king: pos.king(pos.turn));
    // текущий ход линии — в видимой части (линия сдвигается у края)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _walkKeys[w.at]?.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(ctx, alignment: 0.5, duration: const Duration(milliseconds: 200));
      }
    });
  }

  static BoardSession _newSession({String? fen, String? title}) => BoardSession(
        id: 'board_${DateTime.now().millisecondsSinceEpoch}',
        name: title ?? 'Session ${DateTime.now().toLocal().toString().substring(0, 16)}',
        startFen: fen ?? Chess.initial.fen,
      );

  @override
  void initState() {
    super.initState();
    _board = ChessboardController(game: _gameData(Pos(Chess.initial), null));
    _init();
  }

  Future<void> _init() async {
    // движок запускается после анимации перехода
    await Future<void>.delayed(const Duration(milliseconds: 350));
    BoardSession session;
    if (widget.startFen != null) {
      session = _newSession(fen: widget.startFen, title: widget.title);
    } else {
      final saved = await BoardSessions.load();
      session = saved.isNotEmpty ? saved.first : _newSession();
    }
    if (!mounted) return;
    final temporary = widget.startFen != null && widget.temporary;
    setState(() => c = SessionController(session)
      ..temporary = temporary
      ..addListener(_onChange));
    if (!temporary) BoardSessions.save(session);
    _onChange();
  }

  @override
  void dispose() {
    c?.removeListener(_onChange);
    c?.dispose();
    _board.dispose();
    super.dispose();
  }

  GameData _gameData(Pos pos, NormalMove? last) => GameData(
        fen: pos.fen,
        lastMove: last,
        playerSide: PlayerSide.both,
        sideToMove: pos.turn,
        kingSquareInCheck: null,
        validMoves: makeLegalMoves(pos.p),
      );

  void _onChange() {
    final s = c;
    if (s == null) return;
    if (!identical(_shown, s.current)) {
      _walk = null;
      final near = _shown != null && (identical(s.current.parent, _shown) || identical(_shown!.parent, s.current));
      _board.updatePosition(_gameData(s.position, s.current.move), animate: near);
      syncCheck(_board, inCheck: s.position.isCheck, king: s.position.king(s.position.turn));
      _shown = s.current;
    }
    setState(() {});
  }

  /// Which sessions the list shows: opening (clean board) or position.
  String _listKind = 'opening';

  Future<void> _sessions() async {
    final list = await BoardSessions.load();
    if (!mounted) return;
    _listKind = c?.session.kind ?? 'opening';
    final book = analysisQueue.book;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(builder: (context, setSheet) {
        final scheme = Theme.of(context).colorScheme;
        // закреплённые — в самом верху, затем избранные, затем по порядку
        final shown = [for (final x in list) if (x.kind == _listKind) x]
          ..sort((a, b) {
            int rank(BoardSession x) => x.pinned ? 0 : (x.favourite ? 1 : 2);
            return rank(a) - rank(b);
          });
        void changed(BoardSession x) {
          BoardSessions.save(x);
          if (x.id == c?.session.id) {
            c!.session
              ..pinned = x.pinned
              ..favourite = x.favourite
              ..name = x.name;
            setState(() {});
          }
          setSheet(() {});
        }

        return SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'opening', label: Text('Openings'), icon: Icon(Icons.flag_outlined)),
                    ButtonSegment(value: 'position', label: Text('Positions'), icon: Icon(Icons.biotech_outlined)),
                  ],
                  selected: {_listKind},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => setSheet(() => _listKind = v.first),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(children: [
                for (final x in shown)
                  Dismissible(
                    key: ValueKey(x.id),
                    direction: DismissDirection.endToStart,
                    onDismissed: (_) {
                      BoardSessions.remove(x.id);
                      setSheet(() => list.remove(x));
                    },
                    background: Container(color: scheme.errorContainer),
                    child: ListTile(
                      selected: x.id == c?.session.id,
                      leading: x.pinned ? const Icon(Icons.push_pin_rounded, size: 20) : null,
                      title: Text(x.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      // у дебютных — название дебюта, если он в книге
                      subtitle: Text(x.openingName(book) ?? '${x.moveCount} moves',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (x.isOpening)
                          IconButton(
                            tooltip: 'Rename',
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            onPressed: () async {
                              final name = await _askName(x.name);
                              if (name == null || name.isEmpty) return;
                              x.name = name;
                              changed(x);
                            },
                          ),
                        IconButton(
                          tooltip: x.pinned ? 'Unpin' : 'Pin to the top',
                          icon: Icon(x.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined, size: 20),
                          onPressed: () {
                            x.pinned = !x.pinned;
                            changed(x);
                          },
                        ),
                        IconButton(
                          tooltip: x.favourite ? 'Remove from favourites' : 'Add to favourites',
                          icon: Icon(x.favourite ? Icons.star_rounded : Icons.star_outline_rounded,
                              size: 20, color: x.favourite ? Colors.amber : null),
                          onPressed: () {
                            x.favourite = !x.favourite;
                            changed(x);
                          },
                        ),
                      ]),
                      onTap: () {
                        Navigator.of(context).pop();
                        c?.open(x);
                      },
                    ),
                  ),
                if (shown.isEmpty)
                  ListTile(
                      title: Text(_listKind == 'opening'
                          ? 'No opening sessions yet: start one with +'
                          : 'No position sessions yet: open a position with the analysis icon')),
              ]),
            ),
          ]),
        );
      }),
    );
  }

  Future<String?> _askName(String initial) async {
    final field = TextEditingController(text: initial);
    final v = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Session name'),
        content: TextField(controller: field, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, field.text.trim()), child: const Text('OK')),
        ],
      ),
    );
    field.dispose();
    return v;
  }

  void _new() {
    final s = _newSession();
    if (!c!.temporary) BoardSessions.save(c!.session);
    c!.open(s);
    BoardSessions.save(s);
  }

  @override
  Widget build(BuildContext context) {
    final s = c;
    return Scaffold(
      appBar: AppBar(
        title: Text(s?.session.name ?? 'Analysis board', overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: _pen ? 'Stop drawing' : 'Draw arrows',
            isSelected: _pen,
            onPressed: () => setState(() => _pen = !_pen),
            icon: const Icon(Icons.edit_outlined),
            selectedIcon: const Icon(Icons.edit_rounded),
          ),
          if (s != null && s.temporary)
            IconButton(
              tooltip: 'Save as a session',
              onPressed: () {
                s.keep();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved as “${s.session.name}”')));
              },
              icon: const Icon(Icons.bookmark_add_outlined),
            ),
          // PGN со всеми ветками — поделиться линиями дебюта
          IconButton(
            tooltip: 'Copy PGN with all branches',
            onPressed: s == null || s.session.root.children.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: s.session.pgn()));
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('PGN with all branches copied')));
                  },
            icon: const Icon(Icons.content_copy_rounded),
          ),
          IconButton(tooltip: 'Sessions', onPressed: _sessions, icon: const Icon(Icons.folder_open_rounded)),
          IconButton(tooltip: 'New session', onPressed: s == null ? null : _new, icon: const Icon(Icons.add_rounded)),
        ],
      ),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(builder: (context, box) {
              final size = math.min(box.maxWidth - 24, math.min(520.0, box.maxHeight * 0.55));
              return Column(children: [
                const SizedBox(height: 10),
                Center(child: _boardStack(s, size)),
                _nav(s),
                Expanded(
                  child: ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 16), children: [
                    _engine(context, s),
                    const SizedBox(height: 10),
                    _MoveTree(c: s),
                  ]),
                ),
              ]);
            }),
    );
  }

  Widget _boardStack(SessionController s, double size) {
    final best = _walk == null ? s.lines?.firstOrNull : null;
    final arrows = [
      if (best != null)
        BoardArrow(NormalMove.fromUci(best.move).from, NormalMove.fromUci(best.move).to, const Color(0xB015781B)),
      ...s.current.arrows,
    ];
    return SizedBox.square(
      dimension: size,
      child: Stack(children: [
        ArrowDrawing(
          flipped: s.flipped,
          pen: _pen,
          onArrow: s.toggleArrow,
          onMark: s.toggleMark,
          child: Chessboard(
            size: size,
            controller: _board,
            orientation: s.flipped ? Side.black : Side.white,
            onMove: (m, {viaDragAndDrop}) {
              if (m is NormalMove) s.play(m);
            },
            settings: ChessboardSettings(
              colorScheme: appScheme(_board),
              pieceAssets: prefs.pieceSet.assets,
              animationDuration: Duration(milliseconds: prefs.moveAnimationMs),
              borderRadius: const BorderRadius.all(Radius.circular(6)),
              boxShadow: kElevationToShadow[3]!,
            ),
          ),
        ),
        Positioned.fill(child: ArrowLayer(arrows: arrows, marks: s.current.marks, flipped: s.flipped)),
      ]),
    );
  }

  Widget _nav(SessionController s) => _walk != null
      ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(tooltip: 'Start of the line', onPressed: () => _stepWalk(-999), icon: const Icon(Icons.first_page)),
          IconButton(
              tooltip: 'Back', onPressed: _walk!.at > 0 ? () => _stepWalk(-1) : null, icon: const Icon(Icons.chevron_left)),
          IconButton(
              tooltip: 'Forward',
              onPressed: _walk!.at < _walkPv.length ? () => _stepWalk(1) : null,
              icon: const Icon(Icons.chevron_right)),
          IconButton(tooltip: 'End of the line', onPressed: () => _stepWalk(999), icon: const Icon(Icons.last_page)),
          IconButton(tooltip: 'Leave the line', onPressed: () => _leaveWalk(s), icon: const Icon(Icons.close_rounded)),
        ])
      : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(tooltip: 'Start', onPressed: s.current.parent != null ? s.toStart : null, icon: const Icon(Icons.first_page)),
        IconButton(tooltip: 'Back', onPressed: s.current.parent != null ? s.back : null, icon: const Icon(Icons.chevron_left)),
        IconButton(
            tooltip: 'Forward', onPressed: s.current.children.isNotEmpty ? s.forward : null, icon: const Icon(Icons.chevron_right)),
        IconButton(
            tooltip: 'End of line', onPressed: s.current.children.isNotEmpty ? s.toEnd : null, icon: const Icon(Icons.last_page)),
        IconButton(tooltip: 'Flip board', onPressed: s.flip, icon: const Icon(Icons.swap_vert)),
      ]);

  /// The walked line: its moves in a row that scrolls, the move on the
  /// board in blue; a tap on a move goes to it.
  Widget _walkLine(Pos start, List<String> pv, int at, ColorScheme scheme) {
    var b = start;
    final items = <Widget>[];
    for (final (i, uci) in pv.take(30).indexed) {
      final m = NormalMove.fromUci(uci);
      if (!b.isLegal(m)) break;
      final no = b.turn == Side.white ? '${b.fullmoves}. ' : (i == 0 ? '${b.fullmoves}... ' : '');
      final on = i + 1 == at;
      items.add(InkWell(
        key: _walkKeys.putIfAbsent(i + 1, GlobalKey.new),
        borderRadius: BorderRadius.circular(5),
        onTap: () => _stepWalk(i + 1 - _walk!.at),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
          decoration: BoxDecoration(color: on ? scheme.primary : null, borderRadius: BorderRadius.circular(5)),
          child: Text('$no${b.san(m)}', style: TextStyle(fontSize: 13, color: on ? scheme.onPrimary : null)),
        ),
      ));
      b = b.push(m);
    }
    return SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: items));
  }

  String _eval(Eval e, Side toMove) {
    final white = toMove == Side.white;
    if (e.mate != null) return '#${white ? e.mate : -e.mate!}';
    final v = (white ? e.cp! : -e.cp!) / 100;
    return '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}';
  }

  String _sanLine(Pos start, List<String> pv) {
    var b = start;
    final out = <String>[];
    for (final (i, uci) in pv.take(20).indexed) {
      final m = NormalMove.fromUci(uci);
      if (!b.isLegal(m)) break;
      final no = b.turn == Side.white ? '${b.fullmoves}. ' : (i == 0 ? '${b.fullmoves}... ' : '');
      out.add('$no${b.san(m)}');
      b = b.push(m);
    }
    return out.join(' ');
  }

  Widget _engine(BuildContext context, SessionController s) {
    final scheme = Theme.of(context).colorScheme;
    final walk = _walk;
    final lines = walk?.lines ?? s.lines;
    final start = walk?.start ?? s.position;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Switch(value: s.engineOn, onChanged: s.setEngine),
        const SizedBox(width: 6),
        const Text('Engine', style: TextStyle(fontWeight: FontWeight.w700)),
        const Spacer(),
        SegmentedButton<EnginePower>(
          segments: const [
            ButtonSegment(value: EnginePower.low, label: Text('Low')),
            ButtonSegment(value: EnginePower.medium, label: Text('Med')),
            ButtonSegment(value: EnginePower.high, label: Text('High')),
          ],
          selected: {s.power},
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          onSelectionChanged: (p) => s.setPower(p.first),
        ),
      ]),
      if (s.engineOn && lines == null && !s.position.p.isGameOver)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
            Text('Thinking…', style: TextStyle(color: scheme.outline)),
          ]),
        ),
      if ((s.engineOn || walk != null) && lines != null)
        for (final (i, l) in lines.indexed)
          InkWell(
            onTap: walk != null ? null : () => s.play(NormalMove.fromUci(l.move)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // нажатие на оценку — пройти по линии без нового анализа
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => _toggleWalk(s, i),
                  child: Container(
                    width: 56,
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: walk?.line == i ? scheme.primaryContainer : null,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(_eval(l.eval, start.turn),
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: i == 0 ? scheme.primary : null,
                            fontFeatures: const [FontFeature.tabularFigures()])),
                  ),
                ),
                Expanded(
                  child: walk?.line == i
                      ? _walkLine(start, l.pv, walk!.at, scheme)
                      : FadedLine(_sanLine(start, l.pv), style: const TextStyle(fontSize: 13)),
                ),
              ]),
            ),
          ),
      if (s.engineOn && lines != null)
        Text('Stockfish 19 (light), depth ${s.depth}', style: TextStyle(fontSize: 11, color: scheme.outline)),
    ]);
  }
}

/// Moves as a tree: the main line, branches in brackets; long-press removes
/// a branch.
class _MoveTree extends StatefulWidget {
  const _MoveTree({required this.c});

  final SessionController c;

  @override
  State<_MoveTree> createState() => _MoveTreeState();
}

/// A move held down is selected: round buttons copy the line up to it or
/// delete it with everything after it.
class _MoveTreeState extends State<_MoveTree> {
  SessionController get c => widget.c;
  MoveNode? _sel;

  /// The line from the start to [n] with move numbers.
  String _lineText(MoveNode n) {
    final path = <MoveNode>[];
    for (MoveNode? x = n; x != null && x.parent != null; x = x.parent) {
      path.insert(0, x);
    }
    final black0 = c.session.root.pos.turn == Side.black;
    final words = <String>[];
    for (final (i, x) in path.indexed) {
      final ply = x.ply - 1 + (black0 ? 1 : 0);
      if (ply.isEven) {
        words.add('${ply ~/ 2 + 1}.');
      } else if (i == 0) {
        words.add('${ply ~/ 2 + 1}...');
      }
      words.add(x.san);
    }
    return words.join(' ');
  }

  Widget _bar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final n = _sel!;
    Widget round(IconData icon, String tip, VoidCallback onTap, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: IconButton.filled(
            tooltip: tip,
            style: IconButton.styleFrom(
                backgroundColor: color ?? scheme.inverseSurface, foregroundColor: scheme.onInverseSurface),
            onPressed: onTap,
            icon: Icon(icon, size: 20),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        round(Icons.content_copy_rounded, 'Copy the line up to this move', () {
          Clipboard.setData(ClipboardData(text: _lineText(n)));
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Moves copied')));
          setState(() => _sel = null);
        }),
        // ветка: сделать главной линией или второстепенной
        if ((n.parent?.children.length ?? 0) > 1)
          round(
              Icons.call_split_rounded,
              identical(n.parent!.children.first, n) ? 'Make it a side branch' : 'Make it the main line', () {
            c.toggleMain(n);
            setState(() => _sel = null);
          }),
        round(Icons.delete_outline_rounded, 'Delete this move and all after it', () {
          c.delete(n);
          setState(() => _sel = null);
        }, color: scheme.error),
        round(Icons.close_rounded, 'Cancel', () => setState(() => _sel = null)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = <Widget>[];

    Widget chip(MoveNode n, {bool number = false}) {
      final current = identical(n, c.current);
      final ply = n.ply - 1 + (c.session.root.pos.turn == Side.black ? 1 : 0);
      final no = ply.isEven ? '${ply ~/ 2 + 1}. ' : (number ? '${ply ~/ 2 + 1}... ' : '');
      return GestureDetector(
        // зажатие — выбрать ход: скопировать линию или удалить
        onLongPress: () => setState(() => _sel = n),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            if (_sel != null) return setState(() => _sel = null);
            c.go(n);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: current ? scheme.primary : (identical(n, _sel) ? scheme.primaryContainer : Colors.transparent),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('$no${n.san}', style: TextStyle(color: current ? scheme.onPrimary : null)),
          ),
        ),
      );
    }

    // как в PGN: главный ход, затем ветки в скобках, затем продолжение
    void cont(MoveNode p, bool number) {
      while (p.children.isNotEmpty) {
        final main = p.children.first;
        items.add(chip(main, number: number));
        number = false;
        for (final alt in p.children.skip(1)) {
          items.add(Text('(', style: TextStyle(color: scheme.outline)));
          items.add(chip(alt, number: true));
          cont(alt, false);
          items.add(Text(')', style: TextStyle(color: scheme.outline)));
          number = true;
        }
        p = main;
      }
    }

    if (c.session.root.children.isEmpty) {
      return Text('Play a move on the board. Moves off the line become branches; hold a move to copy or delete it.',
          style: TextStyle(color: scheme.outline, fontSize: 13));
    }
    cont(c.session.root, true);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_sel != null) _bar(context),
      Wrap(spacing: 2, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: items),
    ]);
  }
}
