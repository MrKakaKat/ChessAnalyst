/// Analyses waiting and running on the device's single engine.
///
/// Several games can be queued: they run one after another. The queue is kept
/// on the device; after the app is closed or the analysis is broken off, it
/// comes back on the next start and each game goes on from the position it
/// had reached (the job saves itself every two positions).
///
/// [QueueBadges] shows a ring of progress for each queued game at the bottom
/// right of every screen; a tap opens the analysis screen with pause.
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../analysis/game.dart';
import '../analysis/openings.dart';
import '../analysis/settings.dart';
import '../engine/game_job.dart';
import '../engine/puzzle_rater.dart';
import 'history_screen.dart';
import 'history_store.dart';
import 'job_screen.dart';
import 'notices.dart';
import 'player_stats.dart' show mistakeSnapshot;
import 'puzzle_store.dart';

class AnalysisQueue extends ChangeNotifier {
  static const _key = 'analysis.queue';

  final jobs = <AnalysisJob>[];
  OpeningBook? book;

  /// Navigator of the app, to open an analysis from the rings.
  final navigatorKey = GlobalKey<NavigatorState>();

  /// Adds [job] to the queue (and the history) and starts it when the engine
  /// is free.
  void add(AnalysisJob job) {
    history.track(job);
    if (!jobs.any((j) => j.id == job.id)) {
      jobs.add(job);
      job.addListener(_onJob);
    }
    _save();
    _pump();
    notifyListeners();
  }

  /// Resumes a paused analysis: it goes back into the queue.
  void resume(AnalysisJob job) {
    job.pausedByUser = false;
    add(job);
  }

  /// Sends [job] 4 plies deeper, through the queue.
  void deeper(AnalysisJob job) {
    job.deepen();
    resume(job);
  }

  void remove(AnalysisJob job) {
    job.removeListener(_onJob);
    jobs.remove(job);
    _save();
    _pump();
    notifyListeners();
  }

  /// Starts the first waiting analysis when none is running; one the user
  /// paused waits for them.
  void _pump() {
    if (_holds > 0 || ratingPuzzles || jobs.any((j) => j.state == JobState.running)) return;
    for (final j in jobs) {
      if (!j.done && !j.pausedByUser && j.state != JobState.failed) {
        j.start();
        return;
      }
    }
  }

  void _onJob() {
    final finished = [for (final j in jobs) if (j.done) j];
    for (final j in finished) {
      j.removeListener(_onJob);
      jobs.remove(j);
    }
    if (finished.isNotEmpty) _save();
    for (final j in finished) {
      _toRate.add(j);
      // уведомление: партия разобрана (если пользователь согласился)
      notifyAnalysisDone(j.id.hashCode & 0x7fffffff, j.title);
    }
    _rateNext();
    _pump();
    notifyListeners();
  }

  int _holds = 0;

  /// Runs [work] first: the running analysis pauses while it needs the
  /// engine (a move checked in a puzzle, its consequences) and goes on after.
  Future<T> priority<T>(Future<T> Function() work) async {
    _holds++;
    for (final j in [...jobs.where((j) => j.state == JobState.running)]) {
      j.pause();
      // не пауза пользователя: очередь продолжит сама
      j.pausedByUser = false;
      j.onSave?.call(j);
    }
    try {
      return await work();
    } finally {
      _holds--;
      if (_holds == 0) {
        _pump();
        notifyListeners();
      }
    }
  }

  /// Puzzles of finished analyses are rated by the engine before the next
  /// analysis starts (again after a deeper analysis: the ratings change).
  bool ratingPuzzles = false;
  final _toRate = <AnalysisJob>[];

  Future<void> _rateNext() async {
    if (ratingPuzzles || _toRate.isEmpty) return;
    ratingPuzzles = true;
    notifyListeners();
    try {
      while (_toRate.isNotEmpty) {
        final j = _toRate.removeAt(0);
        final a = analyzeGame(j.snapshot(), const Settings(unit: Unit.pawns), book: book);
        // снимок признаков ошибок: статистика сохранит виды, которые новая
        // версия правил может убрать
        j.tagSnapshot = mistakeSnapshot(a);
        await history.save(j);
        // задачи и ошибки партии — один раз, экран задач их только читает
        final stored = await PuzzleStore.build(j.id, a, puzzles: j.puzzles);
        if (j.puzzles) await ratePuzzles(stored.puzzles, again: true);
      }
    } catch (_) {}
    ratingPuzzles = false;
    _pump();
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_key, [for (final j in jobs) j.id]);
    } catch (_) {}
  }

  /// Brings back the queue saved on the device (on start).
  Future<void> restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      for (final id in p.getStringList(_key) ?? const <String>[]) {
        final job = await history.open(id);
        if (job == null || job.done) continue;
        if (!jobs.any((j) => j.id == id)) {
          jobs.add(job);
          job.addListener(_onJob);
        }
      }
    } catch (_) {}
    _pump();
    notifyListeners();
  }

  /// Opens the history, where all the analyses are (the "+X" ring).
  void openHistory() {
    final b = book;
    if (b == null) return;
    navigatorKey.currentState?.push(MaterialPageRoute<void>(builder: (_) => HistoryScreen(book: b)));
  }

  void open(AnalysisJob job) {
    final b = book;
    if (b == null) return;
    navigatorKey.currentState?.push(MaterialPageRoute<void>(builder: (_) => JobScreen(job: job, book: b, autoOpen: false)));
  }
}

