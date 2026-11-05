/// Lines and locks (logic from the earlier Idea Chain project).
///
/// Lists the lines of attack in the position after the selected move: a slider,
/// its target and the locks between them. Selecting a line marks it on the
/// board (slider, locks, target) and shows how its locks closed and opened
/// around this move. Animation, as in that project: dots fill one by one
/// (80 ms step); an open lock turns red with a single 2 px shake.
library;

import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';

import '../../analysis/locks.dart';
import '../../analysis/pos.dart';
import '../controller.dart';
import '../labels.dart';

const okColor = Color(0xFF2F8A4C);
const threatColor = Color(0xFFD23C32);
const sleepColor = Color(0xFFD9820F);

String _piece(Pos b, Square sq) {
  final p = b.pieceAt(sq);
  return p == null ? sq.name : pieceText(pieceSymbol(p), sq.name);
}

class LocksPanel extends StatelessWidget {
  const LocksPanel({super.key, required this.controller, this.bottomPadding = 0});

  final AnalysisController controller;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final pos = c.position;
    final lines = c.linesAt(c.ply);
    final scheme = Theme.of(context).colorScheme;
    final selected = c.selectedLock;
    final shown = c.lockShown();

    Widget group(Side side) {
      final own = lines.where((l) => l.side == side).toList();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text('${side == Side.white ? 'White' : 'Black'} lines',
              style: TextStyle(fontWeight: FontWeight.w700, color: scheme.outline)),
        ),
        if (own.isEmpty) Text('None', style: TextStyle(color: scheme.outline, fontSize: 13)),
        for (final l in own)
          _LineTile(
            pos: pos,
            line: l,
            selected: shown != null && shown.slider == l.slider && shown.target == l.target,
            onTap: () => c.selectLock(shown != null && shown.slider == l.slider && shown.target == l.target ? null : l),
          ),
      ]);
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(14, 8, 14, 16 + bottomPadding),
      children: [
        Text('A line is a bishop, rook or queen aimed at a target through up to two locks. '
            'Closed: blocked. Open: a direct threat.',
            style: TextStyle(fontSize: 12, color: scheme.outline)),
        if (selected != null) ...[
          const SizedBox(height: 12),
          _LockTimeline(key: ValueKey('${selected.anchor}-${selected.slider}-${selected.target}'), controller: c),
        ],
        group(Side.white),
        group(Side.black),
      ],
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.pos, required this.line, required this.selected, required this.onTap});

  final Pos pos;
  final LineOfAttack line;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = line.open ? threatColor : sleepColor;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: selected ? scheme.secondaryContainer : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: selected ? color : scheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(children: [
            Expanded(
              child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(_piece(pos, line.slider), style: const TextStyle(fontWeight: FontWeight.w600)),
                const ArrowGlyph(),
                Text(_piece(pos, line.target), style: const TextStyle(fontWeight: FontWeight.w600)),
                if (line.locks.isNotEmpty)
                  Text(
                    '   Locks: ${line.locks.map((l) => '${_piece(pos, l.square)} (${l.side == line.side ? 'own' : 'defender'})').join(', ')}',
                    style: TextStyle(fontSize: 12, color: scheme.outline),
                  ),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
              child: Text(line.open ? 'Open' : (line.discovered ? 'Closed, discovery' : 'Closed'),
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _LockTimeline extends StatefulWidget {
  const _LockTimeline({super.key, required this.controller});

  final AnalysisController controller;

  @override
  State<_LockTimeline> createState() => _LockTimelineState();
}

class _LockTimelineState extends State<_LockTimeline> with SingleTickerProviderStateMixin {
  late final List<LockPoint> _points = widget.controller.lockTimelineFor(widget.controller.selectedLock!);
  late final AnimationController _a = AnimationController(
      vsync: this, duration: Duration(milliseconds: 80 * _points.length + 400))
    ..forward();

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final scheme = Theme.of(context).colorScheme;
    final total = _a.duration!.inMilliseconds;
    final opened = _points.where((p) => p.state == LineState.open).map((p) => p.ply).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Locks around this move', style: TextStyle(fontWeight: FontWeight.w700, color: scheme.outline)),
      const SizedBox(height: 6),
      AnimatedBuilder(
        animation: _a,
        builder: (context, _) => Wrap(spacing: 4, runSpacing: 6, children: [
          for (final (i, p) in _points.indexed)
            _dot(context, p, ((_a.value * total - i * 80) / 240).clamp(0.0, 1.0), p.ply == c.ply, () => c.select(p.ply)),
        ]),
      ),
      const SizedBox(height: 6),
      Row(children: [
        _legend(okColor, 'Closed'),
        _legend(threatColor, 'Open'),
        _legend(scheme.outlineVariant, 'Not aligned'),
      ]),
      if (opened.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('Opens after ${plyText(opened.first)} ${c.game.plies[opened.first].san}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
    ]);
  }

  Widget _legend(Color color, String label) => Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ]),
      );

  Widget _dot(BuildContext context, LockPoint p, double t, bool current, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (p.state) {
      LineState.closed => okColor,
      LineState.open => threatColor,
      LineState.none => scheme.outlineVariant,
    };
    // открытый замок один раз вздрагивает на 2 px, пока заполняется
    final dx = p.state == LineState.open ? 2 * math.sin(t * math.pi * 3) * (1 - t) : 0.0;
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: '${plyText(p.ply)} ${widget.controller.game.plies[p.ply].san}',
        child: Transform.translate(
          offset: Offset(dx, 0),
          child: Container(
            width: current ? 18 : 14,
            height: current ? 18 : 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color.lerp(scheme.surface, color, t),
              border: Border.all(color: current ? scheme.onSurface : color, width: current ? 2 : 1.5),
            ),
          ),
        ),
      ),
    );
  }
}
