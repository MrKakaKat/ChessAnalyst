/// Settings: arrow style, legal-move display, board colours and piece set.
library;

import 'package:chessground/chessground.dart' hide GameData;
import 'dart:async';

import 'package:chessground/chessground.dart' as cg show GameData;
import 'package:dartchess/dartchess.dart' show Square, Side, makeLegalMoves;
import 'package:flutter/material.dart';

import '../analysis/pos.dart';
import 'prefs.dart';
import 'widgets/board_background.dart';
import 'widgets/arrows.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    prefs.addListener(_rebuild);
  }

  @override
  void dispose() {
    prefs.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final title = Theme.of(context).textTheme.titleMedium;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Arrows', style: title),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 12, children: [
          for (final s in ArrowStyle.values)
            _ArrowSample(style: s, selected: prefs.arrowStyle == s, onTap: () => prefs.update(arrow: s)),
        ]),
        const SizedBox(height: 12),
        Text('Colour of your arrows', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 6),
        Wrap(spacing: 10, children: [
          for (final e in arrowColors.entries)
            Tooltip(
              message: e.key,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => prefs.update(color: e.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: e.value,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: prefs.arrowColor == e.key ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                        width: 3),
                  ),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        Text('Colour of marked squares (tap a square with the pen)', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 6),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final e in markColors.entries)
            Tooltip(
              message: e.key,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => prefs.update(mark: e.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: e.value.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: prefs.markColor == e.key ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                        width: 3),
                  ),
                ),
              ),
            ),
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Draw arrows in'),
          subtitle: const Text('A new arrow grows from its start to its end'),
          value: prefs.animateArrows,
          onChanged: (v) => prefs.update(animate: v),
        ),
        const SizedBox(height: 12),
        Text('Move animation', style: title),
        const SizedBox(height: 8),
        // карточка-пример: g6, Bg7, Nf6 с выбранной скоростью
        Row(children: [
          const _MoveSpeedPreview(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${prefs.moveAnimationMs} ms per move'),
              Slider(
                min: 0,
                max: 800,
                divisions: 16,
                value: prefs.moveAnimationMs.toDouble(),
                label: '${prefs.moveAnimationMs} ms',
                onChanged: (v) => prefs.update(moveMs: v.round()),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Text('Idea playback', style: title),
        Text('${(prefs.ideaStepMs / 1000).toStringAsFixed(1)} s per move'),
        Slider(
          min: 400,
          max: 3000,
          divisions: 26,
          value: prefs.ideaStepMs.toDouble(),
          label: '${(prefs.ideaStepMs / 1000).toStringAsFixed(1)} s',
          onChanged: (v) => prefs.update(ideaStep: v.round()),
        ),
        const SizedBox(height: 12),
        Text('Engine', style: title),
        const SizedBox(height: 4),
        Text('Lines per move in new analyses: ${prefs.engineLines}', style: Theme.of(context).textTheme.bodyMedium),
        Slider(
          min: 5,
          max: 25,
          divisions: 20,
          value: prefs.engineLines.toDouble(),
          label: '${prefs.engineLines}',
          onChanged: (v) => prefs.update(lines: v.round()),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Analyze own moves'),
          subtitle: const Text('Your moves in branches are judged by the engine on the device'),
          value: prefs.analyzeOwnMoves,
          onChanged: (v) => prefs.update(ownMoves: v),
        ),
        const SizedBox(height: 12),
        Text('Legal moves of a piece', style: title),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (v, label) in const [
            (LegalMoves.outline, 'Rounded outline'),
            (LegalMoves.squares, 'Square outline'),
            (LegalMoves.dots, 'Dots'),
            (LegalMoves.contrastDots, 'Contrast dots'),
            (LegalMoves.none, 'Hidden'),
          ])
            ChoiceChip(
              label: Text(label),
              selected: prefs.legalMoves == v,
              showCheckmark: false,
              onSelected: (_) => prefs.update(legal: v),
            ),
        ]),
        const SizedBox(height: 20),
        Text('Board', style: title),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final e in boardThemes.entries)
            _BoardSample(name: e.key, scheme: e.value, selected: prefs.boardTheme == e.key,
                onTap: () => prefs.update(theme: e.key)),
        ]),
        const SizedBox(height: 20),
        Text('Pieces', style: title),
        const SizedBox(height: 8),
        DropdownButton<PieceSet>(
          value: prefs.pieceSet,
          isExpanded: true,
          items: [for (final p in PieceSet.values) DropdownMenuItem(value: p, child: Text(p.label))],
          onChanged: (p) => prefs.update(pieces: p),
        ),
        const SizedBox(height: 8),
        Center(
          child: StaticChessboard(
            size: 240,
            orientation: Side.white,
            fen: 'r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4',
            settings: StaticChessboardSettings(
              colorScheme: prefs.scheme,
              pieceAssets: prefs.pieceSet.assets,
              borderRadius: const BorderRadius.all(Radius.circular(6)),
            ),
          ),
        ),
      ]),
    );
  }
}

