/// Analysis board screen: a free board with the engine's evaluation and its
/// best lines, a move tree with branches, saved sessions (new session and the
/// list in the app bar).
library;

import 'dart:math' as math;

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' hide Board;
import 'package:flutter/material.dart';

import '../analysis/eval.dart';
import '../analysis/pos.dart';
import '../engine/game_job.dart' show EnginePower;
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
      final near = _shown != null && (identical(s.current.parent, _shown) || identical(_shown!.parent, s.current));
      _board.updatePosition(_gameData(s.position, s.current.move), animate: near);
      syncCheck(_board, inCheck: s.position.isCheck, king: s.position.king(s.position.turn));
      _shown = s.current;
    }
    setState(() {});
  }

  Future<void> _sessions() async {
    final list = await BoardSessions.load();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => ListView(children: [
          for (final s in list)
            Dismissible(
              key: ValueKey(s.id),
              direction: DismissDirection.endToStart,
              onDismissed: (_) {
                BoardSessions.remove(s.id);
                setSheet(() => list.remove(s));
              },
              background: Container(color: Theme.of(context).colorScheme.errorContainer),
              child: ListTile(
                selected: s.id == c?.session.id,
                title: Text(s.name),
                subtitle: Text('${s.moveCount} moves'),
                onTap: () {
                  Navigator.of(context).pop();
                  c?.open(s);
                },
              ),
            ),
          if (list.isEmpty) const ListTile(title: Text('No sessions yet')),
        ]),
      ),
    );
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
    final best = s.lines?.firstOrNull;
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

  Widget _nav(SessionController s) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(tooltip: 'Start', onPressed: s.current.parent != null ? s.toStart : null, icon: const Icon(Icons.first_page)),
        IconButton(tooltip: 'Back', onPressed: s.current.parent != null ? s.back : null, icon: const Icon(Icons.chevron_left)),
        IconButton(
            tooltip: 'Forward', onPressed: s.current.children.isNotEmpty ? s.forward : null, icon: const Icon(Icons.chevron_right)),
        IconButton(
            tooltip: 'End of line', onPressed: s.current.children.isNotEmpty ? s.toEnd : null, icon: const Icon(Icons.last_page)),
        IconButton(tooltip: 'Flip board', onPressed: s.flip, icon: const Icon(Icons.swap_vert)),
      ]);

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
    final lines = s.lines;
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
      if (s.engineOn && lines != null)
        for (final (i, l) in lines.indexed)
          InkWell(
            onTap: () => s.play(NormalMove.fromUci(l.move)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 56,
                  child: Text(_eval(l.eval, s.position.turn),
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: i == 0 ? scheme.primary : null,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ),
                Expanded(child: FadedLine(_sanLine(s.position, l.pv), style: const TextStyle(fontSize: 13))),
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
class _MoveTree extends StatelessWidget {
  const _MoveTree({required this.c});

  final SessionController c;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = <Widget>[];

    Widget chip(MoveNode n, {bool number = false}) {
      final current = identical(n, c.current);
      final ply = n.ply - 1 + (c.session.root.pos.turn == Side.black ? 1 : 0);
      final no = ply.isEven ? '${ply ~/ 2 + 1}. ' : (number ? '${ply ~/ 2 + 1}... ' : '');
      return GestureDetector(
        onLongPress: () => c.delete(n),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => c.go(n),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: current ? scheme.primary : Colors.transparent,
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
      return Text('Play a move on the board. Moves off the line become branches; long-press a move to delete it.',
          style: TextStyle(color: scheme.outline, fontSize: 13));
    }
    cont(c.session.root, true);
    return Wrap(spacing: 2, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: items);
  }
}
