/// Game summary sheet: accuracy of each side (overall and by stage) with a
/// rough rating, the moves of each side by kind (a ring with coloured parts,
/// the list behind "Moves by kind"), the game's difficulty and sharpness.
library;

import 'dart:math' as math;

import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/material.dart';

import '../../analysis/character.dart' show Sharpness;
import '../../analysis/game.dart';
import '../../analysis/metrics.dart';
import '../../analysis/settings.dart';
import '../controller.dart';
import '../prefs.dart';
import '../../analysis/kinds.dart' show kindLabels;
import '../labels.dart';
import '../step_icons.dart';

/// Button for the last cards of the game.
class AccuracyButton extends StatelessWidget {
  const AccuracyButton({super.key, required this.controller});

  final AnalysisController controller;

  /// Same shape as the step badge: a 30 px pill.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => showSummary(context, controller),
        child: SizedBox(
          height: 30,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.percent_rounded, size: 16, color: scheme.onSecondaryContainer),
              const SizedBox(width: 6),
              Text('Accuracy',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: scheme.onSecondaryContainer)),
            ]),
          ),
        ),
      ),
    );
  }
}

void showSummary(BuildContext context, AnalysisController c) {
  final s = summarize(c.analysis);
  final sharp = sharpnessOf(c.analysis, (ply) => c.characterAt(ply).sharpness == Sharpness.sharp ? 1 : 0);
  // ходы по видам в каждой оценке: Pawns, WDL и AAC (пешки и WDL вместе)
  final byUnit = {
    for (final u in [Unit.pawns, Unit.wdl, Unit.both])
      u: u == c.unit ? c.analysis : analyzeGame(c.game, Settings(unit: u), book: c.book),
  };

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text('Accuracy', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _SideColumn(name: c.game.white, acc: s.accuracy[Side.white]!, difficulty: s.difficulty)),
            const SizedBox(width: 16),
            Expanded(child: _SideColumn(name: c.game.black, acc: s.accuracy[Side.black]!, difficulty: s.difficulty)),
          ]),
          const SizedBox(height: 20),
          _Difficulty(summary: s, sharpness: sharp),
          const SizedBox(height: 12),
          _MovesByKind(byUnit: byUnit, c: c),
        ],
      ),
    ),
  );
}

class _SideColumn extends StatelessWidget {
  const _SideColumn({required this.name, required this.acc, required this.difficulty});

  final String name;
  final SideAccuracy acc;
  final double difficulty;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.outline)),
      TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: acc.overall ?? 0),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => Text(acc.overall == null ? '–' : '${v.toStringAsFixed(1)}%',
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
      ),
      if (ratingEstimate(acc.overall, difficulty) case final r?)
        Text('$r rating', style: TextStyle(fontSize: 12, color: scheme.outline)),
      const SizedBox(height: 6),
      for (final st in stages)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: _Bar(label: stageLabels[st]!, value: acc.byStage[st], suffix: '%', max: 100),
        ),
    ]);
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.value, required this.max, this.suffix = ''});

  final String label;
  final double? value;
  final double max;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
        Text(value == null ? '–' : '${value!.round()}$suffix', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 3),
      TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: (value ?? 0) / max),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(value: v, minHeight: 6, backgroundColor: scheme.surfaceContainerHighest),
        ),
      ),
    ]);
  }
}

class _Difficulty extends StatelessWidget {
  const _Difficulty({required this.summary, required this.sharpness});

