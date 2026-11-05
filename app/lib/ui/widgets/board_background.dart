/// Board squares painted by the app, shared by the analysis and play boards:
/// the colour theme from the settings, coordinates that fade in (also after
/// a flip), and the legal moves of the touched piece as inset outlines in the
/// opposite square colour (under the pieces). With "dots" in the settings the
/// board shows chessground's dots instead; with "none", nothing.
library;

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' show Side, Square;
import 'package:flutter/material.dart';

import '../prefs.dart';

final _cache = Expando<Map<String, ChessboardBackground>>();
final _checks = Expando<ValueNotifier<Square?>>();

/// The king in check on [board]: its whole square is painted red (instead of
/// chessground's soft circle). Set by the screen after each position change.
ValueNotifier<Square?> checkSquareOf(ChessboardController board) => _checks[board] ??= ValueNotifier(null);

final _lighten = Expando<ValueNotifier<bool>>();

/// Lightens the squares of [board] a little (a branch or an idea is shown).
ValueNotifier<bool> lightenOf(ChessboardController board) => _lighten[board] ??= ValueNotifier(false);

/// Updates [checkSquareOf] for [pos]-like data.
void syncCheck(ChessboardController board, {required bool inCheck, Square? king}) =>
    checkSquareOf(board).value = inCheck ? king : null;

/// The settings' colour scheme for [board], with our background and, when
/// given, the last-move tint.
ChessboardColorScheme appScheme(ChessboardController board, {Color? lastMove}) {
  final base = prefs.scheme;
  final cache = _cache[board] ??= {};
  ChessboardBackground bg(Side side) => cache.putIfAbsent(
      '${side.name}-${prefs.boardTheme}-${prefs.legalMoves.name}',
      () => AppBoardBackground(board: board, orientation: side, scheme: base));
  return base.copyWith(
    lastMove: lastMove != null ? HighlightDetails(solidColor: lastMove) : null,
    validMoves: prefs.legalMoves == LegalMoves.dots ? base.validMoves : const Color(0x00000000),
    whiteCoordBackground: bg(Side.white),
    blackCoordBackground: bg(Side.black),
  );
}

class AppBoardBackground extends ChessboardBackground {
  AppBoardBackground({super.key, required this.board, required super.orientation, required this.scheme})
      : super(coordinates: true, lightSquare: scheme.lightSquare, darkSquare: scheme.darkSquare);

  final ChessboardController board;
  final ChessboardColorScheme scheme;

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        SolidColorChessboardBackground(lightSquare: lightSquare, darkSquare: darkSquare),
        ValueListenableBuilder<bool>(
          valueListenable: lightenOf(board),
          builder: (context, on, _) => AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            color: Colors.white.withValues(alpha: on ? 0.16 : 0),
          ),
        ),
        CustomPaint(painter: _CheckPainter(checkSquareOf(board), orientation == Side.black)),
        // координаты проявляются плавно — при открытии и после разворота
        TweenAnimationBuilder<double>(
          key: ValueKey(orientation),
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOut,
          builder: (context, t, _) => CustomPaint(
            painter: _CoordsPainter(orientation, lightSquare, darkSquare, t),
          ),
        ),
        if (prefs.legalMoves == LegalMoves.outline)
          CustomPaint(painter: _DestsPainter(board, orientation == Side.black, lightSquare, darkSquare)),
      ]);
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.square, this.flipped) : super(repaint: square);

  final ValueNotifier<Square?> square;
  final bool flipped;

  @override
  void paint(Canvas canvas, Size size) {
    final s = square.value;
    if (s == null) return;
    final sq = size.shortestSide / 8;
    final x = flipped ? 7 - s.file : s.file;
    final y = flipped ? s.rank : 7 - s.rank;
    // цвет зевка, но прозрачнее
    canvas.drawRect(Rect.fromLTWH(x * sq, y * sq, sq, sq), Paint()..color = const Color(0x8CD7322F));
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.square != square || old.flipped != flipped;
}

class _CoordsPainter extends CustomPainter {
  _CoordsPainter(this.orientation, this.light, this.dark, this.t);

  final Side orientation;
  final Color light, dark;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final sq = size.shortestSide / 8;
    void label(String s, Offset at, Color c, {bool right = false}) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(
            inherit: false,
            fontWeight: FontWeight.bold,
            fontSize: (sq * 0.22).clamp(8.0, 12.0),
            height: 1,
            color: c.withValues(alpha: t),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, right ? at - Offset(tp.width, 0) : at - Offset(0, tp.height));
    }

    final white = orientation == Side.white;
    for (var i = 0; i < 8; i++) {
      // цифры — у правого края, буквы — у нижнего; цвет — противоположный клетке
      final rankRowDark = (7 + i).isOdd;
      label(white ? '${8 - i}' : '${i + 1}', Offset(8 * sq - sq * 0.06, i * sq + sq * 0.06),
          rankRowDark ? light : dark, right: true);
      final fileDark = (i + 7).isOdd;
      label(String.fromCharCode((white ? 97 + i : 104 - i)), Offset(i * sq + sq * 0.06, 8 * sq - sq * 0.05),
          fileDark ? light : dark);
    }
  }

  @override
  bool shouldRepaint(_CoordsPainter old) => old.t != t || old.orientation != orientation || old.light != light;
}

/// Inset outlines on the legal destinations of the touched piece.
class _DestsPainter extends CustomPainter {
  // ignore: invalid_use_of_internal_member
  _DestsPainter(this.board, this.flipped, this.light, this.dark) : super(repaint: board.highlightNotifier);

  final ChessboardController board;
  final bool flipped;
  final Color light, dark;

  @override
  void paint(Canvas canvas, Size size) {
    final sq = size.shortestSide / 8;
    // ignore: invalid_use_of_internal_member
    final dests = board.highlightNotifier.moveDests;
    if (dests.isEmpty) return;
    final inset = sq * 0.085;
    final width = sq * 0.075;
    for (final d in dests) {
      final x = flipped ? 7 - d.file : d.file;
      final y = flipped ? d.rank : 7 - d.rank;
      final darkSquare = (d.file + d.rank).isEven;
      final rect = Rect.fromLTWH(x * sq, y * sq, sq, sq).deflate(inset + width / 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(sq * 0.07)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..color = darkSquare ? light : dark,
      );
    }
  }

  @override
  bool shouldRepaint(_DestsPainter old) => old.flipped != flipped || old.board != board || old.light != light;
}