final analysisQueue = AnalysisQueue();

/// Progress rings of the queued analyses, at the bottom right.
class QueueBadges extends StatelessWidget {
  const QueueBadges({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([analysisQueue, ...analysisQueue.jobs]),
        builder: (context, _) {
          final jobs = analysisQueue.jobs;
          // [авторское] на экране — только идущий анализ и один кружок
          // ожидания с числом остальных («+X», ведёт в историю)
          final running = jobs.where((j) => j.state == JobState.running).toList();
          final shown = running.isNotEmpty ? running.take(1).toList() : jobs.take(1).toList();
          final rest = jobs.length - shown.length;
          return Positioned(
            right: 12,
            bottom: 96,
            child: AnimatedSize(
              duration: const Duration(milliseconds: 250),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (rest > 0) Padding(padding: const EdgeInsets.only(top: 8), child: _MoreRing(count: rest)),
                for (final j in shown.reversed) Padding(padding: const EdgeInsets.only(top: 8), child: _Ring(job: j)),
              ]),
            ),
          );
        },
      );
}

class _Ring extends StatelessWidget {
  const _Ring({required this.job});

  final AnalysisJob job;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final failed = job.state == JobState.failed;
    final running = job.state == JobState.running;
    // без Tooltip: кружки стоят над навигатором, где нет Overlay
    return Semantics(
      label: '${job.title} · ${(job.progress * 100).round()}%',
      child: Material(
        color: scheme.surfaceContainerHigh,
        shape: const CircleBorder(),
        elevation: 4,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => analysisQueue.open(job),
          child: SizedBox.square(
            dimension: 46,
            child: Stack(alignment: Alignment.center, children: [
              Padding(padding: const EdgeInsets.all(4), child: SizedBox.expand(child: JobRing(job: job))),
              if (running)
                Text('${(job.progress * 100).round()}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800))
              else
                Icon(failed ? Icons.error_outline_rounded : Icons.pause_rounded, size: 18),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The ring of one analysis: its progress, and inside a thin circle that
/// glows while the engine computes (dark while it rests between positions,
/// is paused or waits).
class JobRing extends StatelessWidget {
  const JobRing({super.key, required this.job, this.stroke = 3.5});

  final AnalysisJob job;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final failed = job.state == JobState.failed;
    final busy = job.state == JobState.running && job.thinking;
    return Stack(fit: StackFit.expand, children: [
      CircularProgressIndicator(
        value: job.progress,
        strokeWidth: stroke,
        color: failed ? scheme.error : null,
        backgroundColor: scheme.surfaceContainerHighest,
      ),
      Padding(
        padding: EdgeInsets.all(stroke + 2.5),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: busy ? scheme.primary : scheme.surfaceContainerHighest,
              width: 1.6,
            ),
            boxShadow: busy ? [BoxShadow(color: scheme.primary.withValues(alpha: 0.35), blurRadius: 4)] : null,
          ),
        ),
      ),
    ]);
  }
}

/// The waiting ring: the analyses in the queue besides the running one;
/// opens the history.
class _MoreRing extends StatelessWidget {
  const _MoreRing({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '$count more analyses',
      child: Material(
        color: scheme.surfaceContainerHigh,
        shape: const CircleBorder(),
        elevation: 4,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: analysisQueue.openHistory,
          child: SizedBox.square(
            dimension: 46,
            // кружок ожидания: пустое кольцо, часы и число партий в очереди
            child: Stack(alignment: Alignment.center, children: [
              Padding(
                padding: const EdgeInsets.all(4),
                child: SizedBox.expand(
                  child: CircularProgressIndicator(
                      value: 0, strokeWidth: 3.5, backgroundColor: scheme.surfaceContainerHighest),
                ),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.hourglass_top_rounded, size: 12, color: scheme.outline),
                Text('+$count', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, height: 1)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
