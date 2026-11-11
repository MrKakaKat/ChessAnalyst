/// Evaluation bar next to the board and the game graph.
///
/// Animations: the bar flows to the new value; the graph draws itself left to
/// right on open, morphs from old to new values on a unit switch, the cursor
/// glides; dragging over the graph scrubs through the game; the graph folds
/// away with its header button.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/material.dart';

import '../../analysis/classify.dart';
import '../../analysis/eval.dart';
import '../../analysis/settings.dart';
import '../controller.dart';
import '../labels.dart';

/// Evaluation after the move from White's side, normalised to 0..1.
double whiteShare(MoveRecord r, Unit unit, {bool before = false}) {
  if (unit == Unit.pawns) {
    final v = before ? r.pawns.e1 : r.pawns.ep;
    final w = r.side == Side.white ? v : -v;
    return 0.5 + 0.5 * (2 / (1 + math.exp(-w / 2.2)) - 1); // мягкое насыщение
  }
  final v = before ? r.wdl.e1 : r.wdl.ep;
  return r.side == Side.white ? v : 1 - v;
}

String whiteLabel(MoveRecord r, Unit unit) {
  final e = r.ep;
  final white = r.side == Side.white;
  if (unit == Unit.pawns || unit == Unit.both) {
    if (e.mate != null) return '#${white ? e.mate : -e.mate!}';
    final v = (white ? e.cp! : -e.cp!) / 100;
    return '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}';
  }
  final v = white ? r.wdl.ep : 1 - r.wdl.ep;
  return '${(v * 100).round()}%';
}

/// White-side text of an engine evaluation given from [root]'s side.
String whiteEvalText(Eval e, Side root, Unit unit) {
  final white = root == Side.white;
  if (unit == Unit.wdl) {
    final v = white ? e.expected : 1 - e.expected;
    return '${(v * 100).round()}%';
  }
  if (e.mate != null) return '#${white ? e.mate : -e.mate!}';
  final v = (white ? e.cp! : -e.cp!) / 100;
  return '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}';
}

double _whiteShareOf(Eval e, Side root, Unit unit) {
  final white = root == Side.white;
  if (unit == Unit.pawns) {
    final p = e.mate != null ? (e.mate! > 0 ? 10.0 : -10.0) : e.cp! / 100;
    final w = white ? p : -p;
    return 0.5 + 0.5 * (2 / (1 + math.exp(-w / 2.2)) - 1);
  }
  return white ? e.expected : 1 - e.expected;
}

/// Practical evaluation after [ply] for White, pawns; the engine's where the
/// difficulty is not known (the last move).
double practicalWhiteAt(AnalysisController c, int ply) {
  final v = ply < c.practicalWhite.length ? c.practicalWhite[ply] : null;
  if (v != null) return v;
  final r = c.analysis.records[ply];
  final p = r.ep.pawns(const Settings()).clamp(-8.0, 8.0);
  return r.side == Side.white ? p : -p;
}

class EvalBar extends StatelessWidget {
  const EvalBar({super.key, required this.controller, required this.height});

