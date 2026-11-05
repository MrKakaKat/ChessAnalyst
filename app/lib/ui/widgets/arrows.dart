/// Arrows over the board, drawn by the app instead of chessground: a knight's
/// move goes as an L (two squares, then the turn), and the style is the
/// user's choice (classic, slim, bold, dashed; see docs/arrow_styles.svg).
///
/// Users draw their own arrows: with the right mouse button, or with the pen
/// switched on — drag from a square to another; the same arrow again removes it.
library;

import 'dart:ui' as ui;

import 'package:dartchess/dartchess.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../prefs.dart';

/// A square marked by the user.
class BoardMark {
  const BoardMark(this.square, this.color);

  final Square square;
  final Color color;

  @override
  bool operator ==(Object other) => other is BoardMark && other.square == square;

  @override
  int get hashCode => square.hashCode;
}

/// An arrow any piece could make: along a file or rank, on a 45° diagonal,
/// or a knight's jump. Other directions are slips of the finger.
bool isPieceLine(Square from, Square to) {
  final df = (to.file - from.file).abs(), dr = (to.rank - from.rank).abs();
  if (df == 0 && dr == 0) return false;
  return df == 0 || dr == 0 || df == dr || (df == 1 && dr == 2) || (df == 2 && dr == 1);
}

class BoardArrow {
  const BoardArrow(this.from, this.to, this.color, {this.scale = 1, this.sketched = false, this.muted = false});

  final Square from, to;
  final Color color;
  final double scale;

  /// Drawn by the user: it grows out of its see-through sketch.
  final bool sketched;

  /// Crosses the square with the move's icon: drawn later, see-through,
  /// fading in without growing.
  final bool muted;

  /// Squares the arrow passes through (both ends included; a knight's
  /// arrow through its corner).
  Set<Square> get squares {
    final out = <Square>{from, to};
    final df = to.file - from.file, dr = to.rank - from.rank;
    if ({df.abs(), dr.abs()}.containsAll({1, 2}) && df.abs() != dr.abs()) {
      out.add(dr.abs() == 2 ? Square.fromCoords(from.file, to.rank) : Square.fromCoords(to.file, from.rank));
      return out;
    }
    // прямая или диагональ: шаг по знаку смещения
    if (df == 0 || dr == 0 || df.abs() == dr.abs()) {
      final n = df.abs() > dr.abs() ? df.abs() : dr.abs();
      for (var i = 1; i < n; i++) {
        out.add(Square.fromCoords(File(from.file + df.sign * i), Rank(from.rank + dr.sign * i)));
      }
    }
    return out;
  }

  @override
  bool operator ==(Object other) => other is BoardArrow && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}


/// Arrows over the board. New arrows draw themselves from start to end
/// (unless switched off in the settings).
class ArrowLayer extends StatefulWidget {
  const ArrowLayer(
      {super.key, required this.arrows, required this.flipped, this.style, this.animate, this.marks = const []});

  final List<BoardArrow> arrows;

  /// Marked squares, drawn under the arrows.
  final List<BoardMark> marks;
  final bool flipped;

  /// Style override (settings samples); otherwise the user's choice.
  final ArrowStyle? style;
  final bool? animate;

  @override
  State<ArrowLayer> createState() => _ArrowLayerState();
}

