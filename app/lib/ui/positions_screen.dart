/// Positions worth remembering ("chunks"): those solved in puzzles and those
/// underlined in games as not understood. Each shows its traits — colour,
/// stage, character of the position, type and kinds of the key move, what
/// the mistake cost — and a rough rating of how hard the key move is to
/// find. On top, the traits summed up: how many positions of each kind were
/// solved or underlined, and their mean rating.
library;

import 'package:flutter/material.dart';

import '../analysis/character.dart';
import '../analysis/features.dart' as features;
import '../analysis/game.dart';
import '../analysis/openings.dart';
import '../analysis/pos.dart';
import '../analysis/settings.dart';
import '../analysis/weakness.dart';
import 'controller.dart';
import 'game_screen.dart';
import 'labels.dart';
import 'player_stats.dart';
import 'puzzles.dart';
import 'underlines.dart';

class PositionEntry {
  PositionEntry({
    required this.game,
    required this.ply,
    required this.source,
    required this.tags,
    required this.rating,
    required this.title,
  });

  final GameData game;
  final int ply;

  /// 'solved' (a puzzle) or 'underlined' (a game).
  final String source;
  final Set<String> tags;
  final int rating;
  final String title;
}

/// [простое решение] How hard the key move is to find, without the engine:
/// 900, +250 for a quiet move (no capture, check or promotion), +200 in a
/// sharp position, +150 for a positional move, +100 for each forcing ply of
/// the line after the first two (deep calculation), within 400…3000.
int findRating(Pos board, String bestUci, List<String> pv, String type, Sharpness? sharpness) {
  final m = Pos.move(bestUci);
  final quiet = !board.isCapture(m) && !board.givesCheck(m) && m.promotion == null;
  final forcing = features.forcingCount(board, pv, 10);
  final r = 900 +
      (quiet ? 250 : 0) +
      (sharpness == Sharpness.sharp ? 200 : 0) +
      (type == 'positional' ? 150 : 0) +
      100 * (forcing - 2).clamp(0, 6);
  return r.clamp(400, 3000);
}

Future<List<PositionEntry>> collectPositions(List<GameData> showcase, OpeningBook? book) async {
  const s = Settings(unit: Unit.pawns);
  await underlines.load();
  final analyses = [
    for (final g in showcase) analyzeGame(g, s, book: book),
    ...await ownAnalyses(book),
  ];
  // из задач — только сохранённые промахи (позиция, где был неверный ход)
  final missed = <String, PuzzleAttempt>{};
  for (final a in await PuzzleHistory.load()) {
    if (!a.solved && a.fen != null) missed.putIfAbsent(a.id, () => a);
  }
  final ratings = await PuzzleRatings.load();
  final out = <PositionEntry>[];
  for (final a in analyses) {
    for (final r in a.records) {
      final key = '${a.game.id}:${r.ply}';
      final miss = missed[key];
      final isUnderlined = underlines.has(a.game.id, r.ply);
      if (miss == null && !isUnderlined) continue;
      final p = a.game.plies[r.ply];
      final board = Pos.fromFen(p.fenBefore);
      final best = p.lines.first;
      final ch = characterOf(board, p.lines, p.allLines, const Settings());
      final type = r.bestMoves.isNotEmpty ? r.bestMoves.first.type : r.moveType;
      final next = r.ply + 1 < a.game.plies.length ? a.game.plies[r.ply + 1] : null;
      final tags = <String>{
        ...isUnderlined
            ? mistakeTags(r, board, best,
                after: next == null ? null : Pos.fromFen(next.fenBefore), reply: next?.lines.firstOrNull, lines: p.lines)
            : puzzleTags(r, board, best, lines: p.lines),
        if (ch.sharpness != null) 'char:${ch.sharpness!.name}',
        if (ch.quiet) 'char:quiet',
      };
      final step = miss?.step ?? 0;
      out.add(PositionEntry(
        game: a.game,
        ply: r.ply,
        source: isUnderlined ? 'underlined' : 'missed',
        tags: tags,
        rating: miss?.rating ?? ratings[key] ?? findRating(board, best.move, best.pv, type, ch.sharpness),
        title: '${a.game.title}, ${plyText(r.ply)} ${r.san}'
            '${!isUnderlined && step > 0 ? ' · solution move ${step ~/ 2 + 1}' : ''}',
      ));
    }
  }
  return out;
}