  final AnalysisController controller;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final r = c.analysis.records[c.recordPly];
    final barUnit = c.unit == Unit.pawns ? Unit.pawns : Unit.wdl;
    var target = whiteShare(r, barUnit);
    var text = whiteLabel(r, c.unit);
    if (c.unit == Unit.both && c.hasDifficulty) {
      // практическая оценка: оценка движка с поправкой на сложность
      final p = c.atStart ? 0.0 : practicalWhiteAt(c, c.recordPly);
      target = 0.5 + 0.5 * (p / 8).clamp(-1.0, 1.0);
      text = '${p >= 0 ? '+' : ''}${p.toStringAsFixed(1)}';
    } else if (c.unit == Unit.both) {
      // AAC: контригра вместо оценки движка
      final v = c.atStart ? 0.0 : c.aac[c.recordPly].value;
      target = 0.5 + 0.5 * v;
      text = '${v >= 0 ? '+' : ''}${(v * 100).round()}';
    }
    if (c.atStart && c.unit != Unit.both) {
      // начальная позиция: оценка до первого хода
      target = whiteShare(r, barUnit, before: true);
      text = whiteEvalText(r.e1, r.side, c.unit);
    }
    // в своей ветке — оценка линии движка, если ветка по ней идёт
    final vm = c.varMove;
    if (vm != null && vm.eval != null) {
      target = _whiteShareOf(vm.eval!, vm.root, barUnit);
      text = whiteEvalText(vm.eval!, vm.root, c.unit);
    } else if (vm != null) {
      text = '–';
    }
    final flipped = c.flipped;
    // WDL: ничья — серым посередине, между выигрышем белых и чёрных
    var draw = 0.0;
    if (c.unit == Unit.wdl && vm == null) {
      final e = c.atStart ? r.e1 : r.ep;
      final white = r.side == Side.white;
      final (w, d, l) = e.wdl;
      draw = d / 1000;
      target = (white ? w : l) / 1000;
    }
    return SizedBox(
      width: 22,
      height: height,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: target),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(children: [
            Container(color: const Color(0xFF3A3A3A)),
            TweenAnimationBuilder<double>(
              tween: Tween(end: draw),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              builder: (context, dv, _) => AnimatedAlign(
                duration: const Duration(milliseconds: 420),
                alignment: flipped ? Alignment.topCenter : Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: (v + dv).clamp(0.0, 1.0),
                  widthFactor: 1,
                  child: Container(color: const Color(0xFF8E8E8E)),
                ),
              ),
            ),
            // при развороте доски белая часть плавно переезжает на другую сторону
            AnimatedAlign(
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeInOutCubic,
              alignment: flipped ? Alignment.topCenter : Alignment.bottomCenter,
              child: FractionallySizedBox(heightFactor: v.clamp(0.0, 1.0), widthFactor: 1,
                  child: Container(color: const Color(0xFFF2F2F2))),
            ),
            // число не переезжает: на старом месте гаснет, на новом проявляется
            for (final bottom in [true, false])
              Align(
                alignment: bottom ? Alignment.bottomCenter : Alignment.topCenter,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 300),
                  opacity: (((v >= 0.5) != flipped) == bottom) ? 1 : 0,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: Text(text,
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: v >= 0.5 ? const Color(0xFF3A3A3A) : const Color(0xFFF2F2F2))),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class EvalGraph extends StatefulWidget {
  const EvalGraph({super.key, required this.controller, this.height = 110});

  final AnalysisController controller;
  final double height;

  @override
  State<EvalGraph> createState() => _EvalGraphState();
}

class _EvalGraphState extends State<EvalGraph> with TickerProviderStateMixin {
  late final AnimationController _reveal =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..forward();
  late final AnimationController _morph = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  List<double> _from = const [];
  List<double> _to = const [];
  Unit? _unit;
  Object? _analysis;

  AnalysisController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _to = _values();
    _from = _to;
    _unit = c.unit;
    _analysis = c.analysis;
    c.addListener(_onChange);
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    _reveal.dispose();
    _morph.dispose();
    super.dispose();
  }

  List<double> _values() {
    if (c.unit == Unit.both && c.hasDifficulty) {
      return [
        for (var i = 0; i < c.analysis.records.length; i++) 0.5 + 0.5 * (practicalWhiteAt(c, i) / 8).clamp(-1.0, 1.0),
      ];
    }
    if (c.unit == Unit.both) return [for (final p in c.aac) 0.5 + 0.5 * p.value];
    final unit = c.unit == Unit.pawns ? Unit.pawns : Unit.wdl;
    return [for (final r in c.analysis.records) whiteShare(r, unit)];
  }

  void _onChange() {
    // новая единица или обновлённый анализ (идёт расчёт) — график перетекает
    if ((c.unit != _unit || !identical(c.analysis, _analysis)) && !c.busy) {
      final t = Curves.easeInOutCubic.transform(_morph.value);
      _from = [for (var i = 0; i < _to.length; i++) ui.lerpDouble(_from[i], _to[i], t)!];
      _to = _values();
      _unit = c.unit;
      _analysis = c.analysis;
      _morph.forward(from: 0);
    }
    setState(() {});
  }