class _ArrowLayerState extends State<ArrowLayer> with TickerProviderStateMixin {
  late final AnimationController _draw =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 380), value: 1);

  /// Removed arrows fade out instead of vanishing.
  late final AnimationController _fade =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 260), value: 1);
  Set<BoardArrow> _old = {};
  Set<BoardArrow> _fresh = {};
  List<BoardArrow> _gone = const [];

  @override
  void initState() {
    super.initState();
    _old = widget.arrows.toSet();
  }

  @override
  void didUpdateWidget(ArrowLayer old) {
    super.didUpdateWidget(old);
    final now = widget.arrows.toSet();
    final added = now.difference(_old);
    final removed = _old.difference(now);
    _old = now;
    // стёртые (вручную или со сменой хода) — плавно гаснут
    if (removed.isNotEmpty) {
      _gone = removed.toList();
      _fade.forward(from: 0);
    }
    // новая стрелка проявляется из полупрозрачного наброска: вырастает от
    // начала к концу или просто наливается цветом (анимация выключена)
    if (added.isNotEmpty && widget.animate != false) {
      _fresh = added;
      _draw.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _draw.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedBuilder(
          animation: Listenable.merge([_draw, _fade]),
          builder: (context, _) => CustomPaint(
            size: Size.infinite,
            painter: _ArrowPainter(widget.arrows, widget.flipped, widget.style ?? prefs.arrowStyle,
                gone: _fade.value < 1 ? _gone : const [],
                goneAlpha: 1 - Curves.easeOut.transform(_fade.value),
                fresh: _fresh,
                t: Curves.easeOutCubic.transform(_draw.value),
                grow: widget.animate ?? prefs.animateArrows,
                marks: widget.marks),
          ),
        ),
      );
}

class _ArrowPainter extends CustomPainter {
  _ArrowPainter(this.arrows, this.flipped, this.style,
      {this.fresh = const {},
      this.t = 1,
      this.grow = true,
      this.marks = const [],
      this.alpha = 1,
      this.gone = const [],
      this.goneAlpha = 0});

  /// Arrows just removed, fading out at [goneAlpha].
  final List<BoardArrow> gone;
  final double goneAlpha;

  final List<BoardArrow> arrows;
  final bool flipped;
  final ArrowStyle style;
  final bool grow;
  final List<BoardMark> marks;

  /// Overall opacity (the sketch while drawing, a fading slip).
  final double alpha;

  /// Arrows being drawn in, at progress [t].
  final Set<BoardArrow> fresh;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final sq = size.shortestSide / 8;
    Offset center(Square s) {
      final x = flipped ? 7 - s.file : s.file;
      final y = flipped ? s.rank : 7 - s.rank;
      return Offset((x + 0.5) * sq, (y + 0.5) * sq);
    }

