/// Analysis board: the position after the selected move.
///
/// Over the chessground board lies an own layer:
/// - the move's icon in the corner of its destination square: it appears
///   after the piece has arrived, with a short flash; brilliant and blunder
///   also make the sign jump and send an outline flying out of the badge;
/// - legal moves of the touched piece as an inset outline in the opposite
///   square colour (inset, so it does not merge with like-coloured
///   neighbours).
/// The last move's squares are tinted with the step colour.
///
/// Arrows: green for the best move when the played one was not among the
/// best; red for the idea's attacker, along its route when the target is not
/// hit directly (two moves of a bishop); circles for a selected lock line.
///
/// Any legal move can be played on the board: a move different from the game
/// starts an own variation (see AnalysisController). Swipe to step.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' hide Board;
import 'package:flutter/material.dart';

import '../../analysis/paths.dart';
import '../controller.dart';
import '../prefs.dart';
import '../step_icons.dart';
import 'arrows.dart';
import 'board_background.dart';

const _bestColor = Color(0xB015781B);
const _ideaColor = Color(0xCCC62828);
const _sliderColor = Color(0xCC1565C0);
const _targetColor = Color(0xCCC62828);
const _ownLockColor = Color(0xCCF0A23A);
const _defLockColor = Color(0xCC2F8A4C);
const _variationLastMove = Color(0x66607D8B);

/// How long a piece takes to move (Settings).
Duration get boardAnimation => Duration(milliseconds: prefs.moveAnimationMs);

/// Last-move tint for [kind] (null: own variation).
Color lastMoveTint(String? kind) => kind == null ? _variationLastMove : markColor(kind).withValues(alpha: 0.5);

/// Board colours with the last move tinted by [kind] (static boards).
ChessboardColorScheme boardScheme(String? kind) =>
    prefs.scheme.copyWith(lastMove: HighlightDetails(solidColor: lastMoveTint(kind)));

/// Icon kind of the shown move: the move's step, the game end (resign /
/// timeout), a variation move's verdict; null at the start and for own moves
/// outside the engine lines.
String? shownKind(AnalysisController c) {
  if (c.inVariation) return c.varMove!.kind;
  if (c.atStart) return null;
  if (c.atEnd) return c.end!.kind;
  return c.kindAt(c.ply);
}

/// Badge colour: the resignation takes the colour of its grade; checkmate is
/// green or red depending on whose side the board is seen from.
Color shownColor(AnalysisController c, String kind) {
  if (kind == 'resign') return markColor(c.end!.step!);
  if (kind == 'mate' && !c.inVariation) return c.kindColorAt(c.ply, kind);
  return markColor(kind);
}

/// Static copy of the shown position for the Hero flight: sized by the flight
/// rectangle, without the overlay, so nothing skews or shows raw text. With
/// [from] (the home card's position) it crossfades from that position to the
/// shown one as [animation] runs.
Widget flightBoard(AnalysisController c,
        {({String fen, Move? lastMove, String? kind})? from, Animation<double>? animation}) =>
    LayoutBuilder(builder: (context, box) {
      final size = box.biggest.shortestSide;
      Widget board(String fen, Move? lastMove, String? kind) => StaticChessboard(
            size: size,
            orientation: c.flipped ? Side.black : Side.white,
            fen: fen,
            lastMove: lastMove,
            settings: StaticChessboardSettings(
              colorScheme: boardScheme(kind),
              pieceAssets: prefs.pieceSet.assets,
              borderRadius: const BorderRadius.all(Radius.circular(6)),
            ),
          );
      final shown = board(c.position.fen, c.lastMove, shownKind(c));
      if (from == null || animation == null) return shown;
      return Stack(children: [
        board(from.fen, from.lastMove, from.kind),
        FadeTransition(opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut), child: shown),
      ]);
    });

class BoardView extends StatefulWidget {
  const BoardView({super.key, required this.controller, required this.size});

  final AnalysisController controller;
  final double size;

