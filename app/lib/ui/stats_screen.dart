/// Statistics of the player's own analysed games: results and mistakes by
/// colour, mistakes by stage, the kinds of best moves they miss, how the
/// mistakes cost them, and the weakness profile with its "chunks" (how many
/// similar puzzles were solved, and how hard).
library;

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
    final field = TextEditingController(text: prefs.playerName.isEmpty ? _st?.name ?? '' : prefs.playerName);
    final v = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your names in the games'),
        content: TextField(
            controller: field,
            autofocus: true,
            decoration: const InputDecoration(
                hintText: 'Name or nickname', helperText: 'Several names: separate them with commas')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, field.text), child: const Text('OK')),
        ],
      ),
    );
    field.dispose();
    if (v == null) return;
    prefs.update(name: v.trim());
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

    return Scaffold(
      appBar: AppBar(title: const Text('Statistics'), actions: [
        IconButton(tooltip: 'Your names', onPressed: _rename, icon: const Icon(Icons.badge_outlined)),
      ]),
      body: st == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              Text(st.name.isEmpty ? 'No own games analysed yet.' : 'Games of ${st.name}: ${st.games}',
                  style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('Only your own analysed games count. Tap the badge above to set your name if it is not found.',
                  style: muted),
              const SizedBox(height: 16),
              Text('By colour', style: title),
              const SizedBox(height: 6),
              for (final side in Side.values)
                Builder(builder: (context) {
                  final c = st.colours[side]!;
                  final errors = c.steps.values.fold(0, (a, b) => a + b);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 12,
                      backgroundColor: side == Side.white ? const Color(0xFFF2F2F2) : const Color(0xFF202020),
                    ),
                    title: Text('${side == Side.white ? 'White' : 'Black'}: ${c.games} games · '
                        '${c.wins} won, ${c.draws} drawn, ${c.losses} lost'),
                    subtitle: Text(c.games == 0
                        ? '—'
                        : '${(errors / c.games).toStringAsFixed(1)} negative moves a game · '
                            '${c.steps['blunder'] ?? 0} blunders, ${c.steps['mistake'] ?? 0} mistakes, '
                            '${c.steps['laxity'] ?? 0} weaknesses, ${c.steps['inaccuracy'] ?? 0} inaccuracies'),
                  );
                }),
              const SizedBox(height: 12),
              Text('Mistakes by stage', style: title),
              const SizedBox(height: 6),
              bars(st.stages, (k) => stageLabels[k] ?? k),
              const SizedBox(height: 16),
              Text('Best moves you missed', style: title),
              const SizedBox(height: 6),
              bars(st.missed, (k) => kindLabels[k] ?? k),
              const SizedBox(height: 16),
              Text('How the mistakes were punished', style: title),
              const SizedBox(height: 6),
              if (st.punished.isEmpty)
                const Text('—')
              else
                bars(st.punished, (k) => kindLabels[k] ?? k),
              const SizedBox(height: 16),
              Text('What the mistakes cost', style: title),
              const SizedBox(height: 6),
              bars(st.losses, (k) => lossLabels[k] ?? k),
              const SizedBox(height: 8),
              bars(st.irreversibility, (k) => 'Irreversibility: ${irreversibilityLabels[k] ?? k}'),
              const SizedBox(height: 16),
              Text('Weakness profile', style: title),
              const SizedBox(height: 4),
              Text('Weighted by how bad the mistakes were; underlined ones count double. Puzzles like these come first '
                  'when "Consider weaknesses" is on.', style: muted),
              const SizedBox(height: 6),
              bars({for (final e in st.profile.entries) e.key: e.value}, tagLabel, color: scheme.error),
              const SizedBox(height: 16),
              Text('Training of the weak spots', style: title),
              const SizedBox(height: 4),
              Text('Solved puzzles with the same trait and their mean rating: the more and the harder, the better '
                  'the pattern is learnt.', style: muted),
              const SizedBox(height: 6),
              for (final e in st.chunks.entries)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(tagLabel(e.key)),
                  trailing: Text(e.value.$1 == 0 ? 'not trained yet' : '${e.value.$1} solved · ${e.value.$2.round()}'),
                ),
            ]),
    );
  }
}
