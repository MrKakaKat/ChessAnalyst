/// History of the user's analyses: open one to read it or to continue the
/// engine work. A long press selects analyses (or all of them) to analyse
/// again at another depth and number of lines, or to delete together with
/// the puzzles made from them.
library;

import 'package:flutter/material.dart';

import '../analysis/openings.dart';
import '../engine/game_job.dart';
import 'analysis_queue.dart';
import 'controller.dart';
import 'game_screen.dart';
import 'history_store.dart';
import 'import_screen.dart';
import 'job_screen.dart';
import 'prefs.dart';
import 'puzzles.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.book});

  final OpeningBook book;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

/// Date and time of a finished analysis, local: "2026-11-04 21:46".
String _when(DateTime t) {
  final l = t.toLocal();
  String two(int x) => x.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _selected = <String>{};

  /// Only the favourite games.
  bool _favOnly = false;

  bool get _selecting => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    history.addListener(_rebuild);
    history.load();
  }

  @override
  void dispose() {
    history.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  Future<void> _open(String id) async {
    final job = await history.open(id);
    if (job == null || !mounted) return;
    // недоделанный разбор (прерван закрытием приложения или ошибкой движка)
    // продолжается сам; поставленный пользователем на паузу — нет
    if (job.stalled) analysisQueue.add(job);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => job.ready
            ? GameScreen(
                controller: AnalysisController(job.snapshot(), book: widget.book),
                job: job,
              )
            : JobScreen(job: job, book: widget.book),
      ),
    );
  }

  /// The analysis window of a running analysis (its ring was tapped).
  Future<void> _openJob(String id) async {
    final job = await history.open(id);
    if (job == null || !mounted) return;
    if (job.stalled) analysisQueue.add(job);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => JobScreen(job: job, book: widget.book, autoOpen: false),
      ),
    );
  }

  void _toggle(String id) => setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));

  /// Deletes the analyses and the puzzles made from them (with their ratings
  /// and recorded attempts), after a warning.
  Future<void> _delete(Set<String> ids) async {
    final n = ids.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(n == 1 ? 'Delete this analysis?' : 'Delete $n analyses?'),
        content: const Text(
          'The puzzles made from these games go too, with their ratings and recorded attempts. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    for (final id in ids) {
      await history.remove(id);
      await PuzzleRatings.removeGame(id);
      await PuzzleHistory.removeGame(id);
    }
    if (mounted) setState(_selected.clear);
  }

  /// Analyses the games again at a chosen depth and number of lines.
  Future<void> _reanalyze(Set<String> ids) async {
    var depth = depthPresets['Standard']!;
    var lines = prefs.engineLines;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: Text(ids.length == 1 ? 'Analyze again' : 'Analyze ${ids.length} games again'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Depth $depth'),
              Slider(
                value: depth.toDouble(),
                min: 1,
                max: maxDepth.toDouble(),
                divisions: maxDepth - 1,
                label: '$depth',
                onChanged: (v) => set(() => depth = v.round()),
              ),
              Text('Lines per move: $lines'),
              Slider(
                value: lines.toDouble(),
                min: 5,
                max: 25,
                divisions: 20,
                label: '$lines',
                onChanged: (v) => set(() => lines = v.round()),
              ),
              const Text(
                'The old analysis is replaced; the puzzles follow the new one.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Analyze')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final jobs = <AnalysisJob>[];
    for (final id in ids) {
      final old = await history.open(id);
      if (old == null) continue;
      old.pause();
      analysisQueue.remove(old);
      final job = AnalysisJob(id: old.id, source: old.source, targetDepth: depth, multipv: lines, power: old.power, puzzles: old.puzzles);
      await PuzzleRatings.removeGame(id);
      jobs.add(job);
    }
    // движок один: разборы встают в очередь и идут по одному
    jobs.forEach(analysisQueue.add);
    if (mounted) setState(_selected.clear);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = [
      for (final e in history.entries)
        if (!_favOnly || history.isFavorite(e.id)) e,
    ];
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_selected.clear);
      },
      child: Scaffold(
        appBar: _selecting
            ? AppBar(
                leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(_selected.clear)),
                title: Text('${_selected.length} selected'),
                actions: [
                  IconButton(
                    tooltip: 'Select all',
                    onPressed: () => setState(() => _selected.addAll(entries.map((e) => e.id))),
                    icon: const Icon(Icons.select_all_rounded),
                  ),
                  IconButton(
                    tooltip: 'Analyze again',
                    onPressed: () => _reanalyze({..._selected}),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    onPressed: () => _delete({..._selected}),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              )
            : AppBar(
                title: const Text('Analysis history'),
                actions: [
                  if (entries.isNotEmpty)
                    IconButton(
                      tooltip: 'Select',
                      onPressed: () => setState(() => _selected.add(entries.first.id)),
                      icon: const Icon(Icons.checklist_rounded),
                    ),
                ],
              ),
        floatingActionButton: _selecting
            ? null
            : FloatingActionButton.extended(
                onPressed: () =>
                    Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => ImportScreen(book: widget.book))),
                icon: const Icon(Icons.add_rounded),
                label: const Text('New analysis'),
              ),
        body: history.entries.isEmpty
            ? Center(
                child: Text('No analyses yet.', style: TextStyle(color: scheme.outline)),
              )
            : ListView(
                padding: const EdgeInsets.only(bottom: 88),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Row(
                      children: [
                        const Spacer(),
                        FilterChip(
                          avatar: Icon(_favOnly ? Icons.star_rounded : Icons.star_border_rounded, size: 18),
                          label: const Text('Favourites'),
                          showCheckmark: false,
                          selected: _favOnly,
                          onSelected: (v) => setState(() => _favOnly = v),
                        ),
                      ],
                    ),
                  ),
                  if (entries.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No favourite games yet: tap the star of a finished analysis.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.outline),
                      ),
                    ),
                  for (final e in entries)
                    ListTile(
                      selected: _selected.contains(e.id),
                      leading: _selecting
                          ? Checkbox(value: _selected.contains(e.id), onChanged: (_) => _toggle(e.id))
                          : null,
                      // идущий анализ затемнён — кроме его кружка
                      title: Opacity(
                        opacity: e.progress < 1 ? 0.45 : 1,
                        child: Row(
                          children: [
                            Flexible(child: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
                            // сделан по старым правилам анализа — пометка «переанализировать»
                            if (e.outdated && e.progress >= 1)
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: ActionChip(
                                  visualDensity: VisualDensity.compact,
                                  avatar: const Icon(Icons.update_rounded, size: 16),
                                  label: const Text('Re-analyse', style: TextStyle(fontSize: 11)),
                                  tooltip: 'Analysed with older rules: analyse again for the new kinds of moves',
                                  onPressed: () => _reanalyze({e.id}),
                                ),
                              ),
                          ],
                        ),
                      ),
                      subtitle: Opacity(
                        opacity: e.progress < 1 ? 0.45 : 1,
                        child: Text(
                          '${e.date.replaceAll('.??', '')} · depth ${e.depth}${e.progress < 1 ? ' of ${e.target}, ${(e.progress * 100).round()}%' : ''}'
                          '${e.finished != null ? ' · analysed ${_when(e.finished!)}' : ''}',
                        ),
                      ),
                      trailing: _selecting
                          ? null
                          : (e.progress < 1
                                // кружок загрузки — окно загрузки анализа
                                ? InkResponse(
                                    radius: 22,
                                    onTap: () => _openJob(e.id),
                                    child: SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: switch (analysisQueue.jobs.where((j) => j.id == e.id).firstOrNull) {
                                        final job? => ListenableBuilder(
                                          listenable: job,
                                          builder: (_, _) => JobRing(job: job, stroke: 3),
                                        ),
                                        null => CircularProgressIndicator(value: e.progress, strokeWidth: 3),
                                      },
                                    ),
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // звезда — только у избранной партии; переключение — в меню
                                      if (history.isFavorite(e.id))
                                        const Icon(Icons.star_rounded, color: Color(0xFFF2B01E)),
                                      PopupMenuButton<String>(
                                        onSelected: (a) => switch (a) {
                                          'again' => _reanalyze({e.id}),
                                          'fav' => history.toggleFavorite(e.id),
                                          _ => _delete({e.id}),
                                        },
                                        itemBuilder: (_) => [
                                          PopupMenuItem(
                                            value: 'fav',
                                            child: Text(
                                              history.isFavorite(e.id) ? 'Remove from favourites' : 'Add to favourites',
                                            ),
                                          ),
                                          const PopupMenuItem(value: 'again', child: Text('Analyze again')),
                                          const PopupMenuItem(value: 'delete', child: Text('Delete')),
                                        ],
                                      ),
                                    ],
                                  )),
                      onTap: () => _selecting ? _toggle(e.id) : _open(e.id),
                      onLongPress: () => _toggle(e.id),
                    ),
                ],
              ),
      ),
    );
  }
}
