/// Statistics of the player's own analysed games: results by colour as
/// rings (won, drawn, lost; negative moves under them), mistakes by stage,
/// accuracy by kind of move, the kinds of best moves they miss, how the
/// mistakes cost them, and the weakness profile with its "chunks" (how many
/// similar puzzles were solved, and how hard).
library;

import 'dart:math' as math;

import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/material.dart';

import '../analysis/kinds.dart';
import '../analysis/openings.dart';
import '../analysis/weakness.dart';
import 'labels.dart';
import 'player_stats.dart';
import 'prefs.dart';
import 'puzzles.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, this.book});

  final OpeningBook? book;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  PlayerStats? _st;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final games = await ownAnalyses(widget.book);
    final puzzles = [for (final a in games) ...puzzlesFrom(a)];
    final st = await collectStats(games, puzzles: puzzles);
    if (mounted) setState(() => _st = st);
  }

  Future<void> _rename() async {
    final v = await askPlayerNames(context, prefs.playerName.isEmpty ? _st?.name ?? '' : prefs.playerName);
    if (v == null) return;
    setState(() => _st = null);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final st = _st;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = theme.textTheme.titleMedium;
    final muted = TextStyle(fontSize: 13, color: scheme.outline);
    Widget bars(Map<String, num> m, String Function(String) label, {Color? color}) {
      if (m.isEmpty) return Text('—', style: muted);
      final top = m.values.fold<num>(1, (a, b) => b > a ? b : a);
      final rows = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      return Column(children: [
        for (final e in rows.take(8))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              SizedBox(width: 150, child: Text(label(e.key), style: const TextStyle(fontSize: 13))),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: e.value / top,
                    minHeight: 8,
                    color: color,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
              ),
              SizedBox(width: 44, child: Text(e.value is double ? (e.value as double).toStringAsFixed(1) : '${e.value}',
                  textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
            ]),
          ),
      ]);
    }

    // карточка раздела: заголовок с иконкой, пояснение, содержимое
    Widget section(IconData icon, String name, Widget child, {String? note}) => Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(name, style: title)),
              ]),
              if (note != null) ...[const SizedBox(height: 4), Text(note, style: muted)],
              const SizedBox(height: 8),
              child,
            ]),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Statistics'), actions: [
        IconButton(tooltip: 'Your names', onPressed: _rename, icon: const Icon(Icons.badge_outlined)),
      ]),
      body: st == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              Text(st.name.isEmpty ? 'No own games analysed yet.' : st.name, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text('Only your own analysed games count. Tap the badge above to set your name if it is not found.',
                  style: muted),
              const SizedBox(height: 14),
              // партии: круги с секторами побед, ничьих и поражений, число в середине
              section(
                Icons.donut_large_rounded,
                'Games',
                Row(children: [
                  Expanded(child: _ResultRing(label: 'All', colours: [st.colours[Side.white]!, st.colours[Side.black]!])),
                  Expanded(child: _ResultRing(label: 'White', colours: [st.colours[Side.white]!])),
                  Expanded(child: _ResultRing(label: 'Black', colours: [st.colours[Side.black]!])),
                ]),
                note: 'Won, drawn and lost; under each ring the negative moves (inaccuracy and worse).',
              ),
              section(Icons.timeline_rounded, 'Mistakes by stage', bars(st.stages, (k) => stageLabels[k] ?? k)),
              // аккуратность по видам ходов: сколько, насколько точно, сколько пропущено
              section(
                Icons.category_outlined,
                'Accuracy by kind of move',
                _KindTable(st: st),
                note: 'Moves: your moves of this kind. Accuracy: their mean accuracy. Missed: times this kind was the '
                    'best move and you played another.',
              ),
              section(Icons.search_off_rounded, 'Best moves you missed', bars(st.missed, (k) => kindLabels[k] ?? k)),
              section(
                Icons.bolt_rounded,
                'How the mistakes were punished',
                st.punished.isEmpty ? const Text('—') : bars(st.punished, (k) => kindLabels[k] ?? k),
              ),
              section(
                Icons.trending_down_rounded,
                'What the mistakes cost',
                Column(children: [
                  bars(st.losses, (k) => lossLabels[k] ?? k),
                  const SizedBox(height: 8),
                  bars(st.irreversibility, (k) => 'Irreversibility: ${irreversibilityLabels[k] ?? k}'),
                ]),
              ),
              section(
                Icons.healing_rounded,
                'Weakness profile',
                bars({for (final e in st.profile.entries) e.key: e.value}, tagLabel, color: scheme.error),
                note: 'Weighted by how bad the mistakes were; underlined ones count double, mistakes in puzzles and '
                    'in Start to improve a little less. Puzzles like these come first when "Consider weaknesses" is on.',
              ),
              section(
                Icons.fitness_center_rounded,
                'Training of the weak spots',
                Column(children: [
                  for (final e in st.chunks.entries)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(tagLabel(e.key)),
                      trailing:
                          Text(e.value.$1 == 0 ? 'not trained yet' : '${e.value.$1} solved · ${e.value.$2.round()}'),
                    ),
                ]),
                note: 'Solved puzzles with the same trait and their mean rating: the more and the harder, the better '
                    'the pattern is learnt.',
              ),
            ]),
    );
  }
}