  void _seek(Offset local, double width) {
    final n = c.length;
    if (n < 2) return;
    c.select(((local.dx / width) * (n - 1)).round());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final b = Theme.of(context).brightness;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      return GestureDetector(
        onTapDown: (d) => _seek(d.localPosition, w),
        onHorizontalDragUpdate: (d) => _seek(d.localPosition, w),
        child: AnimatedBuilder(
          animation: Listenable.merge([_reveal, _morph]),
          builder: (context, _) {
            final t = Curves.easeInOutCubic.transform(_morph.value);
            final values = [for (var i = 0; i < _to.length; i++) ui.lerpDouble(_from[i], _to[i], t)!];
            return TweenAnimationBuilder<double>(
              tween: Tween(end: c.recordPly.toDouble()),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut,
              builder: (context, cursor, _) => CustomPaint(
                size: Size(w, widget.height),
                painter: _GraphPainter(
                  values: values,
                  steps: [for (final r in c.analysis.records) r],
                  reveal: Curves.easeOutCubic.transform(_reveal.value),
                  cursor: cursor,
                  scheme: scheme,
                  brightness: b,
                ),
              ),
            );
          },
        ),
      );
    });
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.values,
    required this.steps,
    required this.reveal,
    required this.cursor,
    required this.scheme,
    required this.brightness,
  });

  final List<double> values;
  final List<MoveRecord> steps;
  final double reveal;
  final double cursor;
  final ColorScheme scheme;
  final Brightness brightness;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n == 0) return;
    final rect = Offset.zero & size;
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        Paint()..color = scheme.surfaceContainerHighest);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)));
    double x(num i) => n == 1 ? size.width / 2 : i / (n - 1) * size.width;
    double y(double v) => size.height * (1 - v);

    final line = Path()..moveTo(x(0), y(values[0]));
    for (var i = 1; i < n; i++) {
      line.lineTo(x(i), y(values[i]));
    }
    final area = Path.from(line)
      ..lineTo(x(n - 1), size.height)
      ..lineTo(0, size.height)
      ..close();

    // прорисовка слева направо
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * reveal, size.height));
    canvas.drawPath(area, Paint()..color = brightness == Brightness.dark ? const Color(0x55FFFFFF) : const Color(0xFFFFFFFF));
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2),
        Paint()..color = scheme.outlineVariant..strokeWidth = 1);
    canvas.drawPath(
        line,
        Paint()
          ..color = scheme.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round);
    for (var i = 0; i < n; i++) {
      final r = steps[i];
      // точки: ошибки, brilliant и пропуск (pass) — только когда пропуск и есть
      // оценка хода, а не флаг рядом с другой оценкой
      if (isError(r.step) || r.step == 'pass' || r.subtype == 'brilliant') {
        final color = r.subtype == 'brilliant'
            ? const Color(0xFF00897B)
            : stepColor(isError(r.step) ? r.step : 'pass', brightness);
        canvas.drawCircle(Offset(x(i), y(values[i])), r.step == 'blunder' ? 4.5 : 3.5, Paint()..color = color);
      }
    }
    canvas.restore();

    final cx = x(cursor);
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height),
        Paint()..color = scheme.onSurface.withValues(alpha: 0.55)..strokeWidth = 1.5);
    final i = cursor.round().clamp(0, n - 1);
    canvas.drawCircle(Offset(cx, y(values[i])), 5, Paint()..color = scheme.onSurface);
  }

  @override
  bool shouldRepaint(_GraphPainter old) =>
      old.values != values || old.reveal != reveal || old.cursor != cursor || old.scheme != scheme;
}


/// The graph with a header that folds it away.
class CollapsibleGraph extends StatefulWidget {
  const CollapsibleGraph({super.key, required this.controller, this.height = 110});

  final AnalysisController controller;
  final double height;

  @override
  State<CollapsibleGraph> createState() => _CollapsibleGraphState();
}

class _CollapsibleGraphState extends State<CollapsibleGraph> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => setState(() => _open = !_open),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
          child: Row(children: [
            Text('Evaluation', style: TextStyle(fontSize: 12, color: scheme.outline, fontWeight: FontWeight.w600)),
            const Spacer(),
            AnimatedRotation(
              turns: _open ? 0 : 0.5,
              duration: const Duration(milliseconds: 250),
              child: Icon(Icons.expand_less_rounded, size: 20, color: scheme.outline),
            ),
          ]),
        ),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOutCubic,
        alignment: Alignment.topCenter,
        child: _open ? EvalGraph(controller: widget.controller, height: widget.height) : const SizedBox(width: double.infinity),
      ),
    ]);
  }
}