    for (final m in marks) {
      final c = center(m.square);
      canvas.drawRRect(
        // клетка закрашивается целиком, без скругления
        RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: sq, height: sq), Radius.zero),
        Paint()..color = m.color.withValues(alpha: 0.5 * alpha),
      );
    }
    for (final a in [...gone, ...arrows]) {
      final leaving = gone.contains(a) && !arrows.contains(a);
      final df = a.to.file - a.from.file, dr = a.to.rank - a.from.rank;
      final pts = <Offset>[center(a.from)];
      // ход коня — буквой L: сначала на две клетки, потом поворот
      if ({df.abs(), dr.abs()}.containsAll({1, 2}) && df.abs() != dr.abs()) {
        final corner = dr.abs() == 2
            ? Square.fromCoords(a.from.file, a.to.rank)
            : Square.fromCoords(a.to.file, a.from.rank);
        pts.add(center(corner));
      }
      pts.add(center(a.to));
      final fade = (a.muted ? 0.45 : 1.0) * (leaving ? goneAlpha : 1.0);
      if (leaving) {
        _draw(canvas, pts, a.color, sq * a.scale, Offset.zero & size, alpha * fade);
        continue;
      }
      if (fresh.contains(a) && t < 1) {
        if (a.muted) {
          // через клетку со значком — позже, без роста, только проявление
          final u = ((t - 0.4) / 0.6).clamp(0.0, 1.0);
          _draw(canvas, pts, a.color, sq * a.scale, Offset.zero & size, alpha * fade * u);
          continue;
        }
        // набросок своей стрелки плавно гаснет, пока стрелка растёт
        if (a.sketched) _draw(canvas, pts, a.color, sq * a.scale, Offset.zero & size, 0.4 * alpha * (1 - t));
        if (grow) {
          final cut = _cut(pts, t);
          if (cut.length >= 2 && (cut.last - cut.first).distance >= sq * 0.3) {
            _draw(canvas, cut, a.color, sq * a.scale, Offset.zero & size, alpha);
          }
        } else {
          _draw(canvas, pts, a.color, sq * a.scale, Offset.zero & size, alpha * (a.sketched ? 0.4 + 0.6 * t : t));
        }
        continue;
      }
      _draw(canvas, pts, a.color, sq * a.scale, Offset.zero & size, alpha * fade);
    }
  }

  /// The polyline [pts] up to share [t] of its length (drawing in).
  static List<Offset> _cut(List<Offset> pts, double t) {
    var total = 0.0;
    for (var i = 1; i < pts.length; i++) {
      total += (pts[i] - pts[i - 1]).distance;
    }
    var left = total * t;
    final out = [pts.first];
    for (var i = 1; i < pts.length; i++) {
      final seg = (pts[i] - pts[i - 1]).distance;
      if (left >= seg) {
        out.add(pts[i]);
        left -= seg;
      } else {
        out.add(pts[i - 1] + (pts[i] - pts[i - 1]) * (left / seg));
        break;
      }
    }
    return out;
  }

  void _draw(Canvas canvas, List<Offset> pts, Color color, double sq, Rect bounds, double alpha) {
    // blunt — классика с более тупым углом наконечника (шире и короче)
    final (w, hw, hl, op) = switch (style) {
      ArrowStyle.classic => (sq * 0.2, sq * 0.55, sq * 0.45, 0.7),
      ArrowStyle.blunt => (sq * 0.2, sq * 0.66, sq * 0.32, 0.7),
      ArrowStyle.slim => (sq * 0.1, 0.0, 0.0, 0.9),
      ArrowStyle.bold => (sq * 0.26, sq * 0.62, sq * 0.46, 0.92),
    };
    final a = pts[pts.length - 2], b = pts.last;
    final u = (b - a) / (b - a).distance;
    // у slim конец — такая же точка, как начало
    final tip = style == ArrowStyle.slim ? b : b - u * (sq * 0.12);
    final base = tip - u * hl;
    final n = Offset(-u.dy, u.dx);
    final line = [...pts.sublist(0, pts.length - 1), base];
    if (style != ArrowStyle.slim) {
      final s0 = line[0], s1 = line[1];
      line[0] = s0 + (s1 - s0) / (s1 - s0).distance * (sq * 0.15);
    }
    final head = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo((base + n * (hw / 2)).dx, (base + n * (hw / 2)).dy)
      ..lineTo((base - n * (hw / 2)).dx, (base - n * (hw / 2)).dy)
      ..close();
    Path body() {
      final p = Path()..moveTo(line[0].dx, line[0].dy);
      for (final q in line.skip(1)) {
        p.lineTo(q.dx, q.dy);
      }
      return p;
    }

    final cap = style == ArrowStyle.slim || style == ArrowStyle.bold ? StrokeCap.round : StrokeCap.butt;
    void paintArrow(Color c, double extra) {
      final stroke = Paint()
        ..color = c
        ..style = PaintingStyle.stroke
        ..strokeWidth = w + extra
        ..strokeCap = cap
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(body(), stroke);
      if (style == ArrowStyle.slim) {
        canvas.drawCircle(pts.first, sq * 0.12 + extra / 2, Paint()..color = c);
        canvas.drawCircle(tip, sq * 0.12 + extra / 2, Paint()..color = c);
      } else {
        canvas.drawPath(head, Paint()..color = c);
        if (extra > 0) canvas.drawPath(head, stroke..strokeWidth = extra);
      }
    }

    // слой целиком полупрозрачный — наложения линии и наконечника не темнеют
    canvas.saveLayer(bounds, Paint()..color = Color.fromRGBO(0, 0, 0, op * alpha));
    if (style == ArrowStyle.bold) {
      canvas.save();
      canvas.translate(0, sq * 0.06);
      canvas.saveLayer(bounds, Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: sq * 0.05, sigmaY: sq * 0.05));
      paintArrow(Colors.black.withValues(alpha: 0.3), sq * 0.1);
      canvas.restore();
      canvas.restore();
      paintArrow(Colors.white, sq * 0.1);
    }
    paintArrow(color.withValues(alpha: 1), 0);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ArrowPainter old) =>
      old.flipped != flipped ||
      old.style != style ||
      old.t != t ||
      old.alpha != alpha ||
      old.goneAlpha != goneAlpha ||
      old.gone.length != gone.length ||
      old.marks.length != marks.length ||
      !_same(old.arrows, arrows);

  static bool _same(List<BoardArrow> a, List<BoardArrow> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i] || a[i].color != b[i].color) return false;
    }
    return true;
  }
}