/// A ring of results: won (green), drawn (grey), lost (red) sectors, the
/// number of games in the middle and the negative moves under it.
class _ResultRing extends StatelessWidget {
  const _ResultRing({required this.label, required this.colours});

  final String label;
  final List<ColourStats> colours;

  static const _negative = {'inaccuracy', 'laxity', 'pass', 'mistake', 'blunder'};

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    int sum(int Function(ColourStats) f) => colours.fold(0, (a, c) => a + f(c));
    final games = sum((c) => c.games), won = sum((c) => c.wins), drawn = sum((c) => c.draws), lost = sum((c) => c.losses);
    final negative =
        sum((c) => c.steps.entries.where((e) => _negative.contains(e.key)).fold(0, (a, e) => a + e.value));
    return Column(children: [
      TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => SizedBox.square(
          dimension: 84,
          child: CustomPaint(
            painter: _SectorsPainter([
              (const Color(0xFF4CAF50), won),
              (const Color(0xFF9E9E9E), drawn),
              (const Color(0xFFD7322F), lost),
            ], t, scheme.surfaceContainerHighest),
            child: Center(
              child: Text('$games', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ),
          ),
        ),
      ),
      const SizedBox(height: 6),
      Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      Text('$won · $drawn · $lost', style: TextStyle(fontSize: 11, color: scheme.outline)),
      Text('$negative negative', style: TextStyle(fontSize: 11, color: scheme.error)),
    ]);
  }
}

class _SectorsPainter extends CustomPainter {
  _SectorsPainter(this.parts, this.t, this.track);

  final List<(Color, int)> parts;
  final double t;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 11.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    Paint arc(Color c) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt
      ..color = c;
    canvas.drawArc(rect, 0, 2 * math.pi, false, arc(track));
    final total = parts.fold(0, (a, p) => a + p.$2);
    if (total == 0) return;
    final shown = [for (final p in parts) if (p.$2 > 0) p];
    final gap = shown.length > 1 ? 0.05 : 0.0;
    var start = -math.pi / 2;
    final end = -math.pi / 2 + 2 * math.pi * t;
    for (final (color, n) in shown) {
      final sweep = 2 * math.pi * n / total;
      final a1 = math.min(start + sweep - gap / 2, end);
      final a0 = start + gap / 2;
      if (a1 > a0) canvas.drawArc(rect, a0, a1 - a0, false, arc(color));
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_SectorsPainter old) => old.t != t || old.parts != parts;
}

/// Kinds of move: name, the player's moves of that kind, their mean
/// accuracy, and how often that kind was the best move and was missed.
class _KindTable extends StatelessWidget {
  const _KindTable({required this.st});

  final PlayerStats st;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final kinds = {...st.kindMoves.keys, ...st.missed.keys}.toList()
      ..sort((a, b) => (st.kindMoves[b]?.$1 ?? 0).compareTo(st.kindMoves[a]?.$1 ?? 0));
    if (kinds.isEmpty) return Text('—', style: TextStyle(color: scheme.outline));
    const numStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]);
    final head = TextStyle(fontSize: 11, color: scheme.outline, fontWeight: FontWeight.w600);
    Color accColor(double a) =>
        a >= 85 ? const Color(0xFF4CAF50) : (a >= 65 ? const Color(0xFFF0B414) : const Color(0xFFD7322F));
    return Column(children: [
      Row(children: [
        Expanded(child: Text('Kind', style: head)),
        SizedBox(width: 52, child: Text('Moves', style: head, textAlign: TextAlign.right)),
        SizedBox(width: 70, child: Text('Accuracy', style: head, textAlign: TextAlign.right)),
        SizedBox(width: 56, child: Text('Missed', style: head, textAlign: TextAlign.right)),
      ]),
      const Divider(height: 10),
      for (final k in kinds)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(
                child: Text(kindLabels[k] ?? k,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
            SizedBox(width: 52, child: Text('${st.kindMoves[k]?.$1 ?? 0}', style: numStyle, textAlign: TextAlign.right)),
            SizedBox(
              width: 70,
              child: switch (st.kindMoves[k]) {
                (final n, final sum) when n > 0 => Text('${(sum / n).toStringAsFixed(1)}%',
                    style: numStyle.copyWith(color: accColor(sum / n)), textAlign: TextAlign.right),
                _ => Text('–', style: numStyle, textAlign: TextAlign.right),
              },
            ),
            SizedBox(
              width: 56,
              child: Text('${st.missed[k] ?? 0}',
                  style: numStyle.copyWith(color: (st.missed[k] ?? 0) > 0 ? scheme.error : scheme.outline),
                  textAlign: TextAlign.right),
            ),
          ]),
        ),
    ]);
  }
}

/// Asks for the player's names in the games and saves them; null when
/// cancelled.
Future<String?> askPlayerNames(BuildContext context, String initial) async {
  final field = TextEditingController(text: initial);
  final v = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Your names in the games'),
      content: TextField(
          controller: field,
          autofocus: true,
          decoration: const InputDecoration(
              hintText: 'Name or nickname',
              // описание важное — целиком, в несколько строк
              helperMaxLines: 6,
              helperText: 'Several names (accounts on different sites): separate them with commas. With your name '
                  'the statistics and the puzzles follow your own mistakes, not your opponents\'.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, field.text), child: const Text('OK')),
      ],
    ),
  );
  field.dispose();
  if (v != null) prefs.update(name: v.trim());
  return v?.trim();
}