  @override
  State<BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<BoardView> {
  late final ChessboardController _board;
  Object? _shownKey;
  int _shownIndex = 0;
  bool _animated = false;
  bool _backward = false;

  /// Badge shown before the last change, faded out when stepping back.
  ({String kind, Color color, Offset center, Object key})? _shown, _leaving;
  bool _swipeOnPiece = false;

  AnalysisController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _board = ChessboardController(game: _gameData());
    _syncCheck();
    _shownKey = c.positionKey;
    _shownIndex = c.shownPlyIndex;
    c.addListener(_onChange);
    prefs.addListener(_onPrefs);
  }

  void _onPrefs() => setState(() {});

  @override
  void dispose() {
    c.removeListener(_onChange);
    prefs.removeListener(_onPrefs);
    _board.dispose();
    super.dispose();
  }

  GameData _gameData() {
    final pos = c.position;
    return GameData(
      fen: pos.fen,
      lastMove: c.lastMove,
      playerSide: PlayerSide.both,
      sideToMove: pos.turn,
      kingSquareInCheck: null, // шах рисует фон доски: вся клетка короля красная
      validMoves: makeLegalMoves(pos.p),
    );
  }

  void _onChange() {
    final key = c.positionKey;
    lightenOf(_board).value = c.inVariation;
    if (key != _shownKey) {
      // соседний ход партии или ветки — фигуры едут; прыжки — сразу
      // фигуры едут только на соседний ход: два хода сразу сбивают с толку
      final near = key is int && _shownKey is int ? ((key - (_shownKey as int)).abs() <= 1) : true;
      _board.updatePosition(_gameData(), animate: near);
      _syncCheck();
      _backward = c.shownPlyIndex < _shownIndex;
      // шаг назад: значок отменённого хода гаснет, значок прошлого хода — сразу
      _leaving = _backward ? _shown : null;
      _animated = near && !_backward;
      _shownKey = key;
      _shownIndex = c.shownPlyIndex;
    }
    setState(() {});
  }

  /// Engine and idea arrows of the shown position, filled by [_shapes].
  final _arrows = <BoardArrow>[];

  /// Lock circles (chessground shapes); arrows go to [_arrows].
  void _syncCheck() {
    final pos = c.position;
    syncCheck(_board, inCheck: pos.isCheck, king: pos.king(pos.turn));
    // своя ветка на доске — доска чуть светлее (идея — синий контур)
    lightenOf(_board).value = c.inVariation;
  }

  Set<Shape> _shapes() {
    _arrows.clear();
    final shapes = <Shape>{};

    final lock = c.inVariation ? null : c.lockShown();
    if (lock != null) {
      shapes.add(Circle(color: _sliderColor, orig: lock.slider));
      shapes.add(Circle(color: _targetColor, orig: lock.target));
      for (final l in lock.locks) {
        shapes.add(Circle(color: l.side == lock.side ? _ownLockColor : _defLockColor, orig: l.square, scale: 0.8));
      }
      if (lock.open) _arrows.add(BoardArrow(lock.slider, lock.target, _targetColor, scale: 0.7));
      return shapes;
    }
    // стрелки лучшего хода и идеи — только у ходов партии
    if (c.inVariation || c.atStart || c.atEnd) return shapes;

    final r = c.analysis.records[c.ply];
    final idea = c.selectedIdea;
    if (idea != null) {
      final e = c.chainEntryShown();
      if (e != null && e.attacker != e.target) {
        // по маршруту фигуры: слон c8 бьёт f3 только за два своих хода
        final path = piecePath(c.position, e.attacker, e.target) ?? const <Square>[];
        for (var i = 0; i + 1 < path.length; i++) {
          if (prefs.showIdeaArrows) {
            _arrows.add(BoardArrow(path[i], path[i + 1], _ideaColor, scale: path.length > 2 ? 0.8 : 1));
          }
        }
      }
      if (c.ply != idea.missPly && c.ply != idea.punishPly) return shapes;
    }

    final best = r.bestMoves.firstOrNull;
    final playedIsBest = r.bestMoves.any((m) => m.uci == r.uci);
    if (best != null && !playedIsBest && r.step != 'forced' && r.step != 'book') {
      final b = NormalMove.fromUci(best.uci);
      if (prefs.showBestArrow) _arrows.add(BoardArrow(b.from, b.to, _bestColor));
    }
    return shapes;
  }