/// Draws user arrows and marks: right mouse button always; any pointer while
/// [pen] is on. A drag draws a see-through sketch; on release it stays and
/// becomes the arrow (or fades out quickly if no piece could move that way).
/// A tap on one square marks it.
class ArrowDrawing extends StatefulWidget {
  const ArrowDrawing({
    super.key,
    required this.flipped,
    required this.pen,
    required this.onArrow,
    this.onMark,
    required this.child,
  });

  final bool flipped;
  final bool pen;
  final void Function(Square from, Square to) onArrow;
  final void Function(Square square)? onMark;
  final Widget child;

  @override
  State<ArrowDrawing> createState() => _ArrowDrawingState();
}

class _ArrowDrawingState extends State<ArrowDrawing> with SingleTickerProviderStateMixin {
  Square? _from;
  Square? _over;
  int? _pointer;
  BoardArrow? _slip;
  late final AnimationController _fade =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 220))
        ..addListener(() => setState(() {}))
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) setState(() => _slip = null);
        });

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  Square? _square(Offset p, Size size) {
    final sq = size.shortestSide / 8;
    final x = (p.dx / sq).floor(), y = (p.dy / sq).floor();
    if (x < 0 || x > 7 || y < 0 || y > 7) return null;
    return Square.fromCoords(File(widget.flipped ? 7 - x : x), Rank(widget.flipped ? y : 7 - y));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final size = box.biggest;
      final drawing = _from != null && _over != null && _over != _from;
      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) {
          final right = e.kind == PointerDeviceKind.mouse && (e.buttons & kSecondaryMouseButton) != 0;
          if (!right && !widget.pen) return;
          setState(() {
            _pointer = e.pointer;
            _from = _over = _square(e.localPosition, size);
          });
        },
        onPointerMove: (e) {
          if (e.pointer != _pointer) return;
          final s = _square(e.localPosition, size);
          if (s != _over) setState(() => _over = s);
        },
        onPointerUp: (e) {
          if (e.pointer != _pointer) return;
          final from = _from, to = _square(e.localPosition, size);
          setState(() => _from = _over = _pointer = null);
          if (from == null || to == null) return;
          if (from == to) {
            widget.onMark?.call(from);
          } else if (isPieceLine(from, to)) {
            widget.onArrow(from, to);
          } else {
            // ни одна фигура так не ходит — набросок быстро гаснет
            setState(() => _slip = BoardArrow(from, to, prefs.userArrowColor));
            _fade.forward(from: 0);
          }
        },
        onPointerCancel: (_) => setState(() => _from = _over = _pointer = null),
        child: Stack(children: [
          // пока рисуем пером, доска не получает касаний
          AbsorbPointer(absorbing: widget.pen, child: widget.child),
          if (drawing || _slip != null)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _ArrowPainter(
                    [drawing ? BoardArrow(_from!, _over!, prefs.userArrowColor) : _slip!],
                    widget.flipped,
                    prefs.arrowStyle,
                    alpha: drawing ? 0.4 : 0.4 * (1 - _fade.value),
                  ),
                ),
              ),
            ),
        ]),
      );
    });
  }
}
