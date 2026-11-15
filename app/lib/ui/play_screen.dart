/// Play the engine: choose a level (1–8), a colour and friendly mode, then
/// play on the board; the engine answers. Past positions can be browsed with
/// the arrows under the board. Friendly mode adds takebacks, the evaluation
/// and the engine's best continuation.
library;

import 'dart:math' as math;

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' hide Board;
import 'package:flutter/material.dart';

import '../analysis/pos.dart';
import '../engine/bot.dart';
import '../engine/rated_play.dart' show accuracyForRating;
import 'home_screen.dart' show PawnIcon;
import 'play_controller.dart';
import 'prefs.dart';
import 'widgets/arrows.dart';
import 'widgets/board_background.dart';
import 'widgets/faded_line.dart';

class PlayScreen extends StatefulWidget {
  const PlayScreen({super.key});

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> {
  final c = PlayController();
  late final ChessboardController _board = ChessboardController(game: _gameData());
  int _shown = 0;
  bool _pen = false;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
    prefs.addListener(_onChange);
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    prefs.removeListener(_onChange);
    c.dispose();
    _board.dispose();
    super.dispose();
  }

  GameData _gameData() {
    final pos = c.position;
    return GameData(
      fen: pos.fen,
      lastMove: c.lastMove,
      playerSide: c.myTurn ? (c.player == Side.white ? PlayerSide.white : PlayerSide.black) : PlayerSide.none,
      sideToMove: pos.turn,
      kingSquareInCheck: null, // шах рисует фон доски
      validMoves: c.myTurn ? makeLegalMoves(pos.p) : const {},
    );
  }

  String? _shownFen;
  NormalMove? _shownLast;
  bool? _shownMyTurn;

  void _onChange() {
    // [авторское] доска — только при новой позиции: иначе следующее
    // уведомление (смена статуса после хода движка) ставило ту же позицию
    // заново и обрывало анимацию фигуры
    final pos = c.position;
    if (pos.fen != _shownFen || c.lastMove != _shownLast) {
      // фигуры едут при ходе и при листании на соседнюю позицию
      _board.updatePosition(_gameData(), animate: (c.shownIndex - _shown).abs() <= 2);
      _shownFen = pos.fen;
      _shownLast = c.lastMove;
      _shownMyTurn = c.myTurn;
    } else if (c.myTurn != _shownMyTurn) {
      // только чья очередь сменилась (та же позиция): после анимации хода,
      // иначе новая установка той же позиции обрывает движение фигуры
      _shownMyTurn = c.myTurn;
      Future<void>.delayed(Duration(milliseconds: prefs.moveAnimationMs + 30), () {
        if (mounted && c.position.fen == _shownFen) _board.updatePosition(_gameData(), animate: false);
      });
    }
    syncCheck(_board, inCheck: c.position.isCheck, king: c.position.king(c.position.turn));
    _shown = c.shownIndex;
    setState(() {});
  }