  final GameSummary summary;
  final GameSharpness sharpness;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = summary;
    // круг и подпись — на одной высоте: заголовок и уровень по центру круга
    Widget gauge(String title, double value, String level) => Row(children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value / 100),
            duration: const Duration(milliseconds: 1000),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => SizedBox(
              width: 60,
              height: 60,
              child: Stack(alignment: Alignment.center, children: [
                SizedBox.expand(
                    child: CircularProgressIndicator(
                        value: v, strokeWidth: 7, backgroundColor: scheme.surfaceContainerHighest)),
                Text('${(v * 100).round()}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              Text(level, style: TextStyle(fontSize: 13, color: scheme.outline)),
            ]),
          ),
        ]);
    final sh = sharpness;
    final sharpLevel = switch (sh.score) { < 30 => 'Calm', < 50 => 'Balanced', < 70 => 'Sharp', _ => 'Very sharp' };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: gauge('Difficulty', s.difficulty, s.level)),
        const SizedBox(width: 8),
        Expanded(child: gauge('Sharpness', sh.score, sharpLevel)),
      ]),
      Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          dense: true,
          visualDensity: VisualDensity.compact,
          minTileHeight: 32,
          title: Text('Details', style: TextStyle(fontSize: 13, color: scheme.outline, fontWeight: FontWeight.w500)),
          children: [
            for (final p in s.parts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _Bar(label: '${p.name} (weight ${(p.weight * 100).round()}%)', value: p.value * 100, max: 100),
                  const SizedBox(height: 4),
                  Text(p.note, style: TextStyle(fontSize: 11, color: scheme.outline)),
                  const SizedBox(height: 6),
                ]),
              ),
            // острота — в тех же деталях, без отдельного блока
            for (final (name, value, note) in [
              ('Draw chance (low is sharp)', (1 - sh.drawShare) * 100, 'Mean chance of a draw: ${(sh.drawShare * 100).round()}%'),
              ('Sharp positions', sh.sharpShare * 100, 'Positions with at most two positive moves'),
              ('Tactical attacks', (sh.attackShare * 250).clamp(0, 100).toDouble(),
                  '${(sh.attackShare * 100).round()}% of the moves are tactical attacks or counterattacks'),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _Bar(label: 'Sharpness · $name', value: value, max: 100),
                  const SizedBox(height: 4),
                  Text(note, style: TextStyle(fontSize: 11, color: scheme.outline)),
                  const SizedBox(height: 6),
                ]),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('A short game cannot score high: the total is scaled by the game length.',
                  style: TextStyle(fontSize: 11, color: scheme.outline)),
            ),
          ],
        ),
      ),
    ]);
  }
}

/// Counts of each side's moves by icon kind in [a].
Map<String, int> kindsIn(GameAnalysis a, Side side) {
  final out = <String, int>{};
  for (final r in a.records.where((r) => r.side == side)) {
    final k = iconKindOf(r.step, r.subtype);
    out[k] = (out[k] ?? 0) + 1;
  }
  return out;
}

/// Moves by kind for three ways of judging — WDL, Pawns (in the middle,
/// open at first), AAC. As lists: each column opens and closes from its
/// header, its rows drop in; each row has White's count, the icon, Black's
/// count (0 when none). As rings: one way at a time (chosen at the top), a
/// ring per side like the difficulty gauges, with the number of negative
/// moves. Under it the game's mistakes by what they missed, the key blunder
/// first. A switch at the bottom colours the icons.
class _MovesByKind extends StatefulWidget {
  const _MovesByKind({required this.byUnit, required this.c});

  final Map<Unit, GameAnalysis> byUnit;
  final AnalysisController c;

  @override
  State<_MovesByKind> createState() => _MovesByKindState();
}

class _MovesByKindState extends State<_MovesByKind> {
  bool _rings = false;
  final _open = <Unit>{Unit.pawns};
  Unit _ringUnit = Unit.pawns;

  static const _units = [Unit.wdl, Unit.pawns, Unit.both];
  static const _order = ['brilliant', 'only_move', 'only_light', 'best', 'excellent', 'good', 'book', 'forced',
    'neutral', 'inaccuracy', 'laxity', 'pass', 'mistake', 'blunder'];
  static const _negative = {'inaccuracy', 'laxity', 'pass', 'mistake', 'blunder'};