/// Groups of traits, from the most general to the most particular.
const traitGroups = [
  ('colour', 'Colour'),
  ('stage', 'Stage'),
  ('type', 'Type'),
  ('dir', 'Direction'),
  ('char', 'Character'),
  ('kind', 'Missed move'),
  ('punish', 'Punished by'),
  ('loss', 'Cost'),
  ('irr', 'Irreversibility'),
];

String _group(String tag) => tag.substring(0, tag.indexOf(':'));

String positionTagLabel(String tag) {
  if (tag.startsWith('char:')) {
    final v = tag.substring(5);
    return '${v[0].toUpperCase()}${v.substring(1)} position';
  }
  return tagLabel(tag);
}

class PositionsScreen extends StatefulWidget {
  const PositionsScreen({super.key, required this.games, required this.book});

  final List<GameData> games;
  final OpeningBook book;

  @override
  State<PositionsScreen> createState() => _PositionsScreenState();
}

class _PositionsScreenState extends State<PositionsScreen> {
  List<PositionEntry>? _all;
  String _filter = 'all';
  String _query = '';
  final _chips = <String>{};
  RangeValues _range = const RangeValues(400, 3000);
  bool _filters = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 350), () async {
      final list = await collectPositions(widget.games, widget.book);
      if (mounted) setState(() => _all = list);
    });
  }

  void _open(PositionEntry e) {
    final c = AnalysisController(e.game, book: widget.book);
    c.select(e.ply);
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => GameScreen(controller: c, keepPosition: true)));
  }

  bool _matches(PositionEntry e) {
    if (_filter != 'all' && e.source != _filter) return false;
    if (e.rating < _range.start || e.rating > _range.end) return false;
    if (!_chips.every(e.tags.contains)) return false;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return e.title.toLowerCase().contains(q) || e.tags.any((t) => positionTagLabel(t).toLowerCase().contains(q));
  }

  Widget _chip(String tag, ColorScheme scheme) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
        child: Text(positionTagLabel(tag), style: const TextStyle(fontSize: 11)),
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final all = _all;
    final list = all == null ? null : [for (final e in all) if (_matches(e)) e];
    // признаки, сложенные по всем позициям: сколько и какой средний рейтинг
    final traits = <String, (int, int, int)>{}; // tag → (missed, underlined, rating sum)
    for (final e in list ?? const <PositionEntry>[]) {
      for (final t in e.tags) {
        final v = traits[t] ?? (0, 0, 0);
        traits[t] = (v.$1 + (e.source == 'missed' ? 1 : 0), v.$2 + (e.source == 'underlined' ? 1 : 0), v.$3 + e.rating);
      }
    }
    final allTags = <String>{for (final e in all ?? const <PositionEntry>[]) ...e.tags};
    List<String> ofGroup(Iterable<String> tags, String g) =>
        [for (final t in tags) if (_group(t) == g) t]..sort();
    return Scaffold(
      appBar: AppBar(title: const Text('Positions')),
      body: list == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              Text('Positions where you went wrong in puzzles (saved after the mistake) and moves you underlined in '
                  'games as not understood.',
                  style: TextStyle(fontSize: 13, color: scheme.outline)),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'all', label: Text('All')),
                  ButtonSegment(value: 'missed', label: Text('Puzzle misses')),
                  ButtonSegment(value: 'underlined', label: Text('Underlined')),
                ],
                selected: {_filter},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _filter = s.first),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Search games, players, traits',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Filter',
                  isSelected: _filters,
                  onPressed: () => setState(() => _filters = !_filters),
                  icon: Badge(
                    isLabelVisible: _chips.isNotEmpty || _range != const RangeValues(400, 3000),
                    smallSize: 7,
                    child: const Icon(Icons.filter_list_rounded),
                  ),
                ),
              ]),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: !_filters
                    ? const SizedBox(width: double.infinity)
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const SizedBox(height: 10),
                        Text('Rating ${_range.start.round()}–${_range.end.round()}',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        RangeSlider(
                          values: _range,
                          min: 400,
                          max: 3000,
                          divisions: 26,
                          labels: RangeLabels('${_range.start.round()}', '${_range.end.round()}'),
                          onChanged: (v) => setState(() => _range = v),
                        ),
                        for (final (g, name) in traitGroups)
                          if (ofGroup(allTags, g).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                                SizedBox(
                                    width: 96,
                                    child: Text(name, style: TextStyle(fontSize: 12, color: scheme.outline))),
                                for (final t in ofGroup(allTags, g))
                                  FilterChip(
                                    visualDensity: VisualDensity.compact,
                                    label: Text(positionTagLabel(t), style: const TextStyle(fontSize: 12)),
                                    selected: _chips.contains(t),
                                    onSelected: (on) => setState(() => on ? _chips.add(t) : _chips.remove(t)),
                                  ),
                              ]),
                            ),
                        if (_chips.isNotEmpty || _range != const RangeValues(400, 3000))
                          TextButton(
                            onPressed: () => setState(() {
                              _chips.clear();
                              _range = const RangeValues(400, 3000);
                            }),
                            child: const Text('Clear filters'),
                          ),
                      ]),
              ),
              const SizedBox(height: 14),
              Text('By trait', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              if (traits.isEmpty)
                Text('Nothing yet: save a puzzle after a mistake, or underline mistakes you did not understand.',
                    style: TextStyle(color: scheme.outline)),
              // от общего к частному: цвет → стадия → тип → направление → характер → виды
              for (final (g, name) in traitGroups)
                if (ofGroup(traits.keys, g).isNotEmpty)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 6),
                    dense: true,
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    children: [
                      for (final t in ofGroup(traits.keys, g)
                        ..sort((a, b) => (traits[b]!.$1 + traits[b]!.$2).compareTo(traits[a]!.$1 + traits[a]!.$2)))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(children: [
                            Expanded(child: Text(positionTagLabel(t), style: const TextStyle(fontSize: 13))),
                            Text('${traits[t]!.$1} missed · ${traits[t]!.$2} underlined · '
                                '${(traits[t]!.$3 / (traits[t]!.$1 + traits[t]!.$2)).round()}',
                                style: TextStyle(fontSize: 12, color: scheme.outline)),
                          ]),
                        ),
                    ],
                  ),
              const SizedBox(height: 14),
              Text('Positions (${list.length})', style: Theme.of(context).textTheme.titleMedium),
              for (final e in list)
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _open(e),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(e.source == 'missed' ? Icons.close_rounded : Icons.bookmark_rounded,
                              size: 18, color: e.source == 'missed' ? scheme.error : scheme.tertiary),
                          const SizedBox(width: 6),
                          Expanded(child: Text(e.title, style: const TextStyle(fontWeight: FontWeight.w600))),
                          Text('${e.rating}', style: TextStyle(color: scheme.outline, fontWeight: FontWeight.w700)),
                        ]),
                        const SizedBox(height: 6),
                        Wrap(spacing: 6, runSpacing: 4, children: [
                          for (final (g, _) in traitGroups)
                            for (final t in ofGroup(e.tags, g)) _chip(t, scheme),
                        ]),
                      ]),
                    ),
                  ),
                ),
            ]),
    );
  }
}