  void _settings() => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => ListenableBuilder(
          listenable: prefs,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // скорость ответа движка
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                title: Text('Engine reply: ${prefs.playReplyMs == 0 ? 'at once' : '${(prefs.playReplyMs / 1000).toStringAsFixed(1)} s or more'}'),
                subtitle: Slider(
                  min: 0,
                  max: 3000,
                  divisions: 12,
                  value: prefs.playReplyMs.toDouble(),
                  label: '${(prefs.playReplyMs / 1000).toStringAsFixed(2)} s',
                  onChanged: (v) => prefs.setPlayReplyMs(v.round()),
                ),
              ),
              if (c.friendly) SwitchListTile(
                title: const Text('Engine arrows'),
                subtitle: const Text('The best move as an arrow on your turn'),
                value: prefs.playArrows,
                onChanged: (v) {
                  prefs.update(playArrowsOn: v);
                  setState(() {});
                },
              ),
              if (c.friendly) SwitchListTile(
                title: const Text('Engine lines'),
                subtitle: const Text('The evaluation and the best line under the board'),
                value: prefs.playLines,
                onChanged: (v) {
                  prefs.update(playLinesOn: v);
                  setState(() {});
                },
              ),
            ]),
          ),
        ),
      );

  /// Friendly mode: best continuation as an arrow on the player's turn.
  List<BoardArrow> _arrows() {
    final e = c.shownEval;
    final hint = c.friendly && prefs.playArrows && e != null && e.pv.isNotEmpty && c.myTurn;
    final t = c.status == PlayStatus.blunder && !c.browsing ? c.threat : null;
    return [
      if (t != null) BoardArrow(t.from, t.to, const Color(0xD0D7322F)),
      if (hint) BoardArrow(NormalMove.fromUci(e.pv.first).from, NormalMove.fromUci(e.pv.first).to, const Color(0xB015781B)),
      ...c.arrowsShown,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Play the engine'), actions: [
        if (c.status != PlayStatus.setup)
          IconButton(
            tooltip: _pen ? 'Stop drawing' : 'Draw arrows',
            isSelected: _pen,
            onPressed: () => setState(() => _pen = !_pen),
            icon: const Icon(Icons.edit_outlined),
            selectedIcon: const Icon(Icons.edit_rounded),
          ),
        if (c.status != PlayStatus.setup)
          IconButton(tooltip: 'New game', onPressed: c.newGame, icon: const Icon(Icons.restart_alt_rounded)),
        // скорость ответа движка; в дружеской игре — ещё стрелки и линии
        IconButton(tooltip: 'Game settings', onPressed: _settings, icon: const Icon(Icons.tune_rounded)),
      ]),
      body: LayoutBuilder(builder: (context, box) {
        final size = math.min(box.maxWidth - 24, math.min(520.0, box.maxHeight * 0.6));
        // доска вне прокрутки: перетаскивание фигур не листает окно
        return Column(children: [
          const SizedBox(height: 12),
          Center(
            child: SizedBox.square(
              dimension: size,
              child: Stack(children: [
                ArrowDrawing(
                  flipped: c.player == Side.black,
                  pen: _pen,
                  onArrow: c.toggleArrow,
                  onMark: c.toggleMark,
                  child: Chessboard(
                    size: size,
                    controller: _board,
                    orientation: c.player,
                    onMove: (m, {viaDragAndDrop}) {
                      if (m is NormalMove) c.play(m);
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
                Positioned.fill(
                    child: ArrowLayer(arrows: _arrows(), marks: c.marksShown, flipped: c.player == Side.black)),
              ]),
            ),
          ),
          if (c.status != PlayStatus.setup) _navBar(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: c.status == PlayStatus.setup ? _setup(context) : _game(context),
              ),
            ),
          ),
        ]);
      }),
    );
  }

  Widget _navBar() => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(tooltip: 'Start', onPressed: c.shownIndex > 0 ? c.toStart : null, icon: const Icon(Icons.first_page)),
        IconButton(tooltip: 'Back', onPressed: c.shownIndex > 0 ? c.back : null, icon: const Icon(Icons.chevron_left)),
        IconButton(
            tooltip: 'Forward', onPressed: c.browsing ? c.forward : null, icon: const Icon(Icons.chevron_right)),
        IconButton(tooltip: 'Live position', onPressed: c.browsing ? c.toLive : null, icon: const Icon(Icons.last_page)),
      ]);

  Widget _setup(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(key: const ValueKey('setup'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text('Strength', style: Theme.of(context).textTheme.titleMedium)),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Level')),
            ButtonSegment(value: true, label: Text('Rating')),
          ],
          selected: {c.rating != null},
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          onSelectionChanged: (v) => c.setRating(v.first ? (c.rating ?? 1500) : null),
        ),
      ]),
      const SizedBox(height: 6),
      if (c.rating == null) ...[
        // уровни — в одну строку, листаются вбок
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: botLevels.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, i) {
              final l = botLevels[i];
              return ChoiceChip(
                  label: Text('Level ${l.number}'), selected: c.level == l, onSelected: (_) => c.setLevel(l));
            },
          ),
        ),
        const SizedBox(height: 4),
        Text('Stockfish 19 (light net): Skill Level ${c.level.skill}, depth ${c.level.depth}',
            style: TextStyle(fontSize: 12, color: scheme.outline)),
      ] else ...[
        // [авторское] рейтинг: движок держит точность этого рейтинга
        Text('Rating ${c.rating}', style: const TextStyle(fontWeight: FontWeight.w700)),
        Slider(
          min: 400,
          max: 2800,
          divisions: 48,
          value: c.rating!.toDouble(),
          label: '${c.rating}',
          onChanged: (v) => c.setRating((v / 50).round() * 50),
        ),
        Text(
            'The engine plays at the accuracy of this rating (about ${accuracyForRating(c.rating!).toStringAsFixed(0)}%): '
            'before each move it leaves out the moves that would drop its accuracy below it.',
            style: TextStyle(fontSize: 12, color: scheme.outline)),
      ],
      const SizedBox(height: 14),
      Text('Your colour', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 0, label: Text('White')),
          ButtonSegment(value: 1, label: Text('Random')),
          ButtonSegment(value: 2, label: Text('Black')),
        ],
        selected: {c.chosenSide == null ? 1 : (c.chosenSide == Side.white ? 0 : 2)},
        showSelectedIcon: false,
        onSelectionChanged: (s) => c.setSide(switch (s.first) { 0 => Side.white, 2 => Side.black, _ => null }),
      ),
      const SizedBox(height: 8),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Friendly game'),
        subtitle: const Text('Takebacks, evaluation and the best continuation'),
        value: c.friendly,
        onChanged: c.setFriendly,
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton.icon(onPressed: c.start, icon: const PawnIcon(), label: const Text('Play')),
      ),
    ]);
  }

  String _evalText(EngineEval e, Side toMove) {
    final white = toMove == Side.white;
    if (e.mate != null) return '#${white ? e.mate : -e.mate!}';
    final v = (white ? e.cp! : -e.cp!) / 100;
    return '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}';
  }

  String _sanLine(Pos start, List<String> pv) {
    var b = start;
    final out = <String>[];
    for (final uci in pv.take(16)) {
      final m = NormalMove.fromUci(uci);
      if (!b.isLegal(m)) break;
      out.add(b.san(m));
      b = b.push(m);
    }
    return out.join(' ');
  }

  Widget _game(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final String status = switch (c.status) {
      PlayStatus.starting => 'Starting the engine…',
      PlayStatus.thinking => 'Engine is thinking…',
      PlayStatus.playing => c.browsing ? 'Viewing move ${c.shownIndex}' : (c.myTurn ? 'Your move' : ''),
      PlayStatus.blunder => 'A blunder: ${c.blunderLoss >= 99 ? 'it lets the engine mate' : 'it loses ${c.blunderLoss.toStringAsFixed(1)} pawns'}',
      PlayStatus.over => '${c.reason}: ${c.result}',
      PlayStatus.failed => 'The engine did not start: ${c.error}',
      PlayStatus.setup => '',
    };
    final e = c.shownEval;
    return Column(key: const ValueKey('game'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        if (c.status == PlayStatus.thinking || c.status == PlayStatus.starting) ...[
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 8),
        ],
        Expanded(child: Text(status, style: const TextStyle(fontWeight: FontWeight.w700))),
        Text('${c.rated != null ? 'Rating ${c.rated!.rating}' : 'Level ${c.level.number}'}${c.friendly ? ' · Friendly' : ''}',
            style: TextStyle(color: scheme.outline)),
      ]),
      // по рейтингу: точность движка в этой партии против точности рейтинга
      if (c.rated case final r?)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('Engine accuracy ${r.accuracy.toStringAsFixed(1)}% · target ${r.target.toStringAsFixed(1)}%',
              style: TextStyle(fontSize: 12, color: scheme.outline)),
        ),
      // дружеская партия: зевок — партия стоит; стрелка показывает ответ движка
      if (c.status == PlayStatus.blunder && c.threat != null)
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('The engine would answer ${c.live.san(c.threat!)} (the red arrow) and will not miss it.',
                style: TextStyle(color: scheme.onErrorContainer)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(onPressed: c.takeback, icon: const Icon(Icons.undo_rounded), label: const Text('Take it back')),
              OutlinedButton.icon(onPressed: c.playOn, icon: const Icon(Icons.play_arrow_rounded), label: const Text('Play on')),
            ]),
          ]),
        ),
      if (c.friendly && prefs.playLines && e != null) ...[
        const SizedBox(height: 6),
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(8)),
            child: Text(_evalText(e, c.position.turn), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FadedLine('Best: ${_sanLine(c.position, e.pv)}', style: TextStyle(fontSize: 13, color: scheme.outline)),
          ),
        ]),
      ],
      const SizedBox(height: 8),
      Wrap(spacing: 4, runSpacing: 2, children: [
        for (var i = 0; i < c.sans.length; i++)
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => c.view(i + 1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: c.shownIndex == i + 1 ? scheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('${i.isEven ? '${i ~/ 2 + 1}. ' : ''}${c.sans[i]}',
                  style: TextStyle(color: c.shownIndex == i + 1 ? scheme.onPrimary : null)),
            ),
          ),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (c.friendly)
          OutlinedButton.icon(
              onPressed: c.canTakeback ? c.takeback : null,
              icon: const Icon(Icons.undo_rounded),
              label: const Text('Take back')),
        if (c.status == PlayStatus.playing || c.status == PlayStatus.thinking)
          OutlinedButton.icon(onPressed: c.resign, icon: const Icon(Icons.flag_rounded), label: const Text('Resign')),
        if (c.status == PlayStatus.over || c.status == PlayStatus.failed)
          FilledButton.icon(onPressed: c.newGame, icon: const Icon(Icons.restart_alt_rounded), label: const Text('New game')),
      ]),
    ]);
  }
}