  /// Whether the arrow's path (centre to centre, a knight's through its
  /// corner) comes within [r] of [p].
  bool _passesNear(BoardArrow a, Offset p, double r, double sq) {
    Offset at(Square s) => _squareOrigin(s, sq) + Offset(sq / 2, sq / 2);
    final df = a.to.file - a.from.file, dr = a.to.rank - a.from.rank;
    final pts = [at(a.from)];
    if ({df.abs(), dr.abs()}.containsAll({1, 2}) && df.abs() != dr.abs()) {
      pts.add(at(dr.abs() == 2 ? Square.fromCoords(a.from.file, a.to.rank) : Square.fromCoords(a.to.file, a.from.rank)));
    }
    pts.add(at(a.to));
    for (var i = 0; i + 1 < pts.length; i++) {
      final u = pts[i], v = pts[i + 1], d = v - u;
      final len2 = d.dx * d.dx + d.dy * d.dy;
      final k = len2 == 0 ? 0.0 : (((p - u).dx * d.dx + (p - u).dy * d.dy) / len2).clamp(0.0, 1.0);
      if ((u + d * k - p).distance < r) return true;
    }
    return false;
  }

  Offset _squareOrigin(Square sq, double s) {
    final x = c.flipped ? 7 - sq.file : sq.file;
    final y = c.flipped ? sq.rank : 7 - sq.rank;
    return Offset(x * s, y * s);
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final sq = size / 8;
    final kind = shownKind(c);
    final shapes = _shapes();
    // у конца партии значок стоит на короле сдавшегося
    final dest = c.atEnd ? c.position.king(c.end!.loser)! : (c.lastMove?.to ?? Square.a1);
    final badge = sq * 0.51;
    // бейдж — в правом верхнем углу клетки, слегка за её краем; у края доски
    // угол меняется: у верхнего края — нижний, у правого — левый
    final origin = _squareOrigin(dest, sq);
    final atRight = origin.dx + sq >= size - 1;
    final atTop = origin.dy <= 1;
    final center = Offset(
      atRight ? origin.dx + badge * 0.06 : origin.dx + sq - badge * 0.06,
      atTop ? origin.dy + sq - badge * 0.06 : origin.dy + badge * 0.06,
    );
    // стрелки через клетку хода или через сам значок (он залезает на
    // соседние клетки) — позже и полупрозрачные
    if (kind != null && prefs.showBoardIcons) {
      for (var i = 0; i < _arrows.length; i++) {
        final a = _arrows[i];
        if (a.squares.contains(dest) || _passesNear(a, center, badge / 2 + sq * 0.1, sq)) {
          _arrows[i] = BoardArrow(a.from, a.to, a.color, scale: a.scale, muted: true);
        }
      }
    }
    // тот же ход, другой вердикт (анализ пересчитал) — значок переворачивается
    final changed = kind != null && _shown != null && _shown!.key == c.positionKey && _shown!.kind != kind;
    _shown = kind == null ? null : (kind: kind, color: shownColor(c, kind), center: center, key: c.positionKey);

    return GestureDetector(
      onHorizontalDragStart: (d) {
        final local = d.localPosition;
        final file = (local.dx / sq).floor().clamp(0, 7);
        final rank = (local.dy / sq).floor().clamp(0, 7);
        final square = Square.fromCoords(
            File(c.flipped ? 7 - file : file), Rank(c.flipped ? rank : 7 - rank));
        final piece = c.position.pieceAt(square);
        _swipeOnPiece = piece != null && piece.color == c.position.turn;
      },
      onHorizontalDragEnd: (d) {
        if (_swipeOnPiece || c.pen) return; // перетаскивание фигуры или рисование, а не листание
        final v = d.primaryVelocity ?? 0;
        if (v < -150) c.next();
        if (v > 150) c.prev();
      },
      child: SizedBox.square(
        dimension: size,
        child: Stack(clipBehavior: Clip.none, children: [
          ArrowDrawing(
            flipped: c.flipped,
            pen: c.pen,
            onArrow: c.toggleArrow,
            onMark: c.toggleMark,
            child: Chessboard(
              size: size,
              controller: _board,
              orientation: c.flipped ? Side.black : Side.white,
              onMove: (m, {viaDragAndDrop}) {
                if (m is NormalMove) c.playMove(m);
              },
              settings: ChessboardSettings(
                // покраску клеток хода можно выключить в быстрых настройках
                colorScheme: appScheme(_board,
                    lastMove: prefs.showSquareTint ? lastMoveTint(kind) : const Color(0x00000000)),
                pieceAssets: prefs.pieceSet.assets,
                animationDuration: boardAnimation,
                borderRadius: const BorderRadius.all(Radius.circular(6)),
                boxShadow: kElevationToShadow[3]!,
              ),
              shapes: shapes,
            ),
          ),
          Positioned.fill(
              child: ArrowLayer(arrows: [..._arrows, ...c.arrowsShown], marks: c.marksShown, flipped: c.flipped)),
          // выбрана идея — контур доски цвета и толщины контура блока идеи
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: c.selectedIdea != null ? Theme.of(context).colorScheme.tertiary : Colors.transparent,
                      width: 2),
                ),
              ),
            ),
          ),
          if (_leaving case final l?)
            Positioned(
              left: l.center.dx - badge / 2,
              top: l.center.dy - badge / 2,
              width: badge,
              height: badge,
              child: IgnorePointer(
                child: BoardBadge(
                    key: ValueKey(('leaving', l.key)), kind: l.kind, color: l.color, size: badge, leaving: true),
              ),
            ),
          if (kind != null && prefs.showBoardIcons)
            Positioned(
              left: center.dx - badge / 2,
              top: center.dy - badge / 2,
              width: badge,
              height: badge,
              child: IgnorePointer(
                child: BoardBadge(
                  key: ValueKey('${c.positionKey}-$kind'),
                  kind: kind,
                  color: shownColor(c, kind),
                  size: badge,
                  delay: _animated && !changed ? boardAnimation : Duration.zero,
                  quiet: _backward,
                  changed: changed,
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// The move's icon on the board. It waits for the piece to arrive, then:
/// - brilliant and only move: appear with a flash (best: a faster flash);
/// - the rest: a quick fade-in;
/// - brilliant and blunder: the sign jumps and an outline flies out (blunder
///   jumps at once, without a flash).
/// [leaving] plays the fade backwards (stepping back to an earlier move);
/// [quiet] shows the badge with only the quick fade.
class BoardBadge extends StatefulWidget {
  const BoardBadge({
    super.key,
    required this.kind,
    required this.size,
    this.color,
    this.delay = Duration.zero,
    this.leaving = false,
    this.quiet = false,
    this.changed = false,
  });

  final String kind;
  final Color? color;

  /// The verdict of the same move changed (new engine data): a flip.
  final bool changed;
  final double size;
  final Duration delay;
  final bool leaving;
  final bool quiet;

  @override
  State<BoardBadge> createState() => _BoardBadgeState();
}

class _BoardBadgeState extends State<BoardBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: _duration);
  Timer? _wait;

  bool get _calm => widget.quiet || widget.leaving || widget.changed;
  bool get _flash => !_calm && flashesIn(widget.kind);
  bool get _loud => !_calm && isLoudKind(widget.kind);
  bool get _jumps => !_calm && jumpsIn(widget.kind);

  Duration get _duration {
    if (widget.leaving || widget.quiet) return const Duration(milliseconds: 180);
    if (widget.changed) return const Duration(milliseconds: 520);
    return switch (widget.kind) {
      'brilliant' => const Duration(milliseconds: 1000),
      'only_move' => const Duration(milliseconds: 1000),
      'only_light' => const Duration(milliseconds: 800),
      'best' => const Duration(milliseconds: 420),
      'blunder' => const Duration(milliseconds: 650),
      'resign' || 'timeout' => const Duration(milliseconds: 1400),
      _ => const Duration(milliseconds: 180),
    };
  }

  @override
  void initState() {
    super.initState();
    if (widget.leaving) {
      _a.value = 1;
      _a.reverse();
    } else if (widget.delay == Duration.zero) {
      _a.forward();
    } else {
      _wait = Timer(widget.delay, () {
        if (mounted) _a.forward();
      });
    }
  }

  @override
  void dispose() {
    _wait?.cancel();
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? markColor(widget.kind);
    // вспышка: значок раскрывается из светлого; остальные просто проявляются
    final moving = !_calm && (widget.kind == 'resign' || widget.kind == 'timeout');
    final fadeEnd = _flash ? 0.18 : (_loud ? 0.25 : (moving ? 0.15 : 1.0));
    final fade = CurvedAnimation(parent: _a, curve: Interval(0, fadeEnd, curve: Curves.easeOut));
    final appear = CurvedAnimation(parent: _a, curve: const Interval(0, 0.3, curve: Curves.easeOutBack));
    final flash = CurvedAnimation(parent: _a, curve: const Interval(0.08, 0.55, curve: Curves.easeOut));
    // у brilliant прыжок после вспышки, у blunder — сразу после проявления
    final (j0, j1) = widget.kind == 'brilliant' || widget.kind == 'only_move' ? (0.45, 0.85) : (0.15, 0.7);
    return AnimatedBuilder(
      animation: _a,
      builder: (context, _) {
        final t = _a.value;
        var jump = 1.0;
        if (_jumps && t > j0 && t < j1) {
          final u = (t - j0) / (j1 - j0);
          jump = 1 + 0.25 * math.sin(math.pi * Curves.easeOut.transform(u));
        }
        // флаг сдачи колышется и затихает; стрелка часов делает оборот
        var angle = 0.0;
        if (moving && widget.kind == 'resign') angle = 0.35 * math.sin(t * 4 * math.pi) * (1 - t);
        // time out: стрелка делает оборот, к концу оборота часы
        // приближаются и быстро качаются — «звонят»
        var hand = clockHand;
        var zoom = 1.0;
        if (moving && widget.kind == 'timeout') {
          hand = clockHand + 2 * math.pi * Curves.easeInOutCubic.transform((t / 0.6).clamp(0.0, 1.0));
          if (t > 0.5) {
            final u = (t - 0.5) / 0.5;
            final env = math.sin(math.pi * u);
            zoom = 1 + 0.3 * env;
            angle = 0.28 * math.sin(u * 12 * math.pi) * env;
          }
        }
        final icon = StepIcon(
          kind: widget.kind,
          color: color,
          size: widget.size,
          glyphScale: jump * zoom,
          glyphAngle: angle,
          hand: hand,
          brighten: _flash ? 0.75 * (1 - flash.value) : 0,
        );
        if (widget.changed) {
          // переворот: значок сжимается в ребро и раскрывается новым, со вспышкой
          final flip = Curves.easeOutBack.transform(t);
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(flip.clamp(0.05, 1.2), 1, 1),
            child: StepIcon(kind: widget.kind, color: color, size: widget.size, brighten: 0.6 * (1 - t)),
          );
        }
        return Stack(clipBehavior: Clip.none, children: [
          if (_loud && t > j0)
            Positioned.fill(
                child: CustomPaint(painter: FlyOutPainter(((t - j0) / 0.5).clamp(0, 1), color, circle: true))),
          Opacity(
            opacity: fade.value.clamp(0.0, 1.0),
            child: _flash ? Transform.scale(scale: 0.45 + 0.55 * appear.value, child: icon) : icon,
          ),
        ]);
      },
    );
  }
}

/// An outline that leaves the frame and fades quickly ([t] 0..1). Circle for
/// the board badge, stadium for the card badge.
class FlyOutPainter extends CustomPainter {
  FlyOutPainter(this.t, this.color, {this.circle = false});

  final double t;
  final Color color;
  final bool circle;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final e = Curves.easeOutCubic.transform(t);
    final grow = size.shortestSide * 0.55 * e;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, size.shortestSide * 0.12 * (1 - e))
      ..color = color.withValues(alpha: 0.85 * math.pow(1 - t, 1.6).toDouble());
    final rect = (Offset.zero & size).inflate(grow);
    if (circle) {
      canvas.drawOval(rect, paint);
    } else {
      canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2)), paint);
    }
  }

  @override
  bool shouldRepaint(FlyOutPainter old) => old.t != t || old.color != color;
}