  String _name(Unit u) => u == Unit.both ? 'AAC' : unitLabels[u]!;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colour = prefs.colourSummaryIcons;
    final tint = scheme.primary;
    const num = TextStyle(fontSize: 13, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]);

    Widget header(Unit u, bool on, VoidCallback onTap) => InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: on ? tint : scheme.outline),
              child: Text(_name(u), textAlign: TextAlign.center),
            ),
          ),
        );

    Widget icon(String k) {
      final c = colour ? markColor(k) : tint;
      final light = k == 'only_light' && !colour;
      return Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c, width: light ? 2.8 : 2.4)),
        alignment: Alignment.center,
        child: StepGlyph(kind: k, color: c, size: 10, shadow: false, hollow: light),
      );
    }

    Widget column(Unit u) {
      final a = widget.byUnit[u]!;
      final w = kindsIn(a, Side.white), b = kindsIn(a, Side.black);
      final on = _open.contains(u);
      return Column(children: [
        header(u, on, () => setState(() => on ? _open.remove(u) : _open.add(u))),
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeInOutCubic,
          alignment: Alignment.topCenter,
          child: !on
              ? const SizedBox(width: double.infinity)
              : Column(children: [
                  for (final (i, k) in _order.indexed)
                    _DropIn(
                      key: ValueKey('$u-$k'),
                      delay: Duration(milliseconds: 25 * i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(children: [
                          // число белых — к значку справа, чёрных — к значку слева
                          Expanded(child: Text('${w[k] ?? 0}', style: num, textAlign: TextAlign.right)),
                          const SizedBox(width: 6),
                          icon(k),
                          const SizedBox(width: 6),
                          Expanded(child: Text('${b[k] ?? 0}', style: num.copyWith(color: scheme.outline))),
                        ]),
                      ),
                    ),
                ]),
        ),
      ]);
    }

    Widget ring(Side side) {
      final counts = kindsIn(widget.byUnit[_ringUnit]!, side);
      final negative = counts.entries.where((e) => _negative.contains(e.key)).fold(0, (x, e) => x + e.value);
      return Row(children: [
        TweenAnimationBuilder<double>(
          key: ValueKey('$_ringUnit-$side'),
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) => SizedBox.square(
            dimension: 60,
            child: CustomPaint(
              painter: _RingPainter([for (final k in _order) if ((counts[k] ?? 0) > 0) (markColor(k), counts[k]!)], t,
                  scheme.surfaceContainerHighest,
                  stroke: 7),
              child: Center(child: Text('${counts.values.fold(0, (x, y) => x + y)}', style: num.copyWith(fontSize: 17))),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(side == Side.white ? 'White' : 'Black', style: Theme.of(context).textTheme.titleMedium),
            Text('$negative negative', maxLines: 1, style: TextStyle(fontSize: 11.5, color: scheme.outline)),
          ]),
        ),
      ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text('Moves by kind', style: Theme.of(context).textTheme.titleMedium)),
        IconButton(
          tooltip: _rings ? 'Show as lists' : 'Show as rings',
          onPressed: () => setState(() => _rings = !_rings),
          icon: Icon(_rings ? Icons.format_list_numbered_rounded : Icons.donut_large_rounded),
        ),
      ]),
      // смена вида — сверху вниз, без прыжка круга в середину списка
      AnimatedSize(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeInOutCubic,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        layoutBuilder: (current, previous) =>
            Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
        child: _rings
            ? Column(key: const ValueKey('rings'), children: [
                Row(children: [
                  for (final u in _units)
                    Expanded(child: header(u, u == _ringUnit, () => setState(() => _ringUnit = u))),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: ring(Side.white)),
                  const SizedBox(width: 8),
                  Expanded(child: ring(Side.black)),
                ]),
              ])
            : Row(key: const ValueKey('lists'), crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final u in _units) Expanded(child: column(u)),
              ]),
      ),
      ),
      const SizedBox(height: 16),
      _GameMistakes(c: widget.c),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text('Colour icons'),
        subtitle: const Text('The icons of the lists in their own colours'),
        value: colour,
        onChanged: (v) => setState(() => prefs.update(colourIcons: v)),
      ),
    ]);
  }
}

/// A row that drops in from a little above as it fades in.
class _DropIn extends StatefulWidget {
  const _DropIn({super.key, required this.delay, required this.child});

  final Duration delay;
  final Widget child;

  @override
  State<_DropIn> createState() => _DropInState();
}

class _DropInState extends State<_DropIn> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (mounted) _a.forward();
    });
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _a,
        builder: (context, child) {
          final t = Curves.easeOutCubic.transform(_a.value);
          return Opacity(opacity: t, child: Transform.translate(offset: Offset(0, -10 * (1 - t)), child: child));
        },
        child: widget.child,
      );
}