class _ArrowSample extends StatelessWidget {
  const _ArrowSample({required this.style, required this.selected, required this.onTap});

  final ArrowStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // у каждого образца — свой стиль, независимо от выбранного
    final layer = ArrowLayer(arrows: [
      // образцы — выбранным цветом своих стрелок
      BoardArrow(Square.a1, Square.a4, prefs.userArrowColor),
      BoardArrow(Square.c1, Square.d3, prefs.userArrowColor),
      BoardArrow(Square.h1, Square.e4, prefs.userArrowColor),
    ], flipped: false, style: style, animate: false);
    final picture = SizedBox(
      width: 120,
      height: 120,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.bottomLeft,
          maxWidth: 240,
          maxHeight: 240,
          child: SizedBox(
            width: 240,
            height: 240,
            child: Stack(children: [
              StaticChessboard(size: 240, orientation: Side.white, fen: '8/8/8/8/8/8/8/8 w - - 0 1',
                  settings: StaticChessboardSettings(colorScheme: prefs.scheme)),
              Positioned.fill(child: layer),
            ]),
          ),
        ),
      ),
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2.5 : 1),
        ),
        child: Column(children: [
          picture,
          const SizedBox(height: 4),
          Text(switch (style) {
            ArrowStyle.classic => 'Classic',
            ArrowStyle.blunt => 'Blunt',
            ArrowStyle.slim => 'Slim',
            ArrowStyle.bold => 'Bold',
          }),
        ]),
      ),
    );
  }
}

class _BoardSample extends StatelessWidget {
  const _BoardSample({required this.name, required this.scheme, required this.selected, required this.onTap});

  final String name;
  final ChessboardColorScheme scheme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? cs.primary : cs.outlineVariant, width: selected ? 2.5 : 1),
        ),
        child: Column(children: [
          SizedBox(
            width: 48,
            height: 48,
            child: GridView.count(
              crossAxisCount: 2,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                ColoredBox(color: scheme.lightSquare),
                ColoredBox(color: scheme.darkSquare),
                ColoredBox(color: scheme.darkSquare),
                ColoredBox(color: scheme.lightSquare),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Text(name, style: const TextStyle(fontSize: 12)),
        ]),
      ),
    );
  }
}

/// A small board playing g6, Bg7, Nf6 over and over at the chosen speed.
class _MoveSpeedPreview extends StatefulWidget {
  const _MoveSpeedPreview();

  @override
  State<_MoveSpeedPreview> createState() => _MoveSpeedPreviewState();
}

class _MoveSpeedPreviewState extends State<_MoveSpeedPreview> {
  // после 1. e4 d6 2. d4 — фианкетто и развитие коня чёрных
  static final _start = Pos.fromFen('rnbqkbnr/ppp1pppp/3p4/8/3PP3/8/PPP2PPP/RNBQKBNR b KQkq - 0 2');
  static const _moves = ['g7g6', 'f8g7', 'g8f6'];

  late final ChessboardController _board = ChessboardController(game: _data(_start));
  Timer? _timer;
  int _step = 0;
  Pos _pos = _start;

  cg.GameData _data(Pos p) => cg.GameData(
        fen: p.fen,
        playerSide: PlayerSide.none,
        sideToMove: p.turn,
        kingSquareInCheck: null,
        validMoves: makeLegalMoves(p.p),
      );

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 1000), (_) => _tick());
  }

  void _tick() {
    if (_step >= _moves.length) {
      _step = 0;
      _pos = _start;
      _board.updatePosition(_data(_pos), animate: false);
      return;
    }
    // ходят только чёрные: между их ходами — пропуск хода белых
    final m = Pos.move(_moves[_step++]);
    _pos = _pos.push(m);
    final shown = _step < _moves.length ? _pos.nullMove() : _pos;
    _board.updatePosition(_data(shown), animate: true);
    if (_step < _moves.length) _pos = shown;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _board.dispose();
    super.dispose();
  }

  /// Only the corner where the moves are played: f6–h8, 3×3 squares (from
  /// Black's side it is the bottom left).
  @override
  Widget build(BuildContext context) {
    const shown = 132.0, full = shown * 8 / 3;
    return SizedBox.square(
      dimension: shown,
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(6)),
        child: OverflowBox(
          alignment: Alignment.bottomLeft,
          minWidth: full,
          maxWidth: full,
          minHeight: full,
          maxHeight: full,
          child: IgnorePointer(
            child: Chessboard(
              size: full,
              controller: _board,
              orientation: Side.black,
              onMove: null,
              settings: ChessboardSettings(
                colorScheme: appScheme(_board),
                pieceAssets: prefs.pieceSet.assets,
                animationDuration: Duration(milliseconds: prefs.moveAnimationMs),
                enableCoordinates: false,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

