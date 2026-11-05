/// Extra graphs of the Game tab, under the evaluation (folded by default):
/// - position character along the game: sharp, middle, trivial (and quiet
///   positions as dots);
/// - the AAC parts for each player: Abilities, Activity (free squares
///   controlled), Complication.
library;

import 'dart:math' as math;

import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/material.dart';

import '../../analysis/character.dart';
import '../controller.dart';

class MoreGraphs extends StatelessWidget {
  const MoreGraphs({super.key, required this.controller});

  final AnalysisController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = TextStyle(fontSize: 12, color: scheme.outline, fontWeight: FontWeight.w600);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        dense: true,
        title: Text('More graphs', style: label),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: [
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final c = controller;
              final n = c.analysis.records.length;
              final chars = [for (var i = 0; i < n; i++) c.characterAt(i)];
              final aac = c.aac;
              Widget titled(String t, Widget g, {String? legend}) => Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(t, style: label),
                        const Spacer(),
                        if (legend != null) Text(legend, style: TextStyle(fontSize: 10, color: scheme.outline)),
                      ]),
                      const SizedBox(height: 4),
                      g,
                    ]),
                  );
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                titled(
                  'Position character',
                  _Seek(c, n, CustomPaint(size: const Size(double.infinity, 22), painter: _CharacterPainter(chars, c.recordPly, scheme))),
                  legend: 'sharp · middle · trivial, dot = quiet',
                ),
                for (final (name, part) in [
                  ('Abilities', (Side s, int i) => aac[i].abilities[s]!),
                  ('Activity', (Side s, int i) => aac[i].activity[s]!),
                  ('Complication', (Side s, int i) => aac[i].complication[s]!),
                ])
                  titled(
                    name,
                    _Seek(
                      c,
                      n,
                      CustomPaint(
                        size: const Size(double.infinity, 56),
                        painter: _TwoLinesPainter(
                          [for (var i = 0; i < aac.length; i++) part(Side.white, i)],
                          [for (var i = 0; i < aac.length; i++) part(Side.black, i)],
                          c.recordPly,
                          scheme,
                        ),
                      ),
                    ),
                    legend: null,
                  ),
              ]);
            },
          ),
        ],
      ),
    );
  }
}

/// Tap or drag to go to that move.
class _Seek extends StatelessWidget {
  const _Seek(this.c, this.n, this.child);

  final AnalysisController c;
  final int n;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        void seek(Offset p) {
          if (n < 2) return;
          c.select(((p.dx / box.maxWidth) * (n - 1)).round().clamp(0, n - 1));
        }

        return GestureDetector(
          onTapDown: (d) => seek(d.localPosition),
          onHorizontalDragUpdate: (d) => seek(d.localPosition),
          child: child,
        );
      });
}

class _CharacterPainter extends CustomPainter {
  _CharacterPainter(this.chars, this.cursor, this.scheme);

  final List<PositionCharacter> chars;
  final int cursor;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final n = chars.length;
    if (n == 0) return;
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)));
    canvas.drawRect(rect, Paint()..color = scheme.surfaceContainerHighest);
    final w = size.width / n;
    for (var i = 0; i < n; i++) {
      final color = switch (chars[i].sharpness) {
        Sharpness.sharp => const Color(0xFFE5622E),
        Sharpness.trivial => const Color(0xFF4CAF50),
        Sharpness.middle => const Color(0xFF959595),
        null => Colors.transparent,
      };
      canvas.drawRect(Rect.fromLTWH(i * w, 0, w + 0.5, size.height), Paint()..color = color.withValues(alpha: 0.85));
      if (chars[i].quiet) {
        canvas.drawCircle(Offset((i + 0.5) * w, size.height / 2), math.min(3, w / 2), Paint()..color = Colors.white);
      }
    }
    canvas.restore();
    final x = (cursor.clamp(0, n - 1) + 0.5) * w;
    canvas.drawLine(Offset(x, -2), Offset(x, size.height + 2), Paint()
      ..color = scheme.onSurface
      ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_CharacterPainter old) => old.cursor != cursor || old.chars != chars;
}

/// Two lines (White light, Black dark) on a shared scale.
class _TwoLinesPainter extends CustomPainter {
  _TwoLinesPainter(this.white, this.black, this.cursor, this.scheme);

  final List<double> white, black;
  final int cursor;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final n = white.length;
    if (n == 0) return;
    final rect = Offset.zero & size;
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), Paint()..color = scheme.surfaceContainerHighest);
    final all = [...white, ...black];
    final lo = all.reduce(math.min), hi = all.reduce(math.max);
    final span = hi - lo < 1e-9 ? 1.0 : hi - lo;
    double x(int i) => n == 1 ? size.width / 2 : i / (n - 1) * size.width;
    double y(double v) => size.height - 4 - (v - lo) / span * (size.height - 8);
    void line(List<double> vs, Color color) {
      final path = Path()..moveTo(x(0), y(vs[0]));
      for (var i = 1; i < n; i++) {
        path.lineTo(x(i), y(vs[i]));
      }
      canvas.drawPath(path, Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round);
    }

    line(black, const Color(0xFF8A8A8A));
    line(white, const Color(0xFFF2F2F2));
    final cx = x(cursor.clamp(0, n - 1));
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), Paint()
      ..color = scheme.onSurface.withValues(alpha: 0.55)
      ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_TwoLinesPainter old) => old.cursor != cursor || old.white != white;
}