/// The game's mistakes by what they missed: the key blunder (the worst move)
/// first, then the kinds of missed moves from the most frequent and costly
/// to those met once.
class _GameMistakes extends StatelessWidget {
  const _GameMistakes({required this.c});

  final AnalysisController c;

  static const _weight = {'blunder': 4.0, 'mistake': 3.0, 'laxity': 2.0, 'pass': 1.5, 'inaccuracy': 1.0};

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    List<MapEntry<String, (double, int, String)>> rowsOf(Side side) {
      final groups = <String, (double, int, String)>{}; // kind → (weight, count, worst step)
      for (final r in c.analysis.records.where((r) => r.side == side)) {
        final w = _weight[r.step];
        if (w == null) continue;
        final missed = c.kindsAt(r.ply).$2;
        final k = missed.isEmpty ? 'other' : missed.first;
        final g = groups[k];
        final worst = g == null || w > (_weight[g.$3] ?? 0) ? r.step : g.$3;
        groups[k] = ((g?.$1 ?? 0) + w, (g?.$2 ?? 0) + 1, worst);
      }
      return groups.entries.toList()..sort((a, b) => b.value.$1.compareTo(a.value.$1));
    }

    final bySide = {for (final side in Side.values) side: rowsOf(side)};
    if (bySide.values.every((r) => r.isEmpty)) return const SizedBox.shrink();
    final key = [Side.white, Side.black]
        .map(c.worstPly)
        .whereType<int>()
        .fold<int?>(null, (best, p) => best == null || c.analysis.records[p].wdl.e1 - c.analysis.records[p].wdl.ep >
                c.analysis.records[best].wdl.e1 - c.analysis.records[best].wdl.ep
            ? p
            : best);
    Widget row(MapEntry<String, (double, int, String)> e) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            SizedBox(width: 30, child: Text('${e.value.$2}×', style: const TextStyle(fontWeight: FontWeight.w700))),
            Expanded(child: Text(e.key == 'other' ? 'Other' : 'Missed ${kindLabels[e.key] ?? e.key}')),
            Text(stepLabels[e.value.$3] ?? e.value.$3,
                style: TextStyle(fontSize: 12, color: stepColor(e.value.$3, Theme.of(context).brightness))),
          ]),
        );
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 6),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text('Mistakes of the game', style: Theme.of(context).textTheme.titleMedium),
        children: [
          if (key != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                StepIcon(kind: c.analysis.records[key].step, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Key blunder: ${plyText(key)} ${c.analysis.records[key].san}'
                    '${c.kindsAt(key).$2.isEmpty ? '' : ' — missed ${kindLabels[c.kindsAt(key).$2.first]}'}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ]),
            ),
          // по цвету: у кого какие ошибки, с ником в заголовке
          for (final side in Side.values)
            if (bySide[side]!.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 2),
                child: Row(children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: side == Side.white ? const Color(0xFFF2F2F2) : const Color(0xFF3A3A3A),
                      border: Border.all(color: scheme.outline, width: 1),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(side == Side.white ? c.game.white : c.game.black,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ]),
              ),
              for (final e in bySide[side]!) row(e),
            ],
          const SizedBox(height: 4),
          Text('Sorted by how often and how costly; the worst grade of each is on the right.',
              style: TextStyle(fontSize: 11, color: scheme.outline)),
        ],
      ),
    );
  }
}

/// Donut of coloured parts (small gaps between them), drawn up to [t].
class _RingPainter extends CustomPainter {
  _RingPainter(this.parts, this.t, this.track, {this.stroke = 9});

  final List<(Color, int)> parts;
  final double t;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawArc(rect, 0, 2 * math.pi, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track);
    final total = parts.fold(0, (a, p) => a + p.$2);
    if (total == 0) return;
    const gap = 0.04;
    var start = -math.pi / 2;
    final end = -math.pi / 2 + 2 * math.pi * t;
    for (final (color, n) in parts) {
      final sweep = 2 * math.pi * n / total;
      final a0 = start + (parts.length > 1 ? gap / 2 : 0);
      final a1 = math.min(start + sweep - (parts.length > 1 ? gap / 2 : 0), end);
      if (a1 > a0) {
        canvas.drawArc(rect, a0, a1 - a0, false, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = color);
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.t != t || old.parts != parts;
}

